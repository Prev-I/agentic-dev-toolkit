#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

measure_self_variance() {
  local output=$1
  shift
  (( $# >= 3 )) || return 1
  python3 - "$output" "$@" <<'PY'
import json
import sys

output, *paths = sys.argv[1:]
runs = [json.load(open(path, encoding="utf-8")) for path in paths]
required = {"fixture_digest", "score", "instrumentation_schema", "credit_report"}
if any(required - run.keys() for run in runs):
    raise SystemExit("self-variance run is missing required fields")

credit_shapes = []
for run in runs:
    report = run["credit_report"]
    if not isinstance(report, dict) or not {"observed_cost", "tokens"} <= report.keys():
        raise SystemExit("credit_report is missing required fields")
    credit_shapes.append({key: type(value).__name__ for key, value in sorted(report.items())})

record = {
    "sample_count": len(runs),
    "fixture_determinism": len({run["fixture_digest"] for run in runs}) == 1,
    "scoring_repeatability": all(run["score"] == runs[0]["score"] for run in runs),
    "instrumentation_consistency": len({run["instrumentation_schema"] for run in runs}) == 1,
    "credit_report_consistency": all(shape == credit_shapes[0] for shape in credit_shapes),
    "self_variance_complete": True,
    "candidate_results_used": False,
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
