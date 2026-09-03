#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/run-self-variance.sh"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cat >"$w/opencode" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == --version ]] && { printf '1.18.26\n'; exit; }
printf '%s\n' "$*" >>"${OPENCODE_CALL_LOG:?}"
printf '%s\n' '{"type":"text","part":{"text":"SELF_VARIANCE_OK"}}' '{"type":"step_finish","part":{"tokens":{"total":10},"cost":0.01}}'
FAKE
chmod +x "$w/opencode"
touch "$w/calls"
OPENCODE_BIN="$w/opencode" OPENCODE_CALL_LOG="$w/calls" run_self_variance_once "$root/fixtures/self-variance/fixture.json" "$root/manifests/phase-0-budgets.json" "$w/run.json"
for field in routing_profile_id routing_profile_commit runtime_version eval_runner_version timestamp environment provider model variant pricing_regime classification fixture_digest score instrumentation_schema credit_report tokens wall_clock_ms retry_count candidate_results_used; do assert_contains "$(<"$w/run.json")" "\"$field\""; done
assert_contains "$(<"$w/run.json")" '"cost_unit": "USD"'
assert_contains "$(<"$w/run.json")" '"cost_source": "copilot_provider_reported"'
assert_contains "$(<"$w/run.json")" '"derived_credits": 1.0'
assert_eq 1.0 "$(derive_copilot_credits github-copilot USD copilot_provider_reported 0.01)"
assert_eq null "$(derive_copilot_credits openai USD provider_reported 0.01)"
assert_contains "$(<"$w/calls")" 'run --model github-copilot/gpt-5.6-luna --variant low --format json Reply with exactly: SELF_VARIANCE_OK'
if OPENCODE_BIN="$w/opencode" OPENCODE_CALL_LOG="$w/calls" run_self_variance_once "$root/fixtures/self-variance/fixture.json" "$w/missing.json" "$w/no-budget.json"; then fail "accepted missing budget"; fi
OPENCODE_BIN="$w/opencode" OPENCODE_CALL_LOG="$w/calls" run_self_variance_set "$root/fixtures/self-variance/fixture.json" "$root/manifests/phase-0-budgets.json" "$w/set"
assert_file "$w/set/attempt-1.json"; assert_file "$w/set/attempt-2.json"; assert_file "$w/set/attempt-3.json"
if OPENCODE_BIN="$w/opencode" OPENCODE_CALL_LOG="$w/calls" run_self_variance_set "$root/fixtures/self-variance/fixture.json" "$root/manifests/phase-0-budgets.json" "$w/set"; then fail "accepted fourth valid run"; fi

cat >"$w/opencode-invalid" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == --version ]] && { printf '1.18.26\n'; exit; }
printf '%s\n' '{"type":"error","error":{"data":{"message":"provider unavailable"}}}'
exit 1
FAKE
chmod +x "$w/opencode-invalid"
if OPENCODE_BIN="$w/opencode-invalid" run_self_variance_set "$root/fixtures/self-variance/fixture.json" "$root/manifests/phase-0-budgets.json" "$w/invalid-set"; then fail "accepted invalid environment run"; fi
assert_file "$w/invalid-set/attempt-1.json"
assert_contains "$(<"$w/invalid-set/attempt-1.json")" '"classification": "INVALID_ENVIRONMENT"'
printf 'PASS: self-variance runner\n'
