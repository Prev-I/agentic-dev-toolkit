#!/usr/bin/env python3
"""Shared OpenCode 2.x config helper.

Usage: v2config.py load FILE | shape FILE | md-frontmatter FILE
       v2config.py layers API_CONFIG_JSON SANDBOX
       v2config.py build-config BASE_JSON_OR_- FRAGMENT AGENT_ROW_JSON_OR_- OUT
       v2config.py real-dirs
       v2config.py redact SOURCE... -- PATH...
Exit codes: 0 success, 1 finding, 2 usage or unparseable input.

layers: 0 when every layer of a GET /api/config answer passes check_layers;
  1 with one "  - <problem>" line per problem on stderr.
build-config: BASE (a profile file, or - for a minimal config), FRAGMENT (a
  file holding only `providers` and `policies`; any other key exits 2) and
  AGENT_ROW (a file holding {"name": N, "row": {...}}, or -) are merged into
  OUT as strict JSON, always with "update": "disable".
real-dirs: the OpenCode directories a sandbox must not resolve inside.
redact: every string value of 12 or more characters anywhere in each SOURCE
  (JSON or JSONC, read recursively; a SOURCE that does not parse contributes
  each whitespace-separated token of that length) is searched for, verbatim and
  JSON-escaped, in every regular file under each PATH (a file or a directory;
  symlinks are not followed, a missing PATH is skipped), and each occurrence is
  replaced in place with [REDACTED]. 0 when nothing was found; 1 when something
  was redacted, with one "redact: a credential was redacted in FILE" line per
  file on stdout; 2 when a SOURCE cannot be read. No secret is ever printed.
"""
import fnmatch
import json
import os
import pwd
import re
import sys

V1_KEYS = ("agent", "provider", "permission", "plugin",
           "disabled_providers", "autoupdate", "server")


def strip_jsonc(raw):
    """Remove // and /* */ comments and trailing commas, string-aware."""
    out = []
    index = 0
    size = len(raw)
    in_string = False
    escaped = False
    while index < size:
        char = raw[index]
        if in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            index += 1
            continue
        if char == "/" and index + 1 < size and raw[index + 1] == "/":
            while index < size and raw[index] != "\n":
                index += 1
            continue
        if char == "/" and index + 1 < size and raw[index + 1] == "*":
            index += 2
            while index + 1 < size and not (raw[index] == "*" and raw[index + 1] == "/"):
                index += 1
            index += 2
            continue
        out.append(char)
        index += 1
    # Trailing commas: only outside strings, so rescan with the same state.
    text = "".join(out)
    result = []
    in_string = False
    escaped = False
    for pos, char in enumerate(text):
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            result.append(char)
            continue
        if char == ",":
            rest = text[pos + 1:].lstrip()
            if rest[:1] in ("}", "]"):
                continue
        result.append(char)
    return "".join(result)


def load(path):
    with open(path, encoding="utf-8-sig") as handle:
        return json.loads(strip_jsonc(handle.read()))


def mixed_shape_keys(document):
    """The V1 markers in a parsed config: V1 top-level keys, and `mcp` as an
    object without `servers`. Empty for a pure V2 document."""
    found = [key for key in V1_KEYS if key in document]
    mcp = document.get("mcp")
    if isinstance(mcp, dict) and "servers" not in mcp:
        found.append("mcp without servers")
    return found


