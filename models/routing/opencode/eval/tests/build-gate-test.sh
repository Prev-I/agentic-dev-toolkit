#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/decision-rules/build-gate.sh"

assert_eq pass "$(build_gate 3 3)"
assert_eq classify_then_extend "$(build_gate 2 3)"
assert_eq block_fixture_control "$(build_gate 1 3)"
assert_eq pass "$(build_gate 4 5)"
assert_eq block_fixture_control "$(build_gate 3 5)"

ledger=$(mktemp)
trap 'rm -f "$ledger"' EXIT
if append_classification "$ledger" INVALID_ENVIRONMENT ""; then fail "invalid environment accepted without evidence"; fi
append_classification "$ledger" INVALID_ENVIRONMENT outage
append_classification "$ledger" VALID_CONTROLLER_FAILURE oracle_failed
assert_eq 1 "$(valid_failure_count "$ledger")"
append_classification "$ledger" FIXTURE_DEFECT broken_oracle
assert_eq restart_from_zero "$(classification_action FIXTURE_DEFECT)"
assert_eq 1 "$(valid_failure_count "$ledger")"
printf 'PASS: Build gate state machine\n'
