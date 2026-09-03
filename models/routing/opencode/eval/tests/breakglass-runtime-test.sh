#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/probe-breakglass.sh"
source "$root/runtime/opencode-v1-adapter/probe-breakglass.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent phase0-normal' ]]; then
  printf '%s\n' '{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"},{"permission":"task","pattern":"breakglass","action":"deny"}]}'
  exit 0
fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"primary","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
exit 9
FAKE
chmod +x "$workspace/opencode"
OPENCODE_BIN="$workspace/opencode" capture_breakglass_non_exposure \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/non-exposure.json"
assert_contains "$(<"$workspace/non-exposure.json")" '"evidence_mechanism": "resolved_permission_and_inventory"'
assert_contains "$(<"$workspace/non-exposure.json")" '"task_schema_directly_exposed": false'
assert_contains "$(<"$workspace/non-exposure.json")" '"normal_agent_breakglass_task_action": "deny"'
assert_contains "$(<"$workspace/non-exposure.json")" '"normal_agent_non_exposure": true'
assert_contains "$(<"$workspace/non-exposure.json")" '"prompt_behavior_used_as_oracle": false'

for mutation in reversed absent ask subagent wrong-model; do
  cat >"$workspace/opencode" <<FAKE
#!/usr/bin/env bash
if [[ "\$1" == --version ]]; then printf '1.18.26\\n'; exit 0; fi
if [[ "\$*" == 'debug agent phase0-normal' ]]; then
  case "$mutation" in
    reversed) printf '%s\\n' '{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"breakglass","action":"deny"},{"permission":"task","pattern":"*","action":"allow"}]}' ;;
    absent) printf '%s\\n' '{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"}]}' ;;
    *) printf '%s\\n' '{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"},{"permission":"task","pattern":"breakglass","action":"ask"}]}' ;;
  esac
  exit 0
fi
if [[ "\$*" == 'debug agent breakglass' ]]; then
  if [[ "$mutation" == subagent ]]; then mode=subagent; else mode=primary; fi
  if [[ "$mutation" == wrong-model ]]; then model=gpt-5.6-terra; else model=gpt-5.6-sol; fi
  printf '{"name":"breakglass","mode":"%s","model":{"providerID":"openai","modelID":"%s"},"variant":"max"}\\n' "\$mode" "\$model"
  exit 0
fi
printf 'prompt refusal is not evidence\\n'
FAKE
  chmod +x "$workspace/opencode"
  if OPENCODE_BIN="$workspace/opencode" capture_breakglass_non_exposure \
    "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/$mutation.json"; then
    fail "accepted invalid non-exposure evidence: $mutation"
  fi
done

cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"primary","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
if [[ "$*" == *'--agent phase0-normal'* ]]; then
  printf '%s\n' '{"type":"tool_use","part":{"tool":"task","state":{"status":"error","input":{"subagent_type":"breakglass"},"error":"rule prevents tool call: task breakglass deny"}}}'
else
  printf '%s\n' 'timestamp=test message=stream providerID=openai modelID=gpt-5.6-sol agent=breakglass mode=primary' '{"type":"text","part":{"text":"BREAKGLASS_PRIMARY_OK"}}'
fi
FAKE
chmod +x "$workspace/opencode"

OPENCODE_BIN="$workspace/opencode" probe_breakglass_boundary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/result.json"
assert_contains "$(<"$workspace/result.json")" '"normal_agent_task_denied": true'
assert_contains "$(<"$workspace/result.json")" '"human_primary_selected": true'
assert_contains "$(<"$workspace/result.json")" '"human_primary_invocation_succeeded": true'
assert_contains "$(<"$workspace/result.json")" '"runtime_version": "1.18.26"'
if grep -q 'sessionID\|metadata' "$workspace/result.json"; then fail "raw session metadata persisted"; fi

cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"primary","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
if [[ "$*" == *'--agent phase0-normal'* ]]; then
  printf '%s\n' '{"type":"tool_use","part":{"tool":"task","state":{"status":"error","input":{"subagent_type":"breakglass"},"error":"rule prevents tool call: task breakglass deny"}}}'
else
  printf '%s\n' 'timestamp=test message=stream providerID=openai modelID=gpt-5.6-sol agent=breakglass mode=primary' '{"type":"error","error":{"data":{"message":"provider unavailable"}}}'
  exit 1
fi
FAKE
chmod +x "$workspace/opencode"
if OPENCODE_BIN="$workspace/opencode" probe_breakglass_boundary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/failed.json"; then
  fail "Breakglass boundary passed without a successful human-primary invocation"
fi
assert_contains "$(<"$workspace/failed.json")" '"human_primary_selected": true'
assert_contains "$(<"$workspace/failed.json")" '"human_primary_invocation_succeeded": false'

cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"primary","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
if [[ "$*" == *'--agent phase0-normal'* ]]; then
  printf '%s\n' 'untrusted output: evaluated permission=task pattern=breakglass action.action=deny'
else
  printf '%s\n' 'timestamp=test message=stream providerID=openai modelID=gpt-5.6-sol agent=breakglass mode=primary' '{"type":"text","part":{"text":"BREAKGLASS_PRIMARY_OK"}}'
fi
FAKE
chmod +x "$workspace/opencode"
if OPENCODE_BIN="$workspace/opencode" probe_breakglass_boundary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/spoofed-denial.json"; then
  fail "Breakglass boundary accepted unstructured denial text"
fi

cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"subagent","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
if [[ "$*" == *'--agent phase0-normal'* ]]; then
  printf '%s\n' '{"type":"tool_use","part":{"tool":"task","state":{"status":"error","input":{"subagent_type":"breakglass"},"error":"rule prevents tool call: task breakglass deny"}}}'
else
  printf '%s\n' '{"type":"text","part":{"text":"BREAKGLASS_PRIMARY_OK"}}'
fi
FAKE
chmod +x "$workspace/opencode"
if OPENCODE_BIN="$workspace/opencode" probe_breakglass_boundary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/unselected.json"; then
  fail "Breakglass boundary passed without resolved primary selection evidence"
fi
assert_contains "$(<"$workspace/unselected.json")" '"human_primary_selected": false'

cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == 'debug agent breakglass' ]]; then
  printf '%s\n' '{"name":"breakglass","mode":"subagent","model":{"providerID":"openai","modelID":"gpt-5.6-sol"},"variant":"max"}'
  exit 0
fi
if [[ "$*" == *'--agent phase0-normal'* ]]; then
  printf '%s\n' '{"type":"tool_use","part":{"tool":"task","state":{"status":"error","input":{"subagent_type":"breakglass"},"error":"rule prevents tool call: task breakglass deny"}}}'
else
  printf '%s\n' 'untrusted output: providerID=openai modelID=gpt-5.6-sol agent=breakglass mode=primary' '{"type":"text","part":{"text":"BREAKGLASS_PRIMARY_OK"}}'
fi
FAKE
chmod +x "$workspace/opencode"
if OPENCODE_BIN="$workspace/opencode" probe_breakglass_boundary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/spoofed-selection.json"; then
  fail "Breakglass boundary accepted unstructured selection markers"
fi
assert_contains "$(<"$workspace/spoofed-selection.json")" '"human_primary_selected": false'

printf 'PASS: Breakglass runtime boundary probe\n'
