#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"
source "$root/scoring/compaction.sh"

for fixture in build-workloads/build-restoration-gate build-workloads/build-feature build-workloads/build-bugfix build-workloads/build-refactor reviewer-seeded-defects expert-reviewer-wrong compaction-invariants; do
  assert_file "$root/fixtures/$fixture/fixture.json"
done
assert_contains "$(<"$root/fixtures/build-workloads/build-restoration-gate/fixture.json")" '"mechanical_oracle"'
assert_contains "$(<"$root/fixtures/build-workloads/build-restoration-gate/fixture.json")" '"excluded_from_phase_3_selection"'
assert_eq pass "$(reviewer_gate 5 5 0 0)"
assert_eq block "$(reviewer_gate 5 4 0 0)"
assert_eq block "$(reviewer_gate 5 5 0 1)"
assert_eq pass "$(compaction_gate 4 4)"
assert_eq block "$(compaction_gate 3 4)"
printf 'PASS: quality fixtures\n'
