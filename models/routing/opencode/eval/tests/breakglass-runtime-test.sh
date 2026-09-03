#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/probe-breakglass.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

write_fake() {
  local normal=$1 mode=$2 model=$3 primary=${4:-success}
  cat >"$workspace/opencode" <<FAKE
#!/usr/bin/env bash
if [[ "\$1" == --version ]]; then printf '1.18.26\\n'; exit 0; fi
if [[ "\$*" == 'debug agent phase0-normal' ]]; then
  printf '%s\\n' '$normal'
  exit 0
fi
if [[ "\$*" == 'debug agent breakglass' ]]; then
  printf '%s\\n' '{"name":"breakglass","mode":"$mode","model":{"providerID":"openai","modelID":"$model"},"variant":"max"}'
  exit 0
fi
if [[ "$primary" == success ]]; then
  printf '%s\\n' '{"type":"text","part":{"text":"BREAKGLASS_PRIMARY_OK"}}'
  exit 0
fi
printf '%s\\n' '{"type":"error","error":{"data":{"message":"provider unavailable"}}}'
exit 1
FAKE
  chmod +x "$workspace/opencode"
}

valid_normal='{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"},{"permission":"task","pattern":"breakglass","action":"deny"}]}'
write_fake "$valid_normal" primary gpt-5.6-sol
OPENCODE_BIN="$workspace/opencode" capture_breakglass_non_exposure \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/non-exposure.json"
assert_contains "$(<"$workspace/non-exposure.json")" '"evidence_mechanism": "resolved_permission_and_inventory"'
assert_contains "$(<"$workspace/non-exposure.json")" '"normal_agent_breakglass_task_action": "deny"'
assert_contains "$(<"$workspace/non-exposure.json")" '"normal_agent_non_exposure": true'
assert_contains "$(<"$workspace/non-exposure.json")" '"prompt_behavior_used_as_oracle": false'

reversed='{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"breakglass","action":"deny"},{"permission":"task","pattern":"*","action":"allow"}]}'
absent='{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"}]}'
ask='{"name":"phase0-normal","mode":"primary","permission":[{"permission":"task","pattern":"*","action":"allow"},{"permission":"task","pattern":"breakglass","action":"ask"}]}'
for mutation in reversed absent ask subagent all wrong-model refusal; do
  normal=$valid_normal mode=primary model=gpt-5.6-sol
  case "$mutation" in
    reversed) normal=$reversed ;;
    absent) normal=$absent ;;
    ask) normal=$ask ;;
    subagent) mode=subagent ;;
    all) mode=all ;;
    wrong-model) model=gpt-5.6-terra ;;
    refusal) normal='Breakglass is unavailable' ;;
  esac
  write_fake "$normal" "$mode" "$model"
  if OPENCODE_BIN="$workspace/opencode" capture_breakglass_non_exposure \
    "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/$mutation.json" 2>/dev/null; then
    fail "accepted invalid non-exposure evidence: $mutation"
  fi
done

write_fake "$valid_normal" primary gpt-5.6-sol success
OPENCODE_BIN="$workspace/opencode" probe_breakglass_primary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/primary.json"
assert_contains "$(<"$workspace/primary.json")" '"human_primary_selected": true'
assert_contains "$(<"$workspace/primary.json")" '"human_primary_invocation_succeeded": true'

write_fake "$valid_normal" primary gpt-5.6-sol failure
if OPENCODE_BIN="$workspace/opencode" probe_breakglass_primary \
  "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json" "$workspace/failed.json"; then
  fail "accepted failed primary execution"
fi
assert_contains "$(<"$workspace/failed.json")" '"human_primary_invocation_succeeded": false'

printf 'PASS: Breakglass runtime boundaries\n'
