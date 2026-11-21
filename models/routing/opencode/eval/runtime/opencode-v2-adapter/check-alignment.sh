#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
v2_alignment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Alignment check (OpenCode 2): does the INSTALLED, user-global configuration
# still match this repository's V2 routing bundle?
#
#   check_alignment_v2 --profile FILE --targets FILE --bundle-root DIR \
#     --live-config FILE --live-support-root DIR [--json OUT]
#
# Reports and changes nothing; it never repairs. Exit 0 for ALIGNED or STALE,
# 1 for DRIFT, 2 for usage or an absent installation.
#
#   DRIFT -- a routing-owned key, or an agent file's frontmatter, differs.
#   STALE -- prose only: an agent file's body, or model-routing.md.
#
# Routing-owned keys (the ones activate_profile_v2 writes): top-level `model`;
# `agents.<role>` for every role in the targets manifest, whole row; the
# top-level `permissions` entries whose action is `subagent`, compared in
# order because the last match wins; and exactly one `instructions` entry equal
# to the absolute path of the installed model-routing.md. Everything else is
# user-owned and never reported, with one exception: the top-level entry that
# decides a subagent call to the breakglass agent (the last `subagent` or `*`
# entry whose resource matches it, as the verifier computes it) must be a deny,
# so a user `* * allow` placed after the subagent rules is DRIFT. With --json,
# an existing OUT is removed first, so a failed run never leaves an old report.
#
# Not ported from the 1.x checker: the STALE_PROCESS warning. On 2.x the oracle
# for what the runtime actually resolves is the running server's API
# (verify-effective-routing.sh), not process start times against the config
# mtime; this check compares files only.

check_alignment_v2() {
  local profile="" targets="" bundle_root="" live_config="" live_support="" json_out=""
  while (( $# )); do
    case "$1" in
      --profile|--targets|--bundle-root|--live-config|--live-support-root|--json)
        (( $# >= 2 )) || { printf 'check_alignment_v2: %s needs a value\n' "$1" >&2; return 2; }
        case "$1" in
          --profile) profile=$2 ;;
          --targets) targets=$2 ;;
          --bundle-root) bundle_root=$2 ;;
          --live-config) live_config=$2 ;;
          --live-support-root) live_support=$2 ;;
          --json) json_out=$2 ;;
        esac
        shift 2 ;;
      *) printf 'check_alignment_v2: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  # Never leave an earlier report behind: a failed run must not read as ALIGNED.
  [[ -z "$json_out" ]] || rm -f -- "$json_out"
  [[ -n "$profile" && -n "$targets" && -n "$bundle_root" && -n "$live_config" ]] || {
    printf 'usage: check_alignment_v2 --profile FILE --targets FILE --bundle-root DIR --live-config FILE --live-support-root DIR [--json OUT]\n' >&2
    return 2
  }
  [[ -n "$live_support" ]] || live_support=$(dirname "$live_config")

  [[ -f "$profile" ]] || { printf 'check_alignment_v2: no such profile: %s\n' "$profile" >&2; return 2; }
  [[ -f "$targets" ]] || { printf 'check_alignment_v2: no such targets manifest: %s\n' "$targets" >&2; return 2; }
  if [[ ! -f "$live_config" ]]; then
    printf 'check_alignment_v2: no installed configuration at %s\n' "$live_config" >&2
    printf 'check_alignment_v2: nothing to compare -- is the bundle installed?\n' >&2
    return 2
  fi

  local helper="$v2_alignment_root/v2config.py" profile_shape live_shape
  profile_shape=$(python3 -I -B "$helper" shape "$profile") || profile_shape=invalid
  [[ "$profile_shape" == v2 ]] || {
    printf 'check_alignment_v2: profile is not a V2 config (%s): %s\n' "$profile_shape" "$profile" >&2
    return 2
  }
  live_shape=$(python3 -I -B "$helper" shape "$live_config") || live_shape=invalid
  if [[ "$live_shape" == invalid ]]; then
    printf 'check_alignment_v2: %s is not parseable JSON/JSONC\n' "$live_config" >&2
    return 1
  fi

  PROFILE_PATH="$profile" TARGETS="$targets" BUNDLE_ROOT="$bundle_root" \
    LIVE_CONFIG_PATH="$live_config" LIVE_SUPPORT="$live_support" \
    LIVE_SHAPE="$live_shape" JSON_OUT="$json_out" HELPER_DIR="$v2_alignment_root" \
    python3 -I -B <<'PY'
