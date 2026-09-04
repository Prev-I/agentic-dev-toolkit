#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Mechanical, LLM-free detectors for the reviewer-seeded-defects fixture's
# known defect classes. Each function sources the given file in a subshell
# (so its function definitions never leak into the caller) and exercises it
# directly. Returns 0 (shell "true") if the defect IS present, 1 if absent.
#
# These exist to mechanically prove the fixture's own invariants -- clean/
# has zero known material defects, and each seeded case's override carries
# exactly its own intended defect -- without depending on a live model
# dispatch to notice drift. See docs/evidence/
# 2026-09-04-reviewer-fixture-integrity-remediation.md for the incident that
# motivated this (a real bash octal-reinterpretation defect in
# clean/pagination.sh went unnoticed until a live Reviewer dispatch found it).

# R-BOUNDARY seed: pageSize 0 wrongly accepted (documented range is 1..100).
pagination_has_zero_boundary_defect() {
  local file=$1
  ( source "$file"; validate_page_size 0 >/dev/null 2>&1 )
}

# Root-cause defect (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md):
# a `[[ "$1" =~ ^[0-9]+$ ]]` guard only proves "all decimal digit characters";
# bash's `(( ))` then reparses any leading-zero string as octal (`man bash`,
# ARITHMETIC EVALUATION: "Constants with a leading 0 are interpreted as octal
# numbers"). Present if "0144" (octal 144 = decimal 100) is wrongly accepted,
# or if "08"/"09" crash the arithmetic evaluator instead of being cleanly
# accepted as decimal 8/9.
pagination_has_octal_defect() {
  local file=$1
  local accepts_0144 accepts_08_cleanly
  if ( source "$file"; validate_page_size 0144 >/dev/null 2>&1 ); then
    accepts_0144=1
  else
    accepts_0144=0
  fi
  if ( source "$file"; set +e; validate_page_size 08 >/dev/null 2>&1 ); then
    accepts_08_cleanly=1
  else
    accepts_08_cleanly=0
  fi
  (( accepts_0144 == 1 || accepts_08_cleanly == 0 ))
}

# Second, independent mechanism named in the same live finding that
# motivated pagination_has_octal_defect (both are in
# eval/records/phase-r/reviewer/R-BOUNDARY/dispatch/response.txt; only the
# octal half was originally addressed, per independent review of the first
# fix): bash's `(( ))` is signed 64-bit and silently WRAPS on overflow
# rather than erroring. Present if "2^64 + 1" (a value that unambiguously
# exceeds the documented 1..100 range) is wrongly accepted because it
# wrapped into range.
pagination_has_overflow_defect() {
  local file=$1
  ( source "$file"; validate_page_size 18446744073709551617 >/dev/null 2>&1 )
}

# R-API seed: the documented public field was silently renamed from
# displayName to name. Present if the emitted JSON uses "name" instead of
# "displayName".
api_emits_renamed_field() {
  local file=$1
  local output
  output=$(source "$file"; public_response probe)
  [[ "$output" == *'"name"'* && "$output" != *'"displayName"'* ]]
}

# R-API observability witness (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
# part 2, "Close R-API observability"): unlike the detector above, this
# checks the SAME thing a Reviewer looking at the sandbox could observe --
# clean/api_contract.sh (a downstream consumer's contract expectation,
# present in every sandbox including R-API's, since it is never overridden)
# combined with the api.sh actually present. Present (violation) if the
# combination fails the consumer's own assertion.
api_violates_public_contract() {
  local clean_dir=$1 api_file=$2
  ! ( source "$clean_dir/api_contract.sh"; source "$api_file"; assert_public_response_contract probe >/dev/null 2>&1 )
}

# Pre-existing clean-control defect (fixed by commit a96c0ce in clean/, but
# re-verify mechanically rather than assuming): unescaped JSON interpolation
# lets a value containing a double quote inject arbitrary JSON structure.
api_has_injection_defect() {
  local file=$1
  local output
  output=$(source "$file"; public_response '","admin":true')
  # A safe implementation round-trips the hostile value as an inert string
  # under whichever key it uses; python3 -c is used only to PARSE, not to
  # dispatch a model -- purely local JSON validation.
  ! python3 -c '
import json, sys
try:
    doc = json.loads(sys.argv[1])
except json.JSONDecodeError:
    raise SystemExit(1)
raise SystemExit(0 if doc.get("admin") is not True else 1)
' "$output" >/dev/null 2>&1
}

