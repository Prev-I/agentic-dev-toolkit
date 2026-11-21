#!/usr/bin/env python3
"""Shared OpenCode 2.x config helper.

Usage: v2config.py load FILE | shape FILE | md-frontmatter FILE
Exit codes: 0 success, 1 finding, 2 usage or unparseable input.
"""
import fnmatch
import json
import os
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


def usage():
    sys.stderr.write(__doc__)
    return 2


def main(argv):
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
