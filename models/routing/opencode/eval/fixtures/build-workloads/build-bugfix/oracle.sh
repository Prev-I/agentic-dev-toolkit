#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workspace=$1
fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ -f "$workspace/lib/validate.sh" ]]
bash "$workspace/tests/acceptance.sh"
bash "$workspace/tests/regression.sh"
[[ "$(sha256sum "$workspace/README.md" | cut -d' ' -f1)" == "$(sha256sum "$fixture/snapshot/README.md" | cut -d' ' -f1)" ]]

# forbidden scope: is_blank's own definition must not change, even though
# is_positive (the same file) legitimately must.
extract_is_blank() {
  python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"is_blank\(\)\s*\{.*?\n\}", text, re.S)
print(m.group(0) if m else "")
' "$1"
}
[[ "$(extract_is_blank "$workspace/lib/validate.sh")" == "$(extract_is_blank "$fixture/snapshot/lib/validate.sh")" ]]
