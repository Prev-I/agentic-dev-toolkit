#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# R-API observability fix (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
# section "Reviewer Root-Cause & Fixture Integrity Remediation, part 2").
#
# Root cause of the original R-API zero-signal result: the seeded ground
# truth ("documented public displayName field renamed without compatibility
# handling") required the Reviewer to know api.sh's response field used to
# be called "displayName" -- but "displayName" was never observable
# anywhere the Reviewer's sandbox could see. It existed only in
# cases/R-API/ground-truth.json, the hidden answer key, never copied into
# any sandbox. FIXTURE_DEFECT: the Reviewer cannot be expected to infer
# hidden ground truth.
#
# The fix adds a Reviewer-VISIBLE public-contract witness to clean/ (so it
# survives, unmodified, into every sandbox including R-API's, since R-API
# only overrides api.sh) -- NOT prose asserting "this is a bug", and NOT the
# seed ID -- a downstream consumer's contract expectation, the kind of
# artifact a real API fixture would actually carry. The Reviewer must still
# read api.sh, read the contract, and reason about the mismatch itself.

fixture="$root/fixtures/reviewer-seeded-defects"
clean_dir="$fixture/clean"
r_api_dir="$fixture/cases/R-API"

# --- RED: before the fix, prove no such witness exists ---
# Every *.sh file that clean/ carries (and that therefore survives
# unmodified into R-API's sandbox, since only api.sh is overridden there)
# must be checked: none of them, other than api.sh itself, may reference
# "displayName" -- if none do, the Reviewer has no way to learn the field's
# expected name once api.sh is overridden.
witness_found=0
for f in "$clean_dir"/*.sh; do
  [[ "$(basename "$f")" == "api.sh" ]] && continue
  if grep -q displayName "$f"; then
    witness_found=1
  fi
done
assert_eq 1 "$witness_found"

# --- the witness file must not itself be an R-API override ---
# (it must come from clean/ unmodified, per the fixture's own base+overrides
# architecture, or it would never reach the R-API sandbox at all)
r_api_overrides=$(python3 -c 'import json; print(" ".join(json.load(open("'"$r_api_dir"'/ground-truth.json"))["overrides"]))')
assert_eq api.sh "$r_api_overrides"

# --- the witness must state the CONTRACT, not the verdict ---
# it must not name the seed ID or literally assert that a rename is a bug --
# it documents what the contract IS, leaving the comparison to the Reviewer.
for f in "$clean_dir"/*.sh; do
  [[ "$(basename "$f")" == "api.sh" ]] && continue
  if grep -qi 'R-API\|seeded\|ground.truth\|ground_truth' "$f"; then
    fail "$f leaks the seed ID or references the harness's ground truth -- must not happen"
  fi
done

# --- mechanical proof: clean satisfies its own contract, R-API's override does not ---
source "$root/scoring/fixture-defect-detectors.sh"
if api_violates_public_contract "$clean_dir" "$clean_dir/api.sh"; then
  fail "clean/api.sh violates its own public contract -- clean must satisfy it"
fi
if ! api_violates_public_contract "$clean_dir" "$r_api_dir/api.sh"; then
  fail "cases/R-API/api.sh does not violate the public contract -- R-API is missing its observable seeded defect"
fi

# --- regression: the contract check must not rely on Python's `assert`,
# which PYTHONOPTIMIZE/-O silently strips, defeating the check without any
# error. Independent review caught this: with PYTHONOPTIMIZE=1 set, the
# R-API violation was silently reported as satisfied (rc 0). ---
if ! PYTHONOPTIMIZE=1 api_violates_public_contract "$clean_dir" "$r_api_dir/api.sh"; then
  fail "api_violates_public_contract relies on Python assert, which PYTHONOPTIMIZE strips -- R-API's real violation went undetected under PYTHONOPTIMIZE=1"
fi

printf 'PASS: R-API public-contract observability\n'
