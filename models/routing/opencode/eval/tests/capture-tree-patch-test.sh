#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT

mkdir -p "$w/before/sub" "$w/after/sub" "$w/replay/sub"
printf 'old\n' >"$w/before/sub/a.txt"
printf 'same\n' >"$w/before/sub/b.txt"
cp -R "$w/before/." "$w/replay/"
printf 'new-no-newline' >"$w/after/sub/a.txt"
printf 'same\n' >"$w/after/sub/b.txt"
printf 'added\n' >"$w/after/sub/c.txt"

bash "$root/runtime/opencode-v1-adapter/capture-tree-patch.sh" \
  "$w/before" "$w/after" "$w/change.patch"
patch --batch -d "$w/replay" -p1 <"$w/change.patch" >/dev/null
cmp "$w/replay/sub/a.txt" "$w/after/sub/a.txt"
cmp "$w/replay/sub/b.txt" "$w/after/sub/b.txt"
cmp "$w/replay/sub/c.txt" "$w/after/sub/c.txt"
assert_contains "$(<"$w/change.patch")" 'No newline at end of file'

printf 'PASS: frozen tree patch round-trips files without final newlines\n'
