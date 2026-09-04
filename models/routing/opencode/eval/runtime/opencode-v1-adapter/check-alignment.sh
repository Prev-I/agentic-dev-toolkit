#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
alignment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$alignment_root/load-routing-profile.sh"

# Alignment check: does the INSTALLED, user-global OpenCode configuration
# still match this repository's canonical routing bundle?
#
# This is an operational integrity check, not evaluation machinery. It makes
# no model calls and changes nothing -- it reports and exits non-zero on
# drift, leaving every decision to a human. Drift is sometimes deliberate
# (see the git-push ask/deny correction of 2026-09-04), so this tool must
# never auto-repair.
#
# Two severities, deliberately separated:
#
#   DRIFT -- routing-owned configuration keys, or an agent's permission
#            frontmatter, differ from the repository. Security- and
#            routing-relevant. Exits non-zero.
#   STALE -- a support file's prose differs while its permissions still
#            match. Informational; does not fail the check.
#
# Conflating those two would make this noisy, and a check that cries wolf is
# one people stop reading. The `verify_effective_routing` sibling answers a
# different question (does the RUNTIME resolve roles as declared?); this one
# asks whether the FILES on disk still match the repository.
#
# Scope of "routing-owned" is taken verbatim from activate-profile.sh:
# the top-level `model`, the top-level `permission.task`, and the declared
# agent rows -- whole objects, including their permission blocks. Every
# other key in the live configuration is user-owned and is never reported.

check_alignment() {
  local profile="" targets="" bundle_root="" live_config="" live_support="" json_out=""
  while (( $# )); do
    case "$1" in
      --profile) profile=$2; shift 2 ;;
      --targets) targets=$2; shift 2 ;;
      --bundle-root) bundle_root=$2; shift 2 ;;
      --live-config) live_config=$2; shift 2 ;;
      --live-support-root) live_support=$2; shift 2 ;;
      --json) json_out=$2; shift 2 ;;
      *) printf 'check_alignment: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$profile" && -n "$targets" && -n "$bundle_root" && -n "$live_config" ]] || return 2
  [[ -n "$live_support" ]] || live_support=$(dirname "$live_config")

  [[ -f "$profile" ]] || { printf 'check_alignment: no such profile: %s\n' "$profile" >&2; return 2; }
  [[ -f "$targets" ]] || { printf 'check_alignment: no such targets manifest: %s\n' "$targets" >&2; return 2; }
  if [[ ! -f "$live_config" ]]; then
    printf 'check_alignment: no installed configuration at %s\n' "$live_config" >&2
    printf 'check_alignment: nothing to compare -- is the bundle installed?\n' >&2
    return 2
  fi

  local repo_json live_json
  repo_json=$(load_routing_profile "$profile") || return 1
  live_json=$(load_routing_profile "$live_config") || return 1

  REPO_JSON="$repo_json" LIVE_JSON="$live_json" TARGETS="$targets" \
    BUNDLE_ROOT="$bundle_root" LIVE_SUPPORT="$live_support" \
    PROFILE_PATH="$profile" LIVE_CONFIG_PATH="$live_config" JSON_OUT="$json_out" \
    python3 <<'PY'
import datetime
import hashlib
import json
import os
import re
import sys

repo = json.loads(os.environ["REPO_JSON"])
live = json.loads(os.environ["LIVE_JSON"])
targets = json.load(open(os.environ["TARGETS"], encoding="utf-8"))
roles = list(targets["agents"])
bundle_root = os.environ["BUNDLE_ROOT"]
live_support = os.environ["LIVE_SUPPORT"]

drift = []   # routing/security relevant -- fails the check
stale = []   # prose only -- reported, does not fail

def render(value):
    return json.dumps(value, indent=2, sort_keys=True)

# --- routing-owned configuration keys -------------------------------------
# activate-profile.sh writes exactly these from the repository profile;
# everything else in the live file is user-owned and deliberately ignored.

if repo.get("model") != live.get("model"):
    drift.append({
        "kind": "config",
        "key": "model",
        "expected": repo.get("model"),
        "actual": live.get("model"),
        "detail": "top-level default model",
    })

repo_task = repo.get("permission", {}).get("task")
live_task = live.get("permission", {}).get("task")
if repo_task != live_task:
    drift.append({
        "kind": "config",
        "key": "permission.task",
        "expected": render(repo_task),
        "actual": render(live_task),
        "detail": "top-level Task permission (the Breakglass containment control)",
    })

