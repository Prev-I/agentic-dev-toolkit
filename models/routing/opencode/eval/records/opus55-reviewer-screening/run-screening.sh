#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../../../.." && pwd)
eval_root="$repo/models/routing/opencode/eval"
fixture="$eval_root/fixtures/reviewer-seeded-defects"
ledger="$root/ledger.json"
prompt="$root/reviewer-request.txt"
account=opus55_reviewer

source "$eval_root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$eval_root/scoring/fixture-defect-detectors.sh"

fixture_integrity_check "$fixture"

run_case() {
  local model_key=$1 case_id=$2 sequence=$3
  local agent config out sandbox case_dir credits
  case "$model_key" in
    opus5)
      agent=reviewer-opus5
      config="$root/config/opus5.json"
      ;;
    opus55)
      agent=reviewer-opus55
      config="$root/config/opus55.json"
      ;;
    *) return 2 ;;
  esac

  out="$root/runs/$sequence-$case_id-$model_key"
  sandbox="$out/sandbox"
  [[ ! -e "$out" ]] || { printf 'run already exists: %s\n' "$out" >&2; return 2; }
  ledger_admit "$ledger" "$account" 40 || {
    printf 'budget admission failed before %s/%s\n' "$case_id" "$model_key" >&2
    return 1
  }

  mkdir -p "$sandbox"
  cp "$fixture/clean/"*.sh "$sandbox/"
  if [[ "$case_id" != clean ]]; then
    case_dir="$fixture/cases/$case_id"
    python3 - "$case_dir/ground-truth.json" "$case_dir" "$sandbox" <<'PY'
import json
import shutil
import sys

ground_truth_path, case_dir, sandbox = sys.argv[1:]
for override in json.load(open(ground_truth_path, encoding="utf-8"))["overrides"]:
    shutil.copy(f"{case_dir}/{override}", f"{sandbox}/{override}")
PY
  fi

  set +e
  OPENCODE_CONFIG="$config" dispatch_fixture \
    --outdir "$out/dispatch" \
    --label "reviewer-$case_id-$model_key" \
    --prompt-file "$prompt" \
    --agent "$agent" \
    --workspace "$sandbox" \
    --timeout 480 \
    --attempt 1
  local status=$?
  set -e
  (( status == 0 )) || return "$status"

  if python3 - "$out/dispatch/raw.jsonl" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
raise SystemExit(0 if "Falling back to default agent" in text else 1)
PY
  then
    printf 'subagent fallback detected in %s\n' "$out" >&2
    return 1
  fi

  dispatch_extract_json "$out/dispatch" >"$out/reported.json"
  credits=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["derived_credits"])' \
    "$out/dispatch/dispatch.json")
  [[ "$credits" != None ]] || { printf 'unknown cost in %s\n' "$out" >&2; return 1; }
  ledger_append "$ledger" "$account" "reviewer-$case_id-$model_key" github-copilot "$credits"
}

run_case opus5  clean          01
run_case opus55 clean          02
run_case opus55 R-API          03
run_case opus5  R-API          04
run_case opus5  R-AUTH         05
run_case opus55 R-AUTH         06
run_case opus55 R-BOUNDARY     07
run_case opus5  R-BOUNDARY     08
run_case opus5  R-CONCURRENCY  09
run_case opus55 R-CONCURRENCY  10
run_case opus55 R-ERROR        11
run_case opus5  R-ERROR        12