import datetime
import hashlib
import json
import os
import sys
import tempfile

sys.path.insert(0, os.environ["HELPER_DIR"])
import v2config  # noqa: E402

profile_path = os.environ["PROFILE_PATH"]
live_config = os.environ["LIVE_CONFIG_PATH"]
bundle_root = os.environ["BUNDLE_ROOT"]
live_support = os.environ["LIVE_SUPPORT"]
live_shape = os.environ["LIVE_SHAPE"]

repo = v2config.load(profile_path)
targets = v2config.load(os.environ["TARGETS"])
roles = list(targets["agents"])
installed_routing = os.path.abspath(os.path.join(live_support, "model-routing.md"))

drift = []
stale = []

def render(value):
    return json.dumps(value, indent=2, sort_keys=True)

def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

if live_shape == "v1":
    drift.append({"kind": "config", "key": "shape",
                  "detail": "live config is OpenCode 1.x-shaped; run convert-v1-config"})
    live = {}
else:
    live = v2config.load(live_config) if live_shape == "v2" else {}

if live_shape != "v1":
    if repo.get("model") != live.get("model"):
        drift.append({"kind": "config", "key": "model",
                      "expected": render(repo.get("model")), "actual": render(live.get("model")),
                      "detail": "top-level default model"})

    for role in roles:
        repo_row = repo.get("agents", {}).get(role)
        live_row = live.get("agents", {}).get(role) if isinstance(live.get("agents"), dict) else None
        if repo_row is None:
            drift.append({"kind": "config", "key": f"agents.{role}",
                          "expected": "<declared in targets manifest>",
                          "actual": "<missing from repository profile>",
                          "detail": "targets manifest declares a role the profile does not define"})
        elif live_row is None:
            drift.append({"kind": "config", "key": f"agents.{role}",
                          "expected": render(repo_row), "actual": "<missing>",
                          "detail": "role is absent from the installed configuration"})
        elif repo_row != live_row:
            diffs = [{"subkey": key, "expected": render(repo_row.get(key)),
                      "actual": render(live_row.get(key))}
                     for key in sorted(set(repo_row) | set(live_row))
                     if repo_row.get(key) != live_row.get(key)]
            drift.append({"kind": "config", "key": f"agents.{role}",
                          "differing_subkeys": diffs,
                          "detail": f"routing-owned agent row for {role}"})

    def subagent_entries(document):
        entries = document.get("permissions")
        if not isinstance(entries, list):
            return []
        return [e for e in entries if isinstance(e, dict) and e.get("action") == "subagent"]

    if subagent_entries(repo) != subagent_entries(live):
        drift.append({"kind": "config", "key": "permissions[action=subagent]",
                      "expected": render(subagent_entries(repo)),
                      "actual": render(subagent_entries(live)),
                      "detail": "top-level subagent rules, in order (the Breakglass containment control)"})

    # The runtime also matches `*` actions, so an extra user entry such as
    # `* * allow` after the subagent rules re-opens Breakglass even while the
    # subagent entries match. Decide it exactly as the verifier does.
    breakglass_agent = (targets.get("breakglass") or {}).get("agent") or "breakglass"
    deciding = v2config.breakglass_decision(live.get("permissions"), breakglass_agent)
    if not (isinstance(deciding, dict) and deciding.get("effect") == "deny"):
        drift.append({"kind": "config", "key": "permissions[breakglass]",
                      "expected": f"the last subagent/* entry matching {breakglass_agent} is a deny",
                      "actual": render(deciding),
                      "detail": "the deciding top-level entry for a subagent call to "
                                f"{breakglass_agent} is {json.dumps(deciding)}, not a deny"})

    # Ownership is decided exactly as activation does: by the raw basename. A
    # variant such as a trailing-slash path has an empty basename, so it is
    # user-owned and ignored. The expected entry is the installed absolute path
    # (activation writes it normalised); any other owned entry is extra.
    instructions = live.get("instructions")
    entries = instructions if isinstance(instructions, list) else []
    owned = [i for i in entries if isinstance(i, str) and os.path.basename(i) == "model-routing.md"]
    matches = [i for i in owned if i == installed_routing]
    extras = [i for i in owned if i != installed_routing]
    if len(matches) != 1 or extras:
        problem = "extra model-routing.md entry" if extras else "expected model-routing.md entry missing"
        drift.append({"kind": "config", "key": "instructions",
                      "expected": f"exactly one model-routing.md entry, equal to {installed_routing}",
                      "actual": render(instructions),
                      "detail": f"the installed model-routing.md instruction: {problem}"})