def shape(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return "empty"
    try:
        document = load(path)
    except (ValueError, OSError):
        print("invalid")
        return None
    if not isinstance(document, dict):
        print("invalid")
        return None
    if mixed_shape_keys(document):
        return "v1"
    return "v2"


class FrontmatterError(Exception):
    pass


def scalar(text):
    """Parse one scalar; refuse anything a real YAML parser would read differently."""
    text = text.strip()
    if text == "":
        raise FrontmatterError("empty scalar")
    if text[0] == '"':
        if len(text) < 2 or text[-1] != '"':
            raise FrontmatterError("unsupported quoted scalar: " + text)
        try:
            return json.loads(text)
        except ValueError:
            raise FrontmatterError("bad quoted scalar: " + text)
    if text[0] == "'":
        if len(text) < 2 or text[-1] != "'" or "'" in text[1:-1]:
            raise FrontmatterError("unsupported quoted scalar: " + text)
        return text[1:-1]
    if text[0] in "[{&*!|>%@`#":
        raise FrontmatterError("unsupported scalar: " + text)
    if " #" in text or ": " in text or text.endswith(":"):
        raise FrontmatterError("ambiguous unquoted scalar: " + text)
    if text in ("true", "false"):
        return text == "true"
    if text == "null":
        return None
    if text.lower() in ("true", "false", "null", "yes", "no", "on", "off", "~") \
            or re.fullmatch(r"[-+.\d][\w.+-]*", text) and re.search(r"\d", text) \
            and not re.fullmatch(r"-?\d+(\.\d+)?", text):
        raise FrontmatterError("unsupported scalar spelling: " + text)
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    return text


def split_key(text):
    match = re.match(r'^("[^"]*"|[A-Za-z_][\w-]*):(?:\s+(.*))?$', text)
    if not match:
        raise FrontmatterError("not a key line: " + text)
    key = match.group(1)
    if key.startswith('"'):
        key = key[1:-1]
    return key, match.group(2)


def parse_frontmatter(lines):
    result = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        if line[0] in " \t":
            raise FrontmatterError("unexpected indent: " + line)
        key, value = split_key(line)
        if key in result:
            raise FrontmatterError("duplicate key: " + key)
        index += 1
        if value is not None:
            result[key] = scalar(value)
            continue
        block = []
        while index < len(lines) and (not lines[index].strip() or lines[index][0] in " \t"):
            if lines[index].strip():
                block.append(lines[index])
            index += 1
        if key == "permissions":
            result[key] = parse_permissions_list(block)
        elif key == "permission":
            result[key] = parse_permission_map(block)
        else:
            raise FrontmatterError("unsupported block key: " + key)
    return result


def parse_permissions_list(block):
    entries = []
    for line in block:
        stripped = line.strip()
        if stripped.startswith("- "):
            entries.append({})
            stripped = stripped[2:]
        elif not entries:
            raise FrontmatterError("permissions must be a list of mappings")
        key, value = split_key(stripped)
        if value is None:
            raise FrontmatterError("nested value in permissions entry")
        if key in entries[-1]:
            raise FrontmatterError("duplicate key in permissions entry: " + key)
        entries[-1][key] = scalar(value)
    for entry in entries:
        if set(entry) != {"action", "resource", "effect"}:
            raise FrontmatterError("permissions entries need action, resource, effect")
    return entries


def parse_permission_map(block):
    result = {}
    current = None
    for line in block:
        indent = len(line) - len(line.lstrip())
        key, value = split_key(line.strip())
        if (indent == 2 and key in result) or (
                indent == 4 and current is not None and key in result[current]):
            raise FrontmatterError("duplicate key: " + key)
        if indent == 2:
            if value is None:
                result[key] = {}
                current = key
            else:
                result[key] = scalar(value)
                current = None
        elif indent == 4 and current is not None and value is not None:
            result[current][key] = scalar(value)
        else:
            raise FrontmatterError("unsupported permission nesting: " + line)
    return result


def md_frontmatter(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    if not lines or lines[0].strip() != "---":
        raise FrontmatterError("no frontmatter")
    for end in range(1, len(lines)):
        if lines[end].strip() == "---":
            return parse_frontmatter(lines[1:end])
    raise FrontmatterError("unterminated frontmatter")


def assistant_uses(entries):
    """The distinct `agent@provider/model#variant` values of a session's assistant
    messages (the array V2_PICK_ASSISTANT emits), sorted. Empty when `entries`
    is not a non-empty list of objects with a model object."""
    if not isinstance(entries, list):
        return []
    uses = set()
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("model"), dict):
            continue
        model = entry["model"]
        uses.add(f"{entry.get('agent')}@{model.get('providerID')}/{model.get('id')}#{model.get('variant')}")
    return sorted(uses)


def breakglass_decision(permissions, agent_name="breakglass"):
    """The effective permission entry that decides a subagent call to AGENT_NAME.

    Among the entries whose action is `subagent` or `*` and whose resource
    glob-matches the agent name, the LAST one decides; None when none matches.
    """
    deciding = None
    if not isinstance(permissions, list):
        return None
    for entry in permissions:
        if not isinstance(entry, dict):
            continue
        if (entry.get("action") in ("subagent", "*")
                and fnmatch.fnmatchcase(agent_name, str(entry.get("resource", "")))):
            deciding = entry
    return deciding


# What the account's ~/.opencode may not hold for a sandboxed server to count
# as loading only its sandbox.
ACCOUNT_OPENCODE_FORBIDDEN = ("opencode.json", "opencode.jsonc", "agents", "agent",
                              "command", "plugins")


def _inside(path, root):
    real = os.path.realpath(path)
    return real == root or real.startswith(root + os.sep)


def check_layers(layers, sandbox):
    """The problems with a server's config layers, empty when clean: each layer
    must be inside SANDBOX, or be the account's ~/.opencode holding none of
    ACCOUNT_OPENCODE_FORBIDDEN."""
    sandbox = os.path.realpath(sandbox)
    account = os.path.realpath(os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".opencode"))
    bad = []
    for layer in layers:
        path = layer.get("path") if isinstance(layer, dict) else None
        if not isinstance(path, str) or not path:
            # Never the layer itself: its `info` is the effective config,
            # provider settings and keys included.
            if isinstance(layer, dict):
                kind = layer.get("type")
                kind = kind[:40] if isinstance(kind, str) else type(kind).__name__
                bad.append("a layer with no path (type %s, keys %s)" % (kind, sorted(layer)))
            else:
                bad.append("a layer with no path (a %s, not an object)" % type(layer).__name__)
        elif _inside(path, sandbox):
            continue
        elif os.path.realpath(path) == account:
            held = [n for n in ACCOUNT_OPENCODE_FORBIDDEN
                    if os.path.lexists(os.path.join(account, n))]
            if held:
                bad.append("%s holds %s" % (path, ", ".join(held)))
        else:
            bad.append("%s (%s) is outside the sandbox" % (path, layer.get("type")))
    return bad


