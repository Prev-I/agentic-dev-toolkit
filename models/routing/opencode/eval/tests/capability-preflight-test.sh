#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/classify-capability-failure.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-capability-preflight.sh"
source "$root/runtime/opencode-v1-adapter/classify-capability-failure.sh"
source "$root/runtime/opencode-v1-adapter/run-capability-preflight.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
emit() { printf '%s\n' "$2" >"$workspace/$1"; }

emit unresolvable.json '{"error_text":"ProviderModelNotFoundError: model github-copilot/claude-opus-4.6 not found"}'
assert_eq 'MODEL_UNRESOLVABLE' "$(classify_capability_failure "$workspace/unresolvable.json")"

emit unavailable.json '{"error_text":"model is not available for this account"}'
assert_eq 'MODEL_UNAVAILABLE' "$(classify_capability_failure "$workspace/unavailable.json")"

emit policy.json '{"error_text":"blocked by organization policy"}'
assert_eq 'POLICY_DENIED' "$(classify_capability_failure "$workspace/policy.json")"

emit quota.json '{"error_text":"usage limit has been reached","status_code":429}'
assert_eq 'QUOTA_FAILURE' "$(classify_capability_failure "$workspace/quota.json")"

emit auth.json '{"error_text":"unauthorized: invalid_api_key"}'
assert_eq 'AUTH_FAILURE' "$(classify_capability_failure "$workspace/auth.json")"

emit network.json '{"error_text":"connection timeout"}'
assert_eq 'NETWORK_FAILURE' "$(classify_capability_failure "$workspace/network.json")"

emit provider.json '{"error_text":"service unavailable","status_code":503}'
assert_eq 'PROVIDER_FAILURE' "$(classify_capability_failure "$workspace/provider.json")"

emit odd.json '{"error_text":"something else entirely"}'
assert_eq 'UNCLASSIFIED' "$(classify_capability_failure "$workspace/odd.json")"

assert_eq 'CAPABILITY_REGRESSION' "$(capability_stop_class MODEL_UNRESOLVABLE)"
assert_eq 'CAPABILITY_REGRESSION' "$(capability_stop_class MODEL_UNAVAILABLE)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class QUOTA_FAILURE)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class POLICY_DENIED)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class UNCLASSIFIED)"

targets=$(preflight_targets "$root/manifests/phase-r-routing-targets.json")
assert_eq '11' "$(printf '%s\n' "$targets" | grep -c .)"
assert_eq 'plan github-copilot/claude-opus-5 max' "$(printf '%s\n' "$targets" | head -1)"
assert_contains "$targets" 'breakglass openai/gpt-5.6-sol max'
assert_contains "$targets" 'scout github-copilot/gpt-5.6-luna low'
assert_contains "$targets" 'compaction github-copilot/gpt-5.6-terra medium'
assert_contains "$targets" 'expert openai/gpt-5.6-sol xhigh'
assert_contains "$targets" 'reviewer github-copilot/gpt-5.6-sol high'

printf 'PASS: Phase R capability preflight\n'