# --- support files ----------------------------------------------------------

UNDECODABLE = object()

def read_text(path):
    """Text without a leading BOM; None when absent; UNDECODABLE when not UTF-8."""
    try:
        with open(path, encoding="utf-8-sig") as handle:
            return handle.read()
    except UnicodeDecodeError:
        return UNDECODABLE
    except OSError:
        return None

def has_bom(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(3) == b"\xef\xbb\xbf"
    except OSError:
        return False

def front_of_text(text):
    """md_frontmatter on already-decoded text (BOM stripped)."""
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".md", delete=False) as tmp:
        tmp.write(text)
    try:
        return v2config.md_frontmatter(tmp.name)
    finally:
        os.unlink(tmp.name)

PARSE_ERRORS = (OSError, ValueError, v2config.FrontmatterError)

def body_of(text):
    lines = text.split("\n")
    for end in range(1, len(lines)):
        if lines[end].strip() == "---":
            return "\n".join(lines[end + 1:])
    return text

bundle_agents = os.path.join(bundle_root, "agents")
try:
    agent_names = sorted(e[:-3] for e in os.listdir(bundle_agents) if e.endswith(".md"))
except OSError:
    agent_names = []
if not agent_names:
    drift.append({"kind": "support", "file": "agents/",
                  "detail": "no agent markdown found in the repository bundle",
                  "expected": bundle_agents, "actual": "<none>"})

for name in agent_names:
    label = f"agents/{name}.md"
    repo_file = os.path.join(bundle_agents, f"{name}.md")
    live_file = os.path.join(live_support, "agents", f"{name}.md")
    repo_text, live_text = read_text(repo_file), read_text(live_file)
    if live_text is None:
        drift.append({"kind": "support", "file": label, "detail": "not installed",
                      "expected": "<present in bundle>", "actual": "<missing>"})
        continue
    if live_text is UNDECODABLE:
        drift.append({"kind": "support", "file": label,
                      "detail": "installed file is not valid UTF-8 (unparseable)",
                      "expected": "<valid UTF-8>", "actual": "<undecodable>"})
        continue
    if repo_text is None or repo_text is UNDECODABLE:
        drift.append({"kind": "support", "file": label,
                      "detail": "repository bundle file is missing or unreadable (unparseable)",
                      "expected": "<parseable frontmatter>", "actual": "<unparseable>"})
        continue
    try:
        repo_front = front_of_text(repo_text)
    except PARSE_ERRORS as error:
        drift.append({"kind": "support", "file": label,
                      "detail": f"repository bundle file is unparseable ({error})",
                      "expected": "<parseable frontmatter>", "actual": "<unparseable>"})
        continue
    bom_note = " (a leading UTF-8 BOM was stripped)" if has_bom(live_file) else ""
    try:
        live_front = front_of_text(live_text)
    except PARSE_ERRORS as error:
        drift.append({"kind": "support", "file": label,
                      "detail": f"installed file is unparseable ({error}){bom_note}",
                      "expected": render(repo_front), "actual": "<unparseable>"})
        continue
    if "permission" in live_front:
        drift.append({"kind": "support", "file": label,
                      "detail": "installed file has OpenCode 1.x-shaped frontmatter (permission key)" + bom_note,
                      "expected": render(repo_front), "actual": render(live_front)})
    elif "model" in live_front:
        drift.append({"kind": "support", "file": label,
                      "detail": "installed file sets a model: the bundle keeps model routing in opencode.jsonc" + bom_note,
                      "expected": render(repo_front), "actual": render(live_front)})
    elif repo_front != live_front:
        drift.append({"kind": "support", "file": label,
                      "detail": "frontmatter differs -- permissions are a security boundary" + bom_note,
                      "expected": render(repo_front), "actual": render(live_front)})
    elif body_of(repo_text) != body_of(live_text):
        stale.append({"kind": "support", "file": label,
                      "detail": "frontmatter matches; prose differs" + bom_note,
                      "expected_sha256": digest(repo_text), "actual_sha256": digest(live_text)})

