#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Shared helpers for the Claude Code routing suites. Sourced, never run.
tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bundle=$(cd "$tests_dir/../.." && pwd)
lib_dir="$bundle/eval/lib"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [[ "$2" == "$1" ]] || fail "expected '$1', got '$2'"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected '$1' to contain '$2'"
}

py() {
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$lib_dir" python3 "$@"
}
