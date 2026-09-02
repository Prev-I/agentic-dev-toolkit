#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/self-variance.sh"

state=$(mktemp)
trap 'rm -f "$state"' EXIT
if freeze_thresholds "$state"; then fail "thresholds froze before self-variance"; fi
record_self_variance "$state" true true true true
freeze_thresholds "$state"
assert_contains "$(<"$state")" 'thresholds_frozen=true'
printf 'PASS: self-variance ordering\n'
