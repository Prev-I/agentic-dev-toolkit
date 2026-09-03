#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/continuous-thresholds.sh"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cat >"$w/summary.json" <<'JSON'
{"self_variance_complete":true,"candidate_results_used":false,"wall_clock_ms":{"status":"comparable","relative_range":0.05},"derived_credits":{"status":"comparable","cost_unit":"USD","cost_source":"copilot_provider_reported","relative_range":0.2}}
JSON
derive_continuous_thresholds "$w/summary.json" "$w/out.json" abc123
assert_contains "$(<"$w/out.json")" '"practical_separation_threshold": 0.2'
assert_contains "$(<"$w/out.json")" '"practical_separation_threshold": 0.4'
assert_contains "$(<"$w/out.json")" '"lower_median_alone_is_sufficient": false'
for mutation in incomplete candidate emptyref; do
  cp "$w/summary.json" "$w/$mutation.json"
  [[ "$mutation" == incomplete ]] && python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["self_variance_complete"]=False; json.dump(d,open(p,"w"))' "$w/$mutation.json"
  [[ "$mutation" == candidate ]] && python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["candidate_results_used"]=True; json.dump(d,open(p,"w"))' "$w/$mutation.json"
  ref=abc123; [[ "$mutation" == emptyref ]] && ref=''
  if derive_continuous_thresholds "$w/$mutation.json" "$w/$mutation-out.json" "$ref"; then fail "accepted $mutation threshold input"; fi
done
cat >"$w/incompatible.json" <<'JSON'
{"self_variance_complete":true,"candidate_results_used":false,"wall_clock_ms":{"status":"comparable","relative_range":0.05},"derived_credits":{"status":"unavailable","reason":"incompatible_units"}}
JSON
derive_continuous_thresholds "$w/incompatible.json" "$w/incompatible-out.json" abc123
python3 - "$w/incompatible-out.json" <<'PY'
import json,sys
rows={row["metric"]:row for row in json.load(open(sys.argv[1]))["thresholds"]}
assert rows["derived_credits"]["status"] == "unavailable"
assert rows["derived_credits"]["separation_allowed"] is False
assert rows["wall_clock_ms"]["status"] == "frozen"
assert rows["wall_clock_ms"]["practical_separation_threshold"] == 0.20
PY
printf 'PASS: continuous thresholds\n'
