#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

capture_agent_permissions() {
  local role=$1 output=$2 bin=${OPENCODE_BIN:-opencode}
  local raw
  raw=$(mktemp)
  trap 'rm -f "$raw"' RETURN
  "$bin" debug agent "$role" >"$raw"
  python3 - "$raw" "$output" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
permissions = data.get("permission", [])

def action(name, pattern="*"):
    matches = [item["action"] for item in permissions
               if item.get("permission") == name and item.get("pattern") == pattern]
    return matches[-1] if matches else None

bash_allowed = [item["pattern"] for item in permissions
                if item.get("permission") == "bash" and item.get("action") == "allow"]
model = data.get("model", {})
record = {
    "name": data.get("name"),
    "mode": data.get("mode"),
    "model": f'{model.get("providerID")}/{model.get("modelID")}',
    "variant": data.get("variant"),
    "tools": {key: data.get("tools", {}).get(key) for key in
              ("apply_patch", "bash", "task", "webfetch", "websearch")},
    "permissions": {
        "edit": action("edit"),
        "task": action("task"),
        "bash": {"wildcard": action("bash"), "allowed": bash_allowed},
        "webfetch": action("webfetch"),
        "websearch": action("websearch"),
    },
}
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
}

validate_agent_permissions() {
  local role=$1 record=$2
  python3 - "$role" "$record" <<'PY'
import json
import sys

role, path = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
tools = data.get("tools", {})
permissions = data.get("permissions", {})
common = (
    data.get("name") == role
    and data.get("mode") == "subagent"
    and tools.get("apply_patch") is False
    and tools.get("task") is False
    and permissions.get("edit") == "deny"
    and permissions.get("task") == "deny"
)
if role == "reviewer":
    bash = permissions.get("bash", {})
    valid = common and tools.get("bash") is True and bash.get("wildcard") == "deny"
    valid = valid and set(bash.get("allowed", [])) == {
        "git status*", "git diff*", "git log*", "git show*"
    }
elif role == "expert":
    valid = common and all(tools.get(name) is False for name in
                           ("bash", "webfetch", "websearch"))
    valid = valid and permissions.get("bash", {}).get("wildcard") == "deny"
    valid = valid and permissions.get("webfetch") == "deny"
    valid = valid and permissions.get("websearch") == "deny"
else:
    valid = False
raise SystemExit(0 if valid else 1)
PY
}
