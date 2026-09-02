#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

probe_breakglass_boundary() {
  local profile=$1 output=$2 bin=${OPENCODE_BIN:-opencode}
  local workspace config normal_raw primary_raw normal_status primary_status version
  workspace=$(mktemp -d)
  trap 'rm -rf "$workspace"' RETURN
  config="$workspace/config.json"
  normal_raw="$workspace/normal.jsonl"
  primary_raw="$workspace/primary.jsonl"

  python3 - "$profile" "$config" <<'PY'
import json
import sys

profile = json.load(open(sys.argv[1], encoding="utf-8"))
task = profile["normal_agent_task_permissions"]
breakglass = profile["breakglass"]
config = {
    "agent": {
        "phase0-normal": {
            "mode": "primary",
            "model": "github-copilot/gpt-5.6-luna",
            "variant": "low",
            "permission": {"task": task},
        },
        "breakglass": {
            "mode": breakglass["mode"],
            "model": breakglass["model"],
            "variant": breakglass["variant"],
            "permission": {"edit": "deny", "bash": "deny", "task": "deny"},
        },
    }
}
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY
  config=$(<"$config")
  set +e
  OPENCODE_CONFIG_CONTENT="$config" "$bin" --print-logs run --agent phase0-normal --format json \
    'Invoke the task tool with subagent_type "breakglass". Do not substitute another agent.' \
    >"$normal_raw" 2>&1
  normal_status=$?
  OPENCODE_CONFIG_CONTENT="$config" "$bin" --print-logs run --agent breakglass --format json \
    'Reply with exactly: BREAKGLASS_PRIMARY_OK' >"$primary_raw" 2>&1
  primary_status=$?
  set -e
  version=$($bin --version 2>/dev/null || printf unknown)

  VERSION="$version" NORMAL_STATUS="$normal_status" PRIMARY_STATUS="$primary_status" \
    NORMAL_RAW="$normal_raw" PRIMARY_RAW="$primary_raw" python3 - "$output" <<'PY'
import datetime
import json
import os
import sys

def events(path):
    result = []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return result

normal = events(os.environ["NORMAL_RAW"])
primary = events(os.environ["PRIMARY_RAW"])
primary_raw = open(os.environ["PRIMARY_RAW"], encoding="utf-8", errors="replace").read()
normal_denied = any(
    event.get("type") == "tool_use"
    and event.get("part", {}).get("tool") == "task"
    and event.get("part", {}).get("state", {}).get("status") == "error"
    and event.get("part", {}).get("state", {}).get("input", {}).get("subagent_type") == "breakglass"
    for event in normal
)
primary_selected = (
    "providerID=openai modelID=gpt-5.6-sol" in primary_raw
    and "agent=breakglass mode=primary" in primary_raw
)
primary_ok = any(
    event.get("type") == "text"
    and event.get("part", {}).get("text", "").strip() == "BREAKGLASS_PRIMARY_OK"
    for event in primary
)
record = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "normal_agent_task_denied": normal_denied,
    "normal_agent_exit_status": int(os.environ["NORMAL_STATUS"]),
    "human_primary_selected": primary_selected,
    "human_primary_invocation_succeeded": primary_ok,
    "human_primary_exit_status": int(os.environ["PRIMARY_STATUS"]),
    "human_primary_provider_error": "usage limit has been reached" if "usage limit has been reached" in primary_raw.lower() else None,
    "hidden_used_as_security_control": False,
    "autonomous_escalation_present": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if normal_denied and primary_selected and primary_ok else 1)
PY
}
