#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

validate_breakglass() {
  local file=$1
  python3 - "$file" <<'PY'
import json
import sys

try:
    profile = json.load(open(sys.argv[1], encoding="utf-8"))
    data = profile["breakglass"]
except (OSError, KeyError, TypeError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if profile.get("non_production") is True and
                 profile.get("normal_agent_task_permissions", {}).get("breakglass") == "deny" and
                 data.get("mode") == "primary" and
                 data.get("model") == "openai/gpt-5.6-sol" and
                 data.get("variant") == "max" and
                 data.get("human_selection_only") is True and
                 data.get("task_routable") is False else 1)
PY
}