# An agent file present ONLY in the install, naming a role this bundle routes,
# can shadow a routing-owned row while the JSON still matches. The bundle ships
# nothing to verify it against, so a permissions/permission/model key or an
# unparseable file is drift; plain description/mode is the user's business.
try:
    live_agent_files = sorted(
        e[:-3] for e in os.listdir(os.path.join(live_support, "agents")) if e.endswith(".md"))
except OSError:
    live_agent_files = []
for name in live_agent_files:
    if name in agent_names or name not in roles:
        continue
    label = f"agents/{name}.md"
    text = read_text(os.path.join(live_support, "agents", f"{name}.md"))
    try:
        if text is None:
            raise ValueError("cannot be read")
        if text is UNDECODABLE:
            raise ValueError("not valid UTF-8")
        front = front_of_text(text)
    except PARSE_ERRORS as error:
        drift.append({"kind": "support", "file": label,
                      "detail": f"installed-only agent file for routed role '{name}' is unparseable ({error})",
                      "expected": "<not shipped by this bundle>", "actual": "<unparseable>"})
        continue
    if {"permissions", "permission", "model"} & set(front):
        drift.append({"kind": "support", "file": label,
                      "detail": f"installed-only agent file for routed role '{name}' carries permissions or a model, "
                                "which can override the routing-owned row; the bundle ships nothing to verify it against",
                      "expected": "<not shipped by this bundle>", "actual": render(front)})

repo_routing = read_text(os.path.join(bundle_root, "model-routing.md"))
live_routing = read_text(os.path.join(live_support, "model-routing.md"))
if repo_routing is None:
    drift.append({"kind": "support", "file": "model-routing.md",
                  "detail": "missing from the repository bundle",
                  "expected": "<present>", "actual": "<missing>"})
elif live_routing is UNDECODABLE or repo_routing is UNDECODABLE:
    drift.append({"kind": "support", "file": "model-routing.md",
                  "detail": "file is not valid UTF-8 (unparseable)",
                  "expected": "<valid UTF-8>", "actual": "<undecodable>"})
elif live_routing is None:
    drift.append({"kind": "support", "file": "model-routing.md",
                  "detail": "not installed -- the routing policy the controller loads is absent",
                  "expected": "<present in bundle>", "actual": "<missing>"})
elif repo_routing != live_routing:
    stale.append({"kind": "support", "file": "model-routing.md",
                  "detail": "installed routing policy differs from the bundle; a stale copy misdescribes the active routing",
                  "expected_sha256": digest(repo_routing), "actual_sha256": digest(live_routing)})

# --- report -----------------------------------------------------------------

status = "DRIFT" if drift else ("STALE" if stale else "ALIGNED")
document = {
    "checked_at": datetime.datetime.now().astimezone().isoformat(),
    "status": status,
    "profile": profile_path,
    "installed_configuration": live_config,
    "routing_owned_keys": ["model", "permissions[action=subagent]", "instructions"]
                          + [f"agents.{r}" for r in roles],
    "auto_repair": False,
    "drift": drift,
    "stale": stale,
}
out = os.environ.get("JSON_OUT") or ""
if out:
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

def show(item):
    if "differing_subkeys" in item:
        print(f"  {item['key']} ({item['detail']})")
        for sub in item["differing_subkeys"]:
            print(f"    .{sub['subkey']}")
            print(f"      repository: {sub['expected']}")
            print(f"      installed:  {sub['actual']}")
        return
    label = item.get("key") or item.get("file")
    print(f"  {label} ({item['detail']})")
    if "expected" in item:
        print(f"    repository: {item['expected']}")
        print(f"    installed:  {item['actual']}")

if drift:
    print("DRIFT -- installed configuration differs from the repository on routing-owned keys:")
    for item in drift:
        show(item)
if stale:
    print("STALE -- support files differ in prose only (frontmatter matches):")
    for item in stale:
        show(item)
if status == "ALIGNED":
    print("ALIGNED -- installed configuration matches the repository bundle.")
if drift:
    print()
    print("Nothing was changed. Drift is sometimes deliberate -- decide per item,")
    print("then either sync the installed file or correct the repository.")

raise SystemExit(1 if drift else 0)
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then check_alignment_v2 "$@"; fi
