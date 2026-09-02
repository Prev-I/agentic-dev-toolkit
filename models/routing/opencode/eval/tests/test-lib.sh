#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected=$1 actual=$2
  [[ "$actual" == "$expected" ]] || fail "expected '$expected', got '$actual'"
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected '$1' to contain '$2'"
}
