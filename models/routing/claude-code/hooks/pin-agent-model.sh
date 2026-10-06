#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Claude Code PreToolUse hook for the Agent tool.
#
# Routed roles take their model from their agent frontmatter. Superpowers
# passes an explicit `model` on every dispatch, and a per-call model beats
# frontmatter, so for the roles below this hook removes `model` from the call
# and resolution falls back to the frontmatter. It knows role names only, never
# models: the frontmatter stays the single routing authority.
#
# It never sets permissionDecision, so it never bypasses a permission prompt.
# It fails open: unreadable input exits 1, which Claude Code reports as a
# non-blocking error. It never exits 2, which would block every delegation.

exec python3 -c '
import json
import sys

PINNED = {"reviewer", "expert", "scout", "Explore", "planner"}

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
        or "model" not in tool_input):
    sys.exit(0)

updated = {key: value for key, value in tool_input.items() if key != "model"}
json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                  "updatedInput": updated}}, sys.stdout)
'
