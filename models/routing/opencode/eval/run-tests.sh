#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

strict=0
[[ ${1:-} != --strict ]] || { strict=1; shift; }
(( $# == 0 )) || { printf 'Usage: %s [--strict]\n' "$0" >&2; exit 2; }
passed=0 failed=0 skipped=0
not_passed=()
for test_file in "${EVAL_TEST_DIR:-$root/tests}"/*-test.sh; do
  log=$(mktemp)
  missing=''
  for prerequisite in python3 git patch setsid; do
    command -v "$prerequisite" >/dev/null 2>&1 || missing+=" $prerequisite"
  done
  if [[ -n "$missing" ]]; then
    printf 'SKIP: missing suite tools:%s\n' "$missing" >"$log"; status=77
  elif bash "$test_file" >"$log" 2>&1; then status=0; else status=$?; fi
  cat "$log"
  if { (( status == 77 || status == 0 )) && grep -q '^SKIP:' "$log"; }; then
    skipped=$((skipped+1)); not_passed+=("SKIP $(basename "$test_file")")
  elif (( status != 0 )); then
    failed=$((failed+1)); not_passed+=("FAIL $(basename "$test_file") (exit $status)")
  else
    passed=$((passed+1))
  fi
  rm -f "$log"
done
printf '\nSUMMARY: PASS=%s FAIL=%s SKIP=%s\n' "$passed" "$failed" "$skipped"
if (( ${#not_passed[@]} )); then printf '%s\n' "${not_passed[@]}"; fi
(( failed == 0 && (strict == 0 || skipped == 0) ))
