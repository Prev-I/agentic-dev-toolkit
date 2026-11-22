#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2. Changes: python
# runs isolated (-I -B), and both trees' prefixes are rewritten on both sides,
# because git diff --no-index names an added file by the after tree's path on
# its a/ side too (and a deleted one by the before tree's on its b/ side); V1
# left those headers unappliable.
set -Eeuo pipefail
IFS=$'\n\t'

before=$1
after=$2
output=$3

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
set +e
git diff --no-index --binary --no-renames --src-prefix=a/ --dst-prefix=b/ -- "$before" "$after" >"$tmp"
status=$?
set -e
(( status == 0 || status == 1 )) || exit "$status"
python3 -I -B - "$tmp" "$before" "$after" "$output" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
before = sys.argv[2].rstrip("/") + "/"
after = sys.argv[3].rstrip("/") + "/"
for side in ("a", "b"):
    for tree in (before, after):
        text = text.replace(side + tree, side + "/")
open(sys.argv[4], "w", encoding="utf-8", errors="surrogateescape").write(text)
PY