# R-ERROR seed: a storage backend failure is silently converted into a
# false-successful empty result instead of propagating.
storage_swallows_failure() {
  local file=$1
  local rc
  ( source "$file"; set +e; load_items_or_fail /nonexistent/definitely-missing-storage >/dev/null 2>&1 )
  rc=$?
  (( rc == 0 ))
}

# R-AUTH seed: read_resource never actually compares caller/owner, so any
# caller can read any owner's resource.
auth_bypasses_ownership() {
  local file=$1
  local rc
  ( source "$file"; set +e; read_resource alice bob SECRET >/dev/null 2>&1 )
  rc=$?
  (( rc == 0 ))
}

# R-CONCURRENCY seed: increment_counter performs an unsynchronized
# read-modify-write. A live 50-parallel-process race is slow and can be
# flaky under load; as a fast, deterministic, purely static proxy, a
# lock-free implementation cannot contain a locking primitive at all --
# absence of any lock/flock usage is a necessary (if not sufficient)
# condition for the race, and is what the seeded case actually removes.
counter_lacks_locking() {
  local file=$1
  ! grep -qE 'flock|mkdir[^|]*\.lock|noclobber' "$file"
}

# Admission gate: mechanically proves clean/ has zero known material
# defects and each seeded case's override carries exactly its own intended
# defect and no other known one, WITHOUT any live model dispatch. Prints
# every violation found (does not stop at the first) and returns nonzero if
# any exist. See tests/fixture-integrity-test.sh for the test-harness
# wrapper and docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md
# for why this exists: a real defect in clean/pagination.sh went undetected
# by every prior review pass and was only found by a live, paid dispatch.
FIXTURE_KNOWN_CHECKS=(
  "pagination zero-boundary:pagination_has_zero_boundary_defect:pagination.sh"
  "pagination octal/leading-zero:pagination_has_octal_defect:pagination.sh"
  "pagination overflow/wraparound:pagination_has_overflow_defect:pagination.sh"
  "api field renamed:api_emits_renamed_field:api.sh"
  "api JSON injection:api_has_injection_defect:api.sh"
  "storage swallows failure:storage_swallows_failure:storage.sh"
  "auth bypasses ownership:auth_bypasses_ownership:authorization.sh"
  "counter lacks locking:counter_lacks_locking:counter.sh"
)

declare -gA FIXTURE_EXPECTED_DEFECT=(
  [R-API]=api_emits_renamed_field:api.sh
  [R-AUTH]=auth_bypasses_ownership:authorization.sh
  [R-BOUNDARY]=pagination_has_zero_boundary_defect:pagination.sh
  [R-CONCURRENCY]=counter_lacks_locking:counter.sh
  [R-ERROR]=storage_swallows_failure:storage.sh
)

