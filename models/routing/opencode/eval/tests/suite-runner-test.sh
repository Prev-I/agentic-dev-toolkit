#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
printf '#!/bin/bash\necho PASS: synthetic\n' >"$w/a-test.sh"
printf '#!/bin/bash\necho FAIL: synthetic\nexit 1\n' >"$w/b-test.sh"
printf '#!/bin/bash\necho SKIP: synthetic prerequisite\nexit 77\n' >"$w/c-test.sh"
printf '#!/bin/bash\necho PASS: last-test-executed\n' >"$w/d-test.sh"
if out=$(EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" 2>&1); then fail 'runner ignored failure'; fi
assert_contains "$out" 'last-test-executed'
assert_contains "$out" 'SUMMARY: PASS=2 FAIL=1 SKIP=1'
rm "$w/b-test.sh"
EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" >/dev/null
if EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" --strict >/dev/null; then fail 'strict runner ignored skip'; fi
printf '#!/bin/bash\nexit 77\n' >"$w/b-test.sh"
if out=$(EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" 2>&1); then fail 'bare exit77 counted as skip'; fi
assert_contains "$out" 'FAIL b-test.sh (exit 77)'
printf '#!/bin/bash\necho SKIP: partial\nexit 1\n' >"$w/b-test.sh"
if out=$(EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" 2>&1); then fail 'failure hidden by SKIP line'; fi
assert_contains "$out" 'FAIL b-test.sh (exit 1)'
rm "$w/b-test.sh"
printf '#!/bin/bash\necho SKIP: partial assertion\n' >"$w/c-test.sh"
out=$(EVAL_TEST_DIR="$w" bash "$root/run-tests.sh")
assert_contains "$out" 'PASS=2 FAIL=0 SKIP=1'
rm "$w/c-test.sh"
EVAL_TEST_DIR="$w" bash "$root/run-tests.sh" --strict >/dev/null
if bash "$root/run-tests.sh" --unknown >/dev/null 2>&1; then fail 'unknown argument accepted'; else assert_eq 2 "$?" 'usage error'; fi
printf 'PASS: suite aggregates every test and strict mode rejects skips\n'
