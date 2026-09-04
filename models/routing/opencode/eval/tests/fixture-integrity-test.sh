#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/fixture-defect-detectors.sh"

# Mechanical fixture-integrity gate for reviewer-seeded-defects, independent
# of any live model dispatch. Proves the fixture's own committed invariants
# (clean/ground-truth.json: known_material_defects=0; each case's
# ground-truth.json: exactly one expected_material_defect) mechanically,
# using fixture_integrity_check (scoring/fixture-defect-detectors.sh) -- the
# same function run-reviewer-gate.sh calls as a hard admission gate before
# any live dispatch.
#
# Motivation (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md):
# a real defect in clean/pagination.sh (bash reinterpreting leading-zero
# input as octal) went undetected by every prior review pass and was only
# found by a live Reviewer dispatch -- an expensive, non-deterministic way
# to learn that a fixture violates its own contract. This suite exists so
# that class of drift fails BEFORE any live dispatch is spent on it.
#
# Architecture note: each case directory under fixtures/reviewer-seeded-defects/
# cases/<ID>/ contains ONLY its declared override file(s) (per its own
# ground-truth.json's "overrides" list) plus ground-truth.json -- verified
# below. Every non-override file is supplied fresh from clean/ at sandbox
# construction time by run-reviewer-gate.sh, so a case can only carry an
# "unintended" defect through the override file itself; it cannot silently
# drift via a stale hand-copied non-override file (there isn't one).

fixture="$root/fixtures/reviewer-seeded-defects"

assert_eq 0 "$(python3 -c 'import json; print(json.load(open("'"$fixture"'/clean/ground-truth.json"))["known_material_defects"])')"

if ! violations=$(fixture_integrity_check "$fixture" 2>&1); then
  fail "$violations"
fi

printf 'PASS: fixture integrity (clean zero-defect, one-defect-per-case)\n'
