#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"
source "$root/scoring/compaction.sh"
assert_file "$root/scoring/build-control.sh"
source "$root/scoring/build-control.sh"

for fixture in build-workloads/build-restoration-gate build-workloads/build-feature build-workloads/build-bugfix build-workloads/build-refactor reviewer-seeded-defects expert-reviewer-wrong compaction-invariants; do
  assert_file "$root/fixtures/$fixture/fixture.json"
done
for fixture in build-restoration-gate build-feature build-bugfix build-refactor; do
  validate_build_fixture "$root/fixtures/build-workloads/$fixture/fixture.json"
done
assert_contains "$(<"$root/fixtures/build-workloads/build-restoration-gate/fixture.json")" '"mechanical_oracle"'
assert_contains "$(<"$root/fixtures/build-workloads/build-restoration-gate/fixture.json")" '"excluded_from_phase_3_selection"'
assert_eq practically-passable-open-remediation "$(build_control_interpretation blocked 2)"
assert_eq ambiguous-fixture-difficulty "$(build_control_interpretation blocked 1)"
assert_eq strong-fixture-finding-repair "$(build_control_interpretation blocked 0)"
assert_eq inadmissible "$(build_control_interpretation pass 3)"
if phase_evidence_admissible "$root/fixtures/build-workloads/build-feature/fixture.json" R; then
  fail "Phase-3 fixture admitted as Phase-R evidence"
fi
phase_evidence_admissible "$root/fixtures/build-workloads/build-feature/fixture.json" 3
assert_eq pass "$(reviewer_gate 5 5 0 0)"
assert_eq block "$(reviewer_gate 5 4 0 0)"
assert_eq block "$(reviewer_gate 5 5 0 1)"
assert_eq pass "$(compaction_gate 4 4)"
assert_eq block "$(compaction_gate 3 4)"
printf 'PASS: quality fixtures\n'
