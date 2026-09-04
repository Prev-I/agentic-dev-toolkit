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
# using the detectors in scoring/fixture-defect-detectors.sh.
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

# --- clean/ must have zero known material defects ---
assert_eq 0 "$(python3 -c 'import json; print(json.load(open("'"$fixture"'/clean/ground-truth.json"))["known_material_defects"])')"

clean_checks=(
  "pagination zero-boundary:pagination_has_zero_boundary_defect:pagination.sh"
  "pagination octal/leading-zero:pagination_has_octal_defect:pagination.sh"
  "api field renamed:api_emits_renamed_field:api.sh"
  "api JSON injection:api_has_injection_defect:api.sh"
  "storage swallows failure:storage_swallows_failure:storage.sh"
  "auth bypasses ownership:auth_bypasses_ownership:authorization.sh"
  "counter lacks locking:counter_lacks_locking:counter.sh"
)
for entry in "${clean_checks[@]}"; do
  IFS=: read -r desc fn relfile <<<"$entry"
  if "$fn" "$fixture/clean/$relfile"; then
    fail "clean/$relfile has known material defect ($desc) -- clean must have zero"
  fi
done

# --- each case directory contains ONLY its declared override(s) ---
declare -A EXPECT_DEFECT=(
  [R-API]=api_emits_renamed_field:api.sh
  [R-AUTH]=auth_bypasses_ownership:authorization.sh
  [R-BOUNDARY]=pagination_has_zero_boundary_defect:pagination.sh
  [R-CONCURRENCY]=counter_lacks_locking:counter.sh
  [R-ERROR]=storage_swallows_failure:storage.sh
)

for case_id in R-API R-AUTH R-BOUNDARY R-CONCURRENCY R-ERROR; do
  case_dir="$fixture/cases/$case_id"
  assert_file "$case_dir/ground-truth.json"
  overrides=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["overrides"]))' "$case_dir/ground-truth.json")
  present_files=$(cd "$case_dir" && find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)
  expected_files=$(printf '%s\n' $overrides | sort)
  assert_eq "$expected_files" "$present_files"

  IFS=: read -r own_fn own_relfile <<<"${EXPECT_DEFECT[$case_id]}"
  own_file="$case_dir/$own_relfile"
  assert_file "$own_file"
  if ! "$own_fn" "$own_file"; then
    fail "$case_id/$own_relfile is missing its own intended seeded defect"
  fi

  # every check applies to the override file itself; only the case's OWN
  # detector may report present -- any other detector for the SAME file
  # reporting present is an unintended, unseeded defect riding along.
  for entry in "${clean_checks[@]}"; do
    IFS=: read -r desc fn relfile <<<"$entry"
    [[ "$relfile" == "$own_relfile" ]] || continue
    [[ "$fn" == "$own_fn" ]] && continue
    if "$fn" "$own_file"; then
      fail "$case_id/$relfile carries an UNINTENDED known defect ($desc) in addition to its seeded $case_id defect"
    fi
  done
done

printf 'PASS: fixture integrity (clean zero-defect, one-defect-per-case)\n'
