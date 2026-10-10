#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Claude Code PreToolUse hook for the Agent tool.
#
# Routed roles take their model and effort from their agent frontmatter.
# Superpowers passes an explicit `model` on every dispatch, and since Claude
# Code 2.1.292 a caller can also pass `effort`; either beats the frontmatter.
# For the roles below this hook removes both from the call, so resolution falls
# back to the frontmatter. It knows role names only, never models or levels:
# the frontmatter stays the single routing authority.
#
# It never sets permissionDecision, so it never bypasses a permission prompt.
# It fails open: unreadable input exits 1, which Claude Code reports as a
# non-blocking error. It never exits 2, which would block every delegation;
# an interpreter that exits 2 itself, as on an option it does not know, is
# reported as 1.
#
# Python runs isolated (-I, -S). Hooks run in the session's current directory
# with its environment; without -I, `python3 -c` imports from that directory and
# honours PYTHONPATH, so a json.py there would run on every Agent call.
#
# The interpreter must not depend on that directory either. A version manager's
# shim reads the directory's own config, and mise honours plain `[tools]`
# versions without trust, so a repository could make every Agent call install a
# runtime or run its own binary. The hook therefore leaves the directory, asks
# mise for the interpreter as configured for $HOME, and falls back to python3 on
# PATH, resolved from $HOME as well. Automatic installs are off throughout. The
# body runs as a function in an `||` list, so no step can exit before the
# remap below.

pin() {
  local home=${HOME:-} py=
  if [[ $home == /* && -d $home ]]; then
    cd "$home" || cd /
  else
    home=
    cd /
  fi
  if [[ -n $home ]] && command -v mise >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      py=$(MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false \
        timeout -k 1 5 mise -C "$home" which python3 </dev/null 2>/dev/null) || py=
    else
      py=$(MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false \
        mise -C "$home" which python3 </dev/null 2>/dev/null) || py=
    fi
  fi
  [[ $py == /* && $py != *$'\n'* && -f $py && -x $py ]] || py=python3
  MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false "$py" -I -S -c '
import json
import sys

PINNED = {"reviewer", "expert", "scout", "Explore", "planner"}
OVERRIDES = ("model", "effort")

try:
    event = json.load(sys.stdin)
    tool_input = event["tool_input"] if isinstance(event, dict) else None
    if not isinstance(tool_input, dict):
        raise ValueError("tool_input is not an object")
except (ValueError, KeyError) as error:
    print(f"pin-agent-model: unreadable hook input ({error}); "
          "routing falls back to the policy layer", file=sys.stderr)
    sys.exit(1)

if (event.get("tool_name") != "Agent"
        or tool_input.get("subagent_type") not in PINNED
        or not any(key in tool_input for key in OVERRIDES)):
    sys.exit(0)

updated = {key: value for key, value in tool_input.items() if key not in OVERRIDES}
json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                  "updatedInput": updated}}, sys.stdout)
'
}

rc=0
pin || rc=$?
((rc != 2)) || rc=1
exit "$rc"
