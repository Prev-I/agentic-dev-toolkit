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
  case "$classification" in INVALID_ENVIRONMENT|VALID_CONTROLLER_FAILURE|FIXTURE_DEFECT) ;; *) return 1 ;; esac
  [[ "$classification" != INVALID_ENVIRONMENT || -n "$evidence" ]] || return 1
  local sequence previous payload digest
  sequence=$(( $(wc -l <"$ledger") + 1 ))
  previous=$(awk -F'|' 'END {print $6}' "$ledger")
  [[ -n "$previous" ]] || previous=ROOT
  payload="$sequence|$(date --iso-8601=seconds)|$classification|$evidence|$previous"
  digest=$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)
  printf '%s|%s\n' "$payload" "$digest" >>"$ledger"
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

validate_classification_ledger() {
  python3 - "$1" <<'PY'
import hashlib
import sys

raw = open(sys.argv[1], "rb").read()
if raw and not raw.endswith(b"\n"):
    raise SystemExit(1)
previous = "ROOT"
for expected, line in enumerate(raw.decode().splitlines(), 1):
    parts = line.split("|")
    if len(parts) != 6:
        raise SystemExit(1)
    sequence, timestamp, classification, evidence, recorded_previous, digest = parts
    payload = "|".join(parts[:5])
    if sequence != str(expected) or recorded_previous != previous:
        raise SystemExit(1)
    if hashlib.sha256(payload.encode()).hexdigest() != digest:
        raise SystemExit(1)
    previous = digest
PY
}

next_run_action() {
  local classification
  classification=$(awk -F'|' 'END {print $3}' "$1")
  case "$classification" in
    INVALID_ENVIRONMENT) printf 'replacement_allowed\n' ;;
    VALID_CONTROLLER_FAILURE) printf 'extension_allowed\n' ;;
    FIXTURE_DEFECT) printf 'restart_required\n' ;;
    *) printf 'classification_required\n' ;;
  esac
}
