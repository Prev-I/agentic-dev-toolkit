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
# non-blocking error. It never exits 2, which would block every delegation.

exec python3 -c '
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
