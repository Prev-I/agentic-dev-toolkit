#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Runs every eval/tests/*-test.sh from the repository root. Makes no model
# calls and changes nothing outside temporary directories.
#
#   bash models/routing/claude-code/eval/run-tests.sh

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../.." && pwd)

(( $# == 0 )) || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'run-tests: python3 is required\n' >&2; exit 2; }

passed=0 failed=0
not_passed=()
for test_file in "$root"/tests/*-test.sh; do
  if (cd "$repo" && bash "$test_file"); then
    passed=$((passed+1))
  else
    status=$?
    failed=$((failed+1))
    not_passed+=("FAIL $(basename "$test_file") (exit $status)")
  fi
done
printf '\nSUMMARY: PASS=%s FAIL=%s\n' "$passed" "$failed"
if (( ${#not_passed[@]} )); then printf '%s\n' "${not_passed[@]}"; fi
(( failed == 0 ))
