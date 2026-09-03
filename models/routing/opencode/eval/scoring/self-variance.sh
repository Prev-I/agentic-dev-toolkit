#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

measure_self_variance() {
  local output=$1
  shift
  (( $# >= 3 )) || return 1
  python3 - "$output" "$@" <<'PY'
import json
import statistics
import sys

output, *paths = sys.argv[1:]
runs = [json.load(open(path, encoding="utf-8")) for path in paths]
if any(run.get("candidate_results_used") is not False for run in runs):
    raise SystemExit("candidate results are forbidden")
required = {"fixture_digest", "score", "instrumentation_schema", "credit_report"}
if any(required - run.keys() for run in runs):
    raise SystemExit("self-variance run is missing required fields")

credit_shapes = []
for run in runs:
    report = run["credit_report"]
    if not isinstance(report, dict) or "observed_cost" not in report or "tokens" not in run:
        raise SystemExit("credit_report is missing required fields")
    credit_shapes.append({key: type(value).__name__ for key, value in sorted(report.items())})

def measurement(values):
    median = statistics.median(values)
    spread = max(values) - min(values)
    return {"status": "comparable", "values": values, "minimum": min(values), "median": median, "maximum": max(values), "range": spread, "relative_range": spread / median if median else None}

valid = all(run.get("classification") == "VALID" for run in runs)
wall_clock = measurement([run["wall_clock_ms"] for run in runs]) if valid else None
credit_comparable = valid and all(
    run.get("provider") == "github-copilot"
    and run.get("pricing_regime") == "standard"
    and run["credit_report"].get("cost_unit") == "USD"
    and run["credit_report"].get("cost_source") == "copilot_provider_reported"
    and isinstance(run["credit_report"].get("derived_credits"), (int, float))
    for run in runs
)
credits = measurement([run["credit_report"]["derived_credits"] for run in runs]) if credit_comparable else {"status": "unavailable", "reason": "incompatible_or_invalid_credit_evidence"}
if credit_comparable:
    credits["cost_unit"] = "USD"
    credits["cost_source"] = "copilot_provider_reported"

record = {
    "sample_count": len(runs),
    "fixture_determinism": len({run["fixture_digest"] for run in runs}) == 1,
    "scoring_repeatability": all(run["score"] == runs[0]["score"] for run in runs),
    "instrumentation_consistency": len({run["instrumentation_schema"] for run in runs}) == 1,
    "credit_report_consistency": all(shape == credit_shapes[0] for shape in credit_shapes),
    "self_variance_complete": True,
    "candidate_results_used": any(run["candidate_results_used"] for run in runs),
    "wall_clock_ms": wall_clock,
    "derived_credits": credits,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
}

freeze_thresholds() {
  local file=$1 source=${2:-}
  [[ "$source" == self-variance && -f "$file" ]] || return 1
  python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
if data.get("self_variance_complete") is not True or data.get("candidate_results_used") is not False:
    raise SystemExit(1)
data["thresholds_frozen"] = True
data["threshold_source"] = "self-variance"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
}
