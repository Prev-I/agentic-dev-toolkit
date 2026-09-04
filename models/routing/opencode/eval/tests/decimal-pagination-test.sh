#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Root cause (see docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md):
# clean/pagination.sh's numeric guard, `[[ "$1" =~ ^[0-9]+$ ]]`, only proves the
# input is all-decimal-digit CHARACTERS. The value is then handed to bash's `(( ))`
# arithmetic evaluator, which (per `man bash`, ARITHMETIC EVALUATION: "Constants
# with a leading 0 are interpreted as octal numbers") re-parses any leading-zero
# string in octal, not decimal. This makes the guard's decimal assumption false for
# any leading-zero input: "0144" is evaluated as octal 144 = decimal 100 (silently
# in-range instead of correctly rejected as 144 > 100), and "08"/"09" contain
# digits invalid in octal, so `(( ))` raises a shell arithmetic error instead of
# evaluating decimal 8/9.
#
# This test encodes the DESIRED decimal-only semantics (domain: integer 1..100)
# and is the RED regression proving clean/pagination.sh's current implementation
# violates it. It must be committed failing (or documented as failing) before any
# fix, and pass after the fix in this same commit series.

pagination_sh="$root/fixtures/reviewer-seeded-defects/clean/pagination.sh"
assert_file "$pagination_sh"
source "$pagination_sh"

expect_accept() {
  local value=$1
  if ! validate_page_size "$value" 2>/dev/null; then
    fail "expected '$value' to be ACCEPTED (valid 1..100 decimal), got rejected/errored"
  fi
}

expect_reject() {
  local value=$1
  # A crash (bash arithmetic syntax error) is not an acceptable form of
  # rejection -- it must fail *cleanly*, via the function's own return code,
  # not by aborting the calling shell. set +e / a subshell isolates any
  # `(( ))` syntax error so we can distinguish "clean reject" from "crashed".
  local rc=0
  if ( set +e; validate_page_size "$value" >/dev/null 2>&1 ); then
    rc=0
  else
    rc=$?
  fi
  (( rc != 0 )) || fail "expected '$value' to be REJECTED, got accepted"
}

# --- valid decimal domain: 1..100 ---
expect_accept 1
expect_accept 8
expect_accept 99
expect_accept 100

# --- invalid: outside 1..100, or non-numeric ---
expect_reject 0
expect_reject 101
expect_reject -1
expect_reject 1x
expect_reject abc
expect_reject ''

# --- the leading-zero / octal-reinterpretation regression cases ---
# "08" must be treated as decimal 8 (valid, in-range) -- not crash.
expect_accept 08
# "0144" must be treated as decimal 144 (invalid, > 100) -- not silently
# accepted as if it were octal 144 = decimal 100.
expect_reject 0144

printf 'PASS: decimal pagination semantics\n'