FRAGMENT_KEYS = ("providers", "policies")


def build_config(base, fragment, agent_row):
    """BASE (a dict, or None for the minimal config) with FRAGMENT's providers
    merged over its own and its policies appended, and AGENT_ROW placed at
    agents.<name>. Raises ValueError on a malformed input."""
    if base is None:
        base = {"$schema": "https://opencode.ai/config.json", "update": "disable"}
    if not isinstance(base, dict):
        raise ValueError("the base is not a JSON object")
    if not isinstance(fragment, dict):
        raise ValueError("the fragment is not a JSON object")
    extra = sorted(set(fragment) - set(FRAGMENT_KEYS))
    if extra:
        raise ValueError("the fragment may hold only %s; it also holds %s"
                         % (", ".join(FRAGMENT_KEYS), ", ".join(extra)))
    result = json.loads(json.dumps(base))
    providers = fragment.get("providers", {})
    if not isinstance(providers, dict):
        raise ValueError("the fragment's providers is not an object")
    if providers:
        merged = result.get("providers")
        merged = dict(merged) if isinstance(merged, dict) else {}
        merged.update(providers)
        result["providers"] = merged
    policies = fragment.get("policies", [])
    if not isinstance(policies, list):
        raise ValueError("the fragment's policies is not a list")
    if policies:
        existing = result.get("policies")
        result["policies"] = (list(existing) if isinstance(existing, list) else []) + policies
    if agent_row is not None:
        if (not isinstance(agent_row, dict) or set(agent_row) != {"name", "row"}
                or not isinstance(agent_row["name"], str) or not agent_row["name"]
                or not isinstance(agent_row["row"], dict)):
            raise ValueError('the agent row must be {"name": N, "row": {...}}')
        agents = result.get("agents")
        agents = dict(agents) if isinstance(agents, dict) else {}
        agents[agent_row["name"]] = agent_row["row"]
        result["agents"] = agents
    result["update"] = "disable"
    return result


def real_dirs():
    """The account's OpenCode directories, and the XDG ones when set."""
    home = pwd.getpwuid(os.getuid()).pw_dir
    dirs = [os.path.join(home, ".config", "opencode"),
            os.path.join(home, ".local", "share", "opencode"),
            os.path.join(home, ".local", "state", "opencode"),
            os.path.join(home, ".opencode")]
    for name in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"):
        value = os.environ.get(name)
        if value:
            dirs.append(os.path.join(value, "opencode"))
    return dirs


