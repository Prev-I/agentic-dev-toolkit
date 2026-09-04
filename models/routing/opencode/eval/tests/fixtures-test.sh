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

# R-ERROR fixture repair (R_ERROR_FIXTURE_AMBIGUITY): load_items was renamed to
# load_items_or_fail in both clean/storage.sh and cases/R-ERROR/storage.sh so the
# function's own name signals the caller-visible failure/empty distinction, matching
# every other seeded case's pattern of self-evident materiality from name/signature
# alone. This must not silently regress back to the old name, and the two files must
# differ by nothing except the seeded swallowed-failure defect.
clean_storage="$root/fixtures/reviewer-seeded-defects/clean/storage.sh"
error_storage="$root/fixtures/reviewer-seeded-defects/cases/R-ERROR/storage.sh"
assert_file "$clean_storage"
assert_file "$error_storage"
bash -n "$clean_storage"
bash -n "$error_storage"
assert_contains "$(<"$clean_storage")" 'load_items_or_fail'
assert_contains "$(<"$error_storage")" 'load_items_or_fail'
if grep -qE '(^|[^_])load_items\(\)' "$clean_storage" "$error_storage"; then
  fail "storage.sh still defines the old load_items name instead of load_items_or_fail"
fi
storage_diff=$(diff "$clean_storage" "$error_storage" || true)
assert_contains "$storage_diff" '2>/dev/null || printf'
error_without_defect=$(python3 -c '
import sys
text = open(sys.argv[1], encoding="utf-8").read()
print(text.replace(" 2>/dev/null || printf \x27[]\\n\x27;", ";"), end="")
' "$error_storage")
assert_eq "$(<"$clean_storage")" "$error_without_defect"

# I2 fixture repair: cases/R-API/api.sh and cases/R-BOUNDARY/pagination.sh were
# found still carrying the OLD pre-repair vulnerable patterns that
# clean/{api.sh,pagination.sh} had already been fixed away from (commit
# a96c0ce fixed clean/ only; the case override files, being self-contained,
# were never repaired). Each override must differ from its repaired clean/
# counterpart by nothing except its own seeded defect (field rename for
# R-API, zero-boundary for R-BOUNDARY) — otherwise the case is testing a
# reintroduced generic vulnerability instead of the seeded ground truth.
clean_api="$root/fixtures/reviewer-seeded-defects/clean/api.sh"
case_api="$root/fixtures/reviewer-seeded-defects/cases/R-API/api.sh"
assert_file "$clean_api"
assert_file "$case_api"
bash -n "$clean_api"
bash -n "$case_api"
assert_contains "$(<"$clean_api")" 'json.dumps'
assert_contains "$(<"$case_api")" 'json.dumps'
api_diff=$(diff "$clean_api" "$case_api" || true)
assert_contains "$api_diff" '"name"'
api_without_defect=$(python3 -c '
import sys
text = open(sys.argv[1], encoding="utf-8").read()
print(text.replace("\"name\"", "\"displayName\""), end="")
' "$case_api")
assert_eq "$(<"$clean_api")" "$api_without_defect"

clean_pagination="$root/fixtures/reviewer-seeded-defects/clean/pagination.sh"
case_pagination="$root/fixtures/reviewer-seeded-defects/cases/R-BOUNDARY/pagination.sh"
assert_file "$clean_pagination"
assert_file "$case_pagination"
bash -n "$clean_pagination"
bash -n "$case_pagination"
assert_contains "$(<"$clean_pagination")" '=~ ^[0-9]+$'
assert_contains "$(<"$case_pagination")" '=~ ^[0-9]+$'
pagination_diff=$(diff "$clean_pagination" "$case_pagination" || true)
assert_contains "$pagination_diff" '>= 0'
pagination_without_defect=$(python3 -c '
import sys
text = open(sys.argv[1], encoding="utf-8").read()
print(text.replace(">= 0 &&", ">= 1 &&"), end="")
' "$case_pagination")
assert_eq "$(<"$clean_pagination")" "$pagination_without_defect"

printf 'PASS: quality fixtures\n'