for role in roles:
    repo_row = repo.get("agent", {}).get(role)
    live_row = live.get("agent", {}).get(role)
    if repo_row is None:
        drift.append({
            "kind": "config", "key": f"agent.{role}",
            "expected": "<declared in targets manifest>", "actual": "<missing from repository profile>",
            "detail": "targets manifest declares a role the profile does not define",
        })
        continue
    if live_row is None:
        drift.append({
            "kind": "config", "key": f"agent.{role}",
            "expected": render(repo_row), "actual": "<missing>",
            "detail": "role is absent from the installed configuration",
        })
        continue
    if repo_row != live_row:
        # Report the specific differing sub-keys, not the whole row -- a
        # whole-object dump for a one-key permission change is unreadable.
        diffs = []
        for key in sorted(set(repo_row) | set(live_row)):
            if repo_row.get(key) != live_row.get(key):
                diffs.append({
                    "subkey": key,
                    "expected": render(repo_row.get(key)),
                    "actual": render(live_row.get(key)),
                })
        drift.append({
            "kind": "config", "key": f"agent.{role}",
            "differing_subkeys": diffs,
            "detail": f"routing-owned agent row for {role}",
        })

# --- support files --------------------------------------------------------
# Agent markdown carries permissions in frontmatter (security-relevant) and
# prose in the body (informational). model-routing.md is prose throughout,
# but a stale copy actively misdescribes the routing, so it is still worth
# reporting.

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return None

def frontmatter(text):
    """Return the raw frontmatter block, or None when absent."""
    if text is None or not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[3:end].strip("\n")

def permission_block(front):
    """Extract the `permission:` mapping from frontmatter as normalized text.

    Deliberately dependency-free (no PyYAML): the block is small, strictly
    indented, and we only need a stable comparable form -- not a general
    YAML parse. Lines are stripped of trailing whitespace and compared in
    order, so an equivalent block written in a different order is reported
    as drift. For a security boundary that over-sensitivity is the safe
    direction.
    """
    if front is None:
        return None
    lines = front.split("\n")
    out = []
    capturing = False
    for line in lines:
        if re.match(r"^permission:\s*$", line):
            capturing = True
            out.append("permission:")
            continue
        if capturing:
            # A non-indented, non-empty line ends the block.
            if line.strip() and not line.startswith((" ", "\t")):
                break
            if line.strip():
                out.append(line.rstrip())
    return "\n".join(out) if out else None

def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest() if text is not None else None

# reviewer.md / expert.md: permissions are DRIFT, prose is STALE.
for name in ("reviewer", "expert"):
    repo_path = os.path.join(bundle_root, "agents", f"{name}.md")
    live_path = os.path.join(live_support, "agents", f"{name}.md")
    repo_text, live_text = read(repo_path), read(live_path)
    if repo_text is None:
        drift.append({"kind": "support", "file": f"agents/{name}.md",
                      "detail": "missing from the repository bundle", "expected": repo_path, "actual": "<missing>"})
        continue
    if live_text is None:
        drift.append({"kind": "support", "file": f"agents/{name}.md",
                      "detail": "not installed", "expected": "<present in bundle>", "actual": "<missing>"})
        continue
    repo_perm = permission_block(frontmatter(repo_text))
    live_perm = permission_block(frontmatter(live_text))
    if repo_perm != live_perm:
        drift.append({
            "kind": "support", "file": f"agents/{name}.md",
            "detail": "permission frontmatter differs -- this is a security boundary",
            "expected": repo_perm, "actual": live_perm,
        })
    elif repo_text != live_text:
        stale.append({
            "kind": "support", "file": f"agents/{name}.md",
            "detail": "permissions match; prose/description differs",
            "expected_sha256": digest(repo_text), "actual_sha256": digest(live_text),
        })

# model-routing.md: prose throughout, but a stale copy misdescribes routing.
repo_routing = read(os.path.join(bundle_root, "model-routing.md"))
live_routing = read(os.path.join(live_support, "model-routing.md"))
if repo_routing is None:
    drift.append({"kind": "support", "file": "model-routing.md",
                  "detail": "missing from the repository bundle", "expected": "<present>", "actual": "<missing>"})
elif live_routing is None:
    drift.append({"kind": "support", "file": "model-routing.md",
                  "detail": "not installed -- the routing policy the controller loads is absent",
                  "expected": "<present in bundle>", "actual": "<missing>"})
elif repo_routing != live_routing:
    stale.append({
        "kind": "support", "file": "model-routing.md",
        "detail": "installed routing policy differs from the bundle; a stale copy misdescribes the active routing",
        "expected_sha256": digest(repo_routing), "actual_sha256": digest(live_routing),
    })

# --- report ---------------------------------------------------------------

status = "DRIFT" if drift else ("STALE" if stale else "ALIGNED")
document = {
    "checked_at": datetime.datetime.now().astimezone().isoformat(),
    "status": status,
    "profile": os.environ["PROFILE_PATH"],
    "installed_configuration": os.environ["LIVE_CONFIG_PATH"],
    "routing_owned_keys": ["model", "permission.task"] + [f"agent.{r}" for r in roles],
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
    print("STALE -- support files differ in prose only (permissions match):")
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
