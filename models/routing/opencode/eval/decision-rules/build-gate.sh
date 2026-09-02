#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

build_gate() {
  local successes=$1 valid_runs=$2
  if (( valid_runs == 3 )); then
    if (( successes == 3 )); then printf 'pass\n'; elif (( successes == 2 )); then printf 'classify_then_extend\n'; else printf 'block_fixture_control\n'; fi
  elif (( valid_runs == 5 )); then
    if (( successes >= 4 )); then printf 'pass\n'; else printf 'block_fixture_control\n'; fi
  else
    printf 'invalid_state\n'
  fi
}

append_classification() {
  local ledger=$1 classification=$2 evidence=$3
  [[ "$classification" != INVALID_ENVIRONMENT || -n "$evidence" ]] || return 1
  printf '%s|%s|%s\n' "$(date --iso-8601=seconds)" "$classification" "$evidence" >>"$ledger"
}

valid_failure_count() { grep -c '|VALID_CONTROLLER_FAILURE|' "$1" || true; }

classification_action() {
  case "$1" in
    INVALID_ENVIRONMENT) printf 'exclude_and_replace\n' ;;
    VALID_CONTROLLER_FAILURE) printf 'retain_in_denominator\n' ;;
    FIXTURE_DEFECT) printf 'restart_from_zero\n' ;;
    *) printf 'reject\n' ;;
  esac
}
