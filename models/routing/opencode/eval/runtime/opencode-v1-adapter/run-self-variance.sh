#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
adapter_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$adapter_root/validate-budget.sh"

run_self_variance_once() {
  local fixture=$1 budget=$2 output=$3 bin=${OPENCODE_BIN:-opencode}
  trap - RETURN
  validate_phase0_budget "$budget" || return 1
  local raw start end status version commit digest result
  raw=$(mktemp); trap 'rm -f "$raw"' RETURN
  start=$(date +%s%3N)
  set +e
  "$bin" run --model github-copilot/gpt-5.6-luna --variant low --format json "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prompt"])' "$fixture")" >"$raw" 2>&1
  status=$?
  set -e
  end=$(date +%s%3N)
  version=$($bin --version 2>/dev/null || printf unknown)
  commit=$(git rev-parse HEAD)
  digest="sha256:$(sha256sum "$fixture" | cut -d' ' -f1)"
  set +e
  FIXTURE="$fixture" RAW="$raw" OUTPUT="$output" STATUS="$status" START="$start" END="$end" VERSION="$version" COMMIT="$commit" DIGEST="$digest" python3 <<'PY'
import datetime,json,os
fixture=json.load(open(os.environ["FIXTURE"],encoding="utf-8")); events=[]
for line in open(os.environ["RAW"],encoding="utf-8",errors="replace"):
 try: events.append(json.loads(line))
 except json.JSONDecodeError: pass
texts=[e.get("part",{}).get("text") for e in events if e.get("type")=="text"]
steps=[e.get("part",{}) for e in events if e.get("type")=="step_finish"]
step=steps[-1] if steps else {}; cost=step.get("cost"); tokens=step.get("tokens")
valid=int(os.environ["STATUS"])==0 and fixture["expected"] in texts
record={"routing_profile_id":"phase-0-self-variance-non-production","routing_profile_commit":os.environ["COMMIT"],"runtime_version":os.environ["VERSION"].strip(),"eval_runner_version":"phase0-self-variance-v1","timestamp":datetime.datetime.now().astimezone().isoformat(),"environment":f'{os.uname().sysname} {os.uname().release} {os.uname().machine}',"provider":"github-copilot","model":"gpt-5.6-luna","variant":"low","pricing_regime":"standard","exit_status":int(os.environ["STATUS"]),"classification":"VALID" if valid else "INVALID_ENVIRONMENT","fixture_digest":os.environ["DIGEST"],"score":{"passed":1 if valid else 0,"total":1},"instrumentation_schema":fixture["instrumentation_schema"],"credit_report":{"observed_cost":cost,"cost_unit":"USD","cost_source":"copilot_provider_reported","derived_credits":cost*100 if isinstance(cost,(int,float)) else None},"tokens":tokens,"wall_clock_ms":int(os.environ["END"])-int(os.environ["START"]),"retry_count":0,"candidate_results_used":False}
with open(os.environ["OUTPUT"],"w",encoding="utf-8") as h: json.dump(record,h,indent=2); h.write("\n")
raise SystemExit(0 if valid else 1)
PY
  result=$?
  set -e
  rm -f "$raw"
  trap - RETURN
  return "$result"
}

run_self_variance_set() {
  local fixture=$1 budget=$2 output_dir=$3
  mkdir -p "$output_dir"
  local existing
  existing=$(python3 - "$output_dir" <<'PY'
import glob,json,sys
print(sum(1 for p in glob.glob(sys.argv[1]+"/run-*.json") if json.load(open(p)).get("classification")=="VALID"))
PY
)
  (( existing < 3 )) || return 1
  local run
  for run in $(seq $((existing+1)) 3); do run_self_variance_once "$fixture" "$budget" "$output_dir/run-$run.json" || return 1; done
}