fixture_integrity_check() {
  local fixture=$1
  local ok=0

  local entry desc fn relfile
  for entry in "${FIXTURE_KNOWN_CHECKS[@]}"; do
    IFS=: read -r desc fn relfile <<<"$entry"
    if [[ ! -f "$fixture/clean/$relfile" ]]; then
      printf 'FIXTURE INTEGRITY: clean/%s missing\n' "$relfile" >&2
      ok=1
      continue
    fi
    if "$fn" "$fixture/clean/$relfile"; then
      printf 'FIXTURE INTEGRITY: clean/%s has known material defect (%s) -- clean must have zero\n' "$relfile" "$desc" >&2
      ok=1
    fi
  done

  local case_id case_dir overrides present_files expected_files own_fn own_relfile own_file
  for case_id in "${!FIXTURE_EXPECTED_DEFECT[@]}"; do
    case_dir="$fixture/cases/$case_id"
    if [[ ! -f "$case_dir/ground-truth.json" ]]; then
      printf 'FIXTURE INTEGRITY: %s/ground-truth.json missing\n' "$case_id" >&2
      ok=1
      continue
    fi
    # newline-joined (not space-joined): this file's IFS=$'\n\t' does not
    # split on space, so a space-joined multi-override string previously
    # collapsed into one malformed word here (see docs/evidence/
    # 2026-09-04-reviewer-fixture-integrity-remediation.md, F3).
    overrides=$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["overrides"]))' "$case_dir/ground-truth.json")
    present_files=$(cd "$case_dir" && find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort)
    expected_files=$(printf '%s\n' "$overrides" | sort)
    if [[ "$expected_files" != "$present_files" ]]; then
      printf 'FIXTURE INTEGRITY: %s carries files other than its declared overrides (expected: %s; present: %s)\n' \
        "$case_id" "${expected_files//$'\n'/,}" "${present_files//$'\n'/,}" >&2
      ok=1
    fi

    IFS=: read -r own_fn own_relfile <<<"${FIXTURE_EXPECTED_DEFECT[$case_id]}"
    own_file="$case_dir/$own_relfile"
    if [[ ! -f "$own_file" ]]; then
      printf 'FIXTURE INTEGRITY: %s/%s missing\n' "$case_id" "$own_relfile" >&2
      ok=1
      continue
    fi
    if ! "$own_fn" "$own_file"; then
      printf 'FIXTURE INTEGRITY: %s/%s is missing its own intended seeded defect\n' "$case_id" "$own_relfile" >&2
      ok=1
    fi

    for entry in "${FIXTURE_KNOWN_CHECKS[@]}"; do
      IFS=: read -r desc fn relfile <<<"$entry"
      [[ "$relfile" == "$own_relfile" ]] || continue
      [[ "$fn" == "$own_fn" ]] && continue
      if "$fn" "$own_file"; then
        printf 'FIXTURE INTEGRITY: %s/%s carries an UNINTENDED known defect (%s) in addition to its seeded %s defect\n' \
          "$case_id" "$relfile" "$desc" "$case_id" >&2
        ok=1
      fi
    done
  done

  # R-API public-contract witness (separate from the loop above: this
  # defect is only observable when api.sh is combined with
  # clean/api_contract.sh -- the constructed-sandbox view every live
  # dispatch actually uses -- not the override file in isolation).
  if [[ ! -f "$fixture/clean/api_contract.sh" ]]; then
    printf 'FIXTURE INTEGRITY: clean/api_contract.sh missing -- R-API public-contract witness not present\n' >&2
    ok=1
  else
    if api_violates_public_contract "$fixture/clean" "$fixture/clean/api.sh"; then
      printf 'FIXTURE INTEGRITY: clean/api.sh violates its own declared public contract -- clean must satisfy it\n' >&2
      ok=1
    fi
    if [[ -f "$fixture/cases/R-API/api.sh" ]] && ! api_violates_public_contract "$fixture/clean" "$fixture/cases/R-API/api.sh"; then
      printf 'FIXTURE INTEGRITY: cases/R-API/api.sh does not violate the public contract -- R-API is missing its observable seeded defect\n' >&2
      ok=1
    fi
  fi

  # Scorer attribution integrity (docs/evidence/
  # 2026-09-04-reviewer-fixture-integrity-remediation.md, part 2): for
  # every case that declares a diff-derived "witness" substring
  # (cases/<id>/ground-truth.json), the witness must genuinely discriminate
  # -- present in the override, absent from clean -- or the scorer's
  # witness-matched attribution (eval/scoring/reviewer.sh) would silently
  # fail closed for every future dispatch of that case. Checked here, at
  # admission time, not only in CI, so drift is caught before a single
  # credit is spent, the same principle as the fixture-defect checks above.
  local case_dir2 gt_file witness override_rel clean_file override_file
  for case_dir2 in "$fixture"/cases/*/; do
    case_id=$(basename "${case_dir2%/}")
    gt_file="$case_dir2/ground-truth.json"
    [[ -f "$gt_file" ]] || continue
    if ! python3 -c 'import json,sys; sys.exit(0 if "witness" in json.load(open(sys.argv[1])) else 1)' "$gt_file"; then
      continue
    fi
    witness=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("witness") or "")' "$gt_file")
    if [[ -z "$witness" ]]; then
      printf 'FIXTURE INTEGRITY: %s witness is present but empty -- an empty substring matches anything, invalid\n' "$case_id" >&2
      ok=1
      continue
    fi
    override_rel=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["overrides"][0])' "$gt_file")
    clean_file="$fixture/clean/$override_rel"
    override_file="$case_dir2$override_rel"
    if [[ ! -f "$clean_file" || ! -f "$override_file" ]]; then
      printf 'FIXTURE INTEGRITY: %s witness check cannot run -- %s or %s missing\n' "$case_id" "$clean_file" "$override_file" >&2
      ok=1
      continue
    fi
    if [[ "$(<"$override_file")" != *"$witness"* ]]; then
      printf 'FIXTURE INTEGRITY: %s witness %q is not present in %s -- scorer attribution would always miss this case\n' \
        "$case_id" "$witness" "$override_file" >&2
      ok=1
    fi
    if [[ "$(<"$clean_file")" == *"$witness"* ]]; then
      printf 'FIXTURE INTEGRITY: %s witness %q is also present in %s -- does not discriminate\n' \
        "$case_id" "$witness" "$clean_file" >&2
      ok=1
    fi
  done

  return "$ok"
}
