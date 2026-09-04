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

# R-API seed: the documented public field was silently renamed from
# displayName to name. Present if the emitted JSON uses "name" instead of
# "displayName".
api_emits_renamed_field() {
  local file=$1
  local output
  output=$(source "$file"; public_response probe)
  [[ "$output" == *'"name"'* && "$output" != *'"displayName"'* ]]
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