def _layers_command(api_path, sandbox):
    try:
        with open(api_path) as handle:
            layers = json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("layers: %s\n" % error)
        return 2
    if not isinstance(layers, list):
        sys.stderr.write("layers: %s is not a list of layers\n" % api_path)
        return 2
    bad = check_layers(layers, sandbox)
    sys.stderr.write("".join("  - %s\n" % b for b in bad))
    return 1 if bad else 0


def _build_config_command(base_path, fragment_path, row_path, out):
    try:
        base = None if base_path == "-" else load(base_path)
        fragment = load(fragment_path)
        row = None if row_path == "-" else load(row_path)
        result = build_config(base, fragment, row)
    except (OSError, ValueError) as error:
        sys.stderr.write("build-config: %s\n" % error)
        return 2
    with open(out, "w") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")
    return 0


REDACT_MIN = 12
REDACTED = b"[REDACTED]"


def _secret_strings(value, found):
    if isinstance(value, str):
        if len(value) >= REDACT_MIN:
            found.add(value)
    elif isinstance(value, dict):
        for item in value.values():
            _secret_strings(item, found)
    elif isinstance(value, list):
        for item in value:
            _secret_strings(item, found)


def secret_needles(sources):
    """The byte strings to redact: each secret verbatim and JSON-escaped
    (ASCII-only and not), longest first. Raises OSError on an unreadable
    source."""
    secrets = set()
    for source in sources:
        with open(source, encoding="utf-8-sig", errors="replace") as handle:
            text = handle.read()
        try:
            _secret_strings(json.loads(strip_jsonc(text)), secrets)
        except ValueError:
            secrets.update(t for t in text.split() if len(t) >= REDACT_MIN)
    needles = set()
    for secret in secrets:
        needles.add(secret.encode("utf-8"))
        for ascii_only in (True, False):
            needles.add(json.dumps(secret, ensure_ascii=ascii_only)[1:-1].encode("utf-8"))
    return sorted(needles, key=len, reverse=True)


def _files_under(path):
    if os.path.islink(path):
        return
    if os.path.isfile(path):
        yield path
        return
    for directory, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(directory, d))]
        for name in sorted(files):
            full = os.path.join(directory, name)
            if os.path.isfile(full) and not os.path.islink(full):
                yield full


def redact(sources, paths):
    """Redact SOURCES' secrets in place under PATHS; the files changed."""
    needles = secret_needles(sources)
    changed = []
    for path in paths:
        for name in _files_under(path):
            with open(name, "rb") as handle:
                data = handle.read()
            new = data
            for needle in needles:
                new = new.replace(needle, REDACTED)
            if new != data:
                with open(name, "r+b") as handle:
                    handle.write(new)
                    handle.truncate()
                changed.append(name)
    return changed


def _redact_command(args):
    if "--" not in args:
        return usage()
    split = args.index("--")
    sources, paths = args[:split], args[split + 1:]
    if not sources:
        return usage()
    try:
        changed = redact(sources, paths)
    except OSError as error:
        sys.stderr.write("redact: cannot read a source or a file (%s)\n" % error.strerror)
        return 2
    for name in changed:
        print("redact: a credential was redacted in %s" % name)
    return 1 if changed else 0


def usage():
    sys.stderr.write(__doc__)
    return 2


def main(argv):
    if len(argv) == 4 and argv[1] == "layers":
        return _layers_command(argv[2], argv[3])
    if len(argv) == 6 and argv[1] == "build-config":
        return _build_config_command(*argv[2:])
    if len(argv) >= 2 and argv[1] == "redact":
        return _redact_command(argv[2:])
    if len(argv) == 2 and argv[1] == "real-dirs":
        for path in real_dirs():
            print(path)
        return 0
    if len(argv) != 3 or argv[1] not in ("load", "shape", "md-frontmatter"):
        return usage()
    command, path = argv[1], argv[2]
    if command == "shape":
        kind = shape(path)
        if kind is None:
            return 1
        print(kind)
        return 0
    try:
        document = load(path) if command == "load" else md_frontmatter(path)
    except (OSError, ValueError, FrontmatterError) as error:
        sys.stderr.write("%s: %s\n" % (command, error))
        return 2
    json.dump(document, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
