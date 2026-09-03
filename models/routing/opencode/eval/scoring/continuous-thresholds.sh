#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

derive_continuous_thresholds() {
  local summary=$1 output=$2 reference=$3
  [[ -n "$reference" ]] || return 1
  python3 - "$summary" "$output" "$reference" <<'PY'
import json,sys
source,output,reference=sys.argv[1:]
d=json.load(open(source,encoding="utf-8"))
if d.get("self_variance_complete") is not True or d.get("candidate_results_used") is not False: raise SystemExit(1)
def entry(metric,floor):
    measured=d.get(metric)
    if not isinstance(measured,dict) or measured.get("status") != "comparable" or not isinstance(measured.get("relative_range"),(int,float)):
        return {"metric":metric,"status":"unavailable","separation_allowed":False,"commit_reference":reference}
    relative=measured["relative_range"]
    return {"metric":metric,"status":"frozen","observed_self_variance":{"relative_range":relative},"practical_separation_threshold":max(2*relative,floor),"rule":f"max(2 * relative_range, {floor:.2f})","reasoning":"operational threshold; lower median alone is insufficient","lower_median_alone_is_sufficient":False,"commit_reference":reference}
record={"status":"frozen","candidate_results_may_define_thresholds":False,"threshold_source":"self-variance","thresholds":[entry("wall_clock_ms",0.20),entry("derived_credits",0.10)]}
with open(output,"w",encoding="utf-8") as h: json.dump(record,h,indent=2); h.write("\n")
PY
}
