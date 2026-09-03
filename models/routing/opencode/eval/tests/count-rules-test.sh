#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/decision-rules/count-rules.sh"

assert_eq separates "$(count_decision 3 3 0)"
assert_eq extend_n5 "$(count_decision 3 3 1)"
assert_eq no_separation "$(count_decision 3 3 2)"
assert_eq fixture_finding "$(count_decision 3 1 0)"
assert_eq separates "$(count_decision 5 5 2)"
assert_eq inconclusive "$(count_decision 5 4 2)"
assert_eq no_separation "$(count_decision 5 4 3)"
assert_eq fixture_finding "$(count_decision 5 2 1)"
assert_eq inconclusive "$(count_decision 5 3 0)"
assert_eq inconclusive "$(count_decision 7 7 0)"
assert_eq separates "$(count_decision 3 3 0)"
assert_eq extend_n5 "$(count_decision 3 2 0)"
assert_eq no_separation "$(count_decision 3 2 1)"
assert_eq fixture_finding "$(count_decision 3 1 1)"
assert_eq inconclusive "$(count_decision 5 3 1)"
printf 'PASS: count rules\n'
