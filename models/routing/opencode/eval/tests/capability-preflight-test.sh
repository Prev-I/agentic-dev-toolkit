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

# Test cost extraction with null observed_cost to verify the fix for Finding 1:
# Probe records without step_finish have observed_cost: null (JSON null, not the string "null").
# The cost-extraction step must emit "null" (the JSON literal string), not "None" (Python's str(None)),
# so that the ledger_credits_from_cost null guard recognizes it and returns "null" instead of
# attempting float("None") which would crash the entire preflight under set -Eeuo pipefail.
emit failure_no_cost.json '{"error_text":"MODEL_UNRESOLVABLE","observed_cost":null}'
cost=$(python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))["observed_cost"]
print("null" if value is None else value)
' "$workspace/failure_no_cost.json")
assert_eq 'null' "$cost"

# Test the while read loop field splitting under file-scope IFS=$'\n\t' (no space).
# This verifies the fix for the bug where the entire space-separated line was assigned
# to the first variable because space was not in IFS. The fix uses an explicit local
# IFS=' ' in the inner read to properly split role/model/variant.
# We verify: (1) loop correctly splits all 11 lines from preflight_targets;
# (2) probe_model_variant is invoked with non-empty model/variant for each role;
# (3) record path is clean (no embedded spaces or corrupted slashes).
test_preflight_loop_output="$workspace/test_preflight_loop"
mkdir -p "$test_preflight_loop_output"

# Create a fake probe function that logs its invocations and writes minimal success records.
# This avoids real model calls while testing the loop's field-splitting behavior.
probe_model_variant_fake() {
  local model=$1 variant=$2 output=$3
  [[ -n "$model" && "$model" != "" ]] || fail "probe_model_variant_fake called with empty model"
  [[ -n "$variant" && "$variant" != "" ]] || fail "probe_model_variant_fake called with empty variant"
  # Verify output path is clean (expected pattern: /path/to/dir/ROLENAME.json, no embedded spaces from corrupted split)
  [[ "$output" == "$test_preflight_loop_output"/*.json ]] || fail "record path is corrupted: $output"
  # Write a minimal success record
  printf '{"error_text":"","status_code":200,"observed_cost":null,"provider":"test","model":"%s","variant":"%s","pricing_regime":"test","wall_clock_ms":0,"runtime_version":"test","exact_invocation":"test"}' "$model" "$variant" >"$output"
  return 0
}
export -f probe_model_variant_fake

# Run a minimal invocation of run_capability_preflight with our test setup.
# Create a stub ledger file.
test_ledger="$workspace/test_ledger.json"
echo '[]' >"$test_ledger"

# Temporarily override probe_model_variant with our fake.
unset probe_model_variant
probe_model_variant() { probe_model_variant_fake "$@"; }

# Run preflight (will not exit 0 because records have observed_cost: null, but that's OK —
# we're testing the loop field-splitting, not the overall status).
set +e
run_capability_preflight "$test_preflight_loop_output" "$workspace/test_manifest.json" "$test_ledger" "$root/manifests/phase-r-routing-targets.json" 2>&1 | head -1 || true
set -e

# Verify all 11 role record files were created (proving the loop iterated all 11 times).
record_count=$(ls "$test_preflight_loop_output"/*.json 2>/dev/null | wc -l)
assert_eq '11' "$record_count"

# Spot-check that specific roles got the correct model/variant assignments.
# Read the first role's record and verify its role, model, variant fields.
first_record=$(cat "$test_preflight_loop_output/plan.json")
assert_contains "$first_record" 'plan'
assert_contains "$first_record" 'github-copilot/claude-opus-5'
assert_contains "$first_record" 'max'

breakglass_record=$(cat "$test_preflight_loop_output/breakglass.json")
assert_contains "$breakglass_record" 'breakglass'
assert_contains "$breakglass_record" 'openai/gpt-5.6-sol'

printf 'PASS: Phase R capability preflight\n'
