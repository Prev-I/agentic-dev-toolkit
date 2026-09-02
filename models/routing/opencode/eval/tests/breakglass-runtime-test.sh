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

printf 'PASS: Breakglass runtime boundary probe\n'
