#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/self-variance.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
state="$workspace/state.json"

for run in 1 2 3; do
  cat >"$workspace/run-$run.json" <<JSON
{
  "fixture_digest": "sha256:stable",
  "score": {"passed": 4, "total": 4},
  "instrumentation_schema": "phase0-v1",
  "classification": "VALID",
  "provider": "github-copilot",
  "pricing_regime": "standard",
  "wall_clock_ms": $((900 + run * 100)),
  "tokens": {"total": $((run * 10))},
  "credit_report": {"observed_cost": $run, "cost_unit": "USD", "cost_source": "copilot_provider_reported", "derived_credits": $(python3 -c "print(0.9 + $run / 10)")}
}
JSON
done

if measure_self_variance "$state" "$workspace/run-1.json" "$workspace/run-2.json"; then
  fail "self-variance accepted fewer than three runs"
fi
measure_self_variance "$state" "$workspace/run-1.json" "$workspace/run-2.json" "$workspace/run-3.json"
assert_contains "$(<"$state")" '"sample_count": 3'
assert_contains "$(<"$state")" '"fixture_determinism": true'
assert_contains "$(<"$state")" '"scoring_repeatability": true'
assert_contains "$(<"$state")" '"instrumentation_consistency": true'
assert_contains "$(<"$state")" '"credit_report_consistency": true'
assert_contains "$(<"$state")" '"self_variance_complete": true'
assert_contains "$(<"$state")" '"median": 1100'
assert_contains "$(<"$state")" '"range": 200'
assert_contains "$(<"$state")" '"relative_range": 0.18181818181818182'
assert_contains "$(<"$state")" '"median": 1.1'

if freeze_thresholds "$workspace/missing.json" self-variance; then
  fail "thresholds froze before self-variance"
fi
if freeze_thresholds "$state" candidate-results; then
  fail "candidate results created continuous thresholds"
fi
freeze_thresholds "$state" self-variance
assert_contains "$(<"$state")" '"thresholds_frozen": true'

python3 - "$workspace/run-3.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["score"]["passed"] = 3
json.dump(data, open(path, "w", encoding="utf-8"))
PY
measure_self_variance "$workspace/variance.json" "$workspace/run-1.json" "$workspace/run-2.json" "$workspace/run-3.json"
assert_contains "$(<"$workspace/variance.json")" '"scoring_repeatability": false'

printf 'PASS: measured self-variance ordering\n'
