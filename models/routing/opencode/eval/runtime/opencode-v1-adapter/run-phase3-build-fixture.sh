#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$runner_root/dispatch-fixture.sh"

# Generalized Build Phase-3 A/B dispatch runner: same shape as
# run-build-restoration-gate.sh, parametrized over fixture id and a direct
# --model/--variant override (Phase-3 compares raw models, not the routed
# "build" agent identity). Fresh isolated workspace per arm; the fixture's
# own oracle.sh and regression.sh are the sole verdicts on the work product.

run_phase3_build_fixture() {
  local outdir="" ledger="" attempt=1 fixture_id="" model="" variant="" timeout_seconds=1800 label=""
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --attempt) attempt=$2; shift 2 ;;
      --fixture) fixture_id=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_phase3_build_fixture: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" && -n "$fixture_id" && -n "$model" && -n "$variant" ]] || return 2
  [[ -n "$label" ]] || label="$fixture_id"

  local fixture sandbox prompt oracle_status regression_status dispatch_status initially_failing regression_ok
  fixture=$(cd "$runner_root/../../fixtures/build-workloads/$fixture_id" && pwd)
  mkdir -p "$outdir"
  sandbox="$outdir/sandbox"
  rm -rf "$sandbox"
  mkdir -p "$sandbox"
  cp -R "$fixture/snapshot/." "$sandbox/"
  prompt="$outdir/prompt.txt"
  cp "$fixture/task.md" "$prompt"

  if ( cd "$sandbox" && bash tests/acceptance.sh >/dev/null 2>&1 ); then
    initially_failing=false
  else
    initially_failing=true
  fi

  local ledger_args=()
  [[ -n "$ledger" ]] && ledger_args=(--ledger "$ledger" --account phase3_build_ab)

  set +e
  dispatch_fixture --outdir "$outdir/dispatch" --label "$label" \
    --prompt-file "$prompt" --model "$model" --variant "$variant" \
    --workspace "$sandbox" --timeout "$timeout_seconds" \
    "${ledger_args[@]}" --attempt "$attempt"
  dispatch_status=$?
  set -e

  set +e
  bash "$fixture/oracle.sh" "$sandbox" >"$outdir/oracle.log" 2>&1
  oracle_status=$?
  bash "$sandbox/tests/regression.sh" >"$outdir/regression.log" 2>&1
  regression_status=$?
  set -e
  [[ "$regression_status" == 0 ]] && regression_ok=true || regression_ok=false

  ATTEMPT="$attempt" FIXTURE="$fixture_id" LABEL="$label" INITIAL="$initially_failing" \
    ORACLE="$oracle_status" REGRESSION_OK="$regression_ok" \
    DISPATCH_STATUS="$dispatch_status" DISPATCH="$outdir/dispatch/dispatch.json" \
    python3 - "$outdir/attempt.json" <<'PY'
import json
import os
import sys

dispatch = json.load(open(os.environ["DISPATCH"], encoding="utf-8"))
document = {
    "fixture": os.environ["FIXTURE"],
    "phase": "3-comparative",
    "label": os.environ["LABEL"],
    "attempt": int(os.environ["ATTEMPT"]),
    "acceptance_initially_failing": os.environ["INITIAL"] == "true",
    "dispatch": dispatch,
    "dispatch_healthy": int(os.environ["DISPATCH_STATUS"]) == 0,
    "dispatch_classification": dispatch.get("classification"),
    "oracle": f"eval/fixtures/build-workloads/{os.environ['FIXTURE']}/oracle.sh",
    "oracle_exit_status": int(os.environ["ORACLE"]),
    "oracle_passed": int(os.environ["ORACLE"]) == 0,
    "regression_passed": os.environ["REGRESSION_OK"] == "true",
    "human_or_llm_judgment_in_oracle": False,
    "runner_decides_gate_outcome": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  rm -rf "$sandbox"
}
