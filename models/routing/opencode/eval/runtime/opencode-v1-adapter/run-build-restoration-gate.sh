#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
build_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$build_runner_root/dispatch-fixture.sh"

run_build_restoration_gate() {
  local outdir="" ledger="" attempt=1 model="" variant="" timeout_seconds=1800
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --attempt) attempt=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_build_restoration_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture sandbox prompt oracle_status dispatch_status initially_failing
  fixture=$(cd "$build_runner_root/../../fixtures/build-workloads/build-restoration-gate" && pwd)
  mkdir -p "$outdir"
  sandbox="$outdir/sandbox"
  rm -rf "$sandbox"
  mkdir -p "$sandbox"
  cp -R "$fixture/snapshot/." "$sandbox/"
  prompt="$outdir/prompt.txt"
  cp "$fixture/task.md" "$prompt"

  # Fixture precondition: the acceptance suite must start red.
  if ( cd "$sandbox" && bash tests/acceptance.sh >/dev/null 2>&1 ); then
    initially_failing=false
  else
    initially_failing=true
  fi

  local ledger_args=()
  [[ -n "$ledger" ]] && ledger_args=(--ledger "$ledger")

  set +e
  if [[ -n "$model" ]]; then
    dispatch_fixture --outdir "$outdir/dispatch" --label "build-restoration-gate" \
      --prompt-file "$prompt" --model "$model" --variant "$variant" \
      --workspace "$sandbox" --timeout "$timeout_seconds" \
      "${ledger_args[@]}" --attempt "$attempt"
  else
    dispatch_fixture --outdir "$outdir/dispatch" --label "build-restoration-gate" \
      --prompt-file "$prompt" --agent build \
      --workspace "$sandbox" --timeout "$timeout_seconds" \
      "${ledger_args[@]}" --attempt "$attempt"
  fi
  dispatch_status=$?
  set -e

  # The committed mechanical oracle is the sole verdict on the work product.
  set +e
  bash "$fixture/oracle.sh" "$sandbox" >"$outdir/oracle.log" 2>&1
  oracle_status=$?
  set -e

  ATTEMPT="$attempt" INITIAL="$initially_failing" ORACLE="$oracle_status" \
    DISPATCH_STATUS="$dispatch_status" DISPATCH="$outdir/dispatch/dispatch.json" \
    python3 - "$outdir/attempt.json" <<'PY'
import json
import os
import sys

dispatch = json.load(open(os.environ["DISPATCH"], encoding="utf-8"))
document = {
    "fixture": "build-restoration-gate",
    "phase": "R-operational-viability",
    "attempt": int(os.environ["ATTEMPT"]),
    "acceptance_initially_failing": os.environ["INITIAL"] == "true",
    "dispatch": dispatch,
    "dispatch_healthy": int(os.environ["DISPATCH_STATUS"]) == 0,
    "oracle": "eval/fixtures/build-workloads/build-restoration-gate/oracle.sh",
    "oracle_exit_status": int(os.environ["ORACLE"]),
    "oracle_passed": int(os.environ["ORACLE"]) == 0,
    "human_or_llm_judgment_in_oracle": False,
    "runner_decides_gate_outcome": False,
    "classification": None,
    "classification_owner": "eval/decision-rules/build-gate.sh",
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  rm -rf "$sandbox"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); raise SystemExit(0 if d["oracle_passed"] and d["dispatch_healthy"] and d["acceptance_initially_failing"] else 1)' "$outdir/attempt.json"
}
