#!/usr/bin/env bash
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
python3 - "$tmp" "$before" "$after" "$output" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
before = sys.argv[2].rstrip("/") + "/"
after = sys.argv[3].rstrip("/") + "/"
text = text.replace("a" + before, "a/").replace("b" + after, "b/")
open(sys.argv[4], "w", encoding="utf-8", errors="surrogateescape").write(text)
PY
