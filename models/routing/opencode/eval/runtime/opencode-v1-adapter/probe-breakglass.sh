#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

capture_breakglass_non_exposure() {
  local profile=$1 output=$2 bin=${OPENCODE_BIN:-opencode}
  local config normal_raw breakglass_raw version
  config=$(python3 - "$profile" <<'PY'
import json
import sys
profile = json.load(open(sys.argv[1], encoding="utf-8"))
task = profile["normal_agent_task_permissions"]
breakglass = profile["breakglass"]
print(json.dumps({"agent": {
    "phase0-normal": {"mode": "primary", "model": "github-copilot/gpt-5.6-luna", "variant": "low", "permission": {"task": task}},
    "breakglass": {"mode": breakglass["mode"], "model": breakglass["model"], "variant": breakglass["variant"]},
}}))
PY
)
  normal_raw=$(mktemp)
  breakglass_raw=$(mktemp)
  trap 'rm -f "$normal_raw" "$breakglass_raw"' RETURN
  OPENCODE_CONFIG_CONTENT="$config" "$bin" debug agent phase0-normal >"$normal_raw"
  OPENCODE_CONFIG_CONTENT="$config" "$bin" debug agent breakglass >"$breakglass_raw"
  version=$($bin --version 2>/dev/null || printf unknown)
  VERSION="$version" NORMAL="$normal_raw" BREAKGLASS="$breakglass_raw" python3 - "$output" <<'PY'
import datetime
import fnmatch
import json
import os
import sys

normal = json.load(open(os.environ["NORMAL"], encoding="utf-8"))
breakglass = json.load(open(os.environ["BREAKGLASS"], encoding="utf-8"))
matches = [rule.get("action") for rule in normal.get("permission", [])
           if rule.get("permission") == "task"
           and fnmatch.fnmatchcase("breakglass", rule.get("pattern", ""))]
action = matches[-1] if matches else None
model = breakglass.get("model", {})
resolved_primary = (
    breakglass.get("name") == "breakglass"
    and breakglass.get("mode") == "primary"
    and model.get("providerID") == "openai"
    and model.get("modelID") == "gpt-5.6-sol"
    and breakglass.get("variant") == "max"
)
passed = action == "deny" and resolved_primary
record = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "evidence_mechanism": "resolved_permission_and_inventory",
    "task_schema_directly_exposed": False,
    "normal_agent_breakglass_task_action": action,
    "breakglass_mode": breakglass.get("mode"),
    "breakglass_model": f'{model.get("providerID")}/{model.get("modelID")}',
    "breakglass_variant": breakglass.get("variant"),
    "normal_agent_non_exposure": passed,
    "prompt_behavior_used_as_oracle": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if passed else 1)
PY
}

probe_breakglass_primary() {
  local profile=$1 output=$2 bin=${OPENCODE_BIN:-opencode}
  local workspace config primary_raw resolved_agent primary_status version
  workspace=$(mktemp -d)
  trap 'rm -rf "$workspace"' RETURN
  config="$workspace/config.json"
  primary_raw="$workspace/primary.jsonl"
  resolved_agent="$workspace/resolved-agent.json"

  python3 - "$profile" "$config" <<'PY'
import json
import sys

breakglass = json.load(open(sys.argv[1], encoding="utf-8"))["breakglass"]
config = {
    "agent": {
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
  OPENCODE_CONFIG_CONTENT="$config" "$bin" debug agent breakglass >"$resolved_agent"
  set +e
  OPENCODE_CONFIG_CONTENT="$config" "$bin" --print-logs run --agent breakglass --format json \
    'Reply with exactly: BREAKGLASS_PRIMARY_OK' >"$primary_raw" 2>&1
  primary_status=$?
  set -e
  version=$($bin --version 2>/dev/null || printf unknown)

  VERSION="$version" PRIMARY_STATUS="$primary_status" \
    PRIMARY_RAW="$primary_raw" RESOLVED_AGENT="$resolved_agent" python3 - "$output" <<'PY'
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

primary = events(os.environ["PRIMARY_RAW"])
primary_raw = open(os.environ["PRIMARY_RAW"], encoding="utf-8", errors="replace").read()
resolved = json.load(open(os.environ["RESOLVED_AGENT"], encoding="utf-8"))
model = resolved.get("model", {})
primary_selected = (
    resolved.get("name") == "breakglass"
    and resolved.get("mode") == "primary"
    and model.get("providerID") == "openai"
    and model.get("modelID") == "gpt-5.6-sol"
    and resolved.get("variant") == "max"
)
primary_ok = any(
    event.get("type") == "text"
    and event.get("part", {}).get("text", "").strip() == "BREAKGLASS_PRIMARY_OK"
    for event in primary
)
status = int(os.environ["PRIMARY_STATUS"])
raw_lower = primary_raw.lower()
external_markers = ("usage limit", "provider unavailable", "authentication", "network", "429")
if primary_selected and primary_ok and status == 0:
    classification = "PASS"
elif any(marker in raw_lower for marker in external_markers):
    classification = "BLOCKED_EXTERNAL"
else:
    classification = "FAIL"
record = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "human_primary_selected": primary_selected,
    "human_primary_invocation_succeeded": primary_ok,
    "human_primary_exit_status": status,
    "human_primary_provider_error": next((marker for marker in external_markers if marker in raw_lower), None),
    "classification": classification,
    "attempt_number": 1,
    "retry_count": 0,
    "hidden_used_as_security_control": False,
    "autonomous_escalation_present": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if classification == "PASS" else 1)
PY
}
