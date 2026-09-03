#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workspace=$1
fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ -f "$workspace/lib/math.sh" ]]
grep -q '^double()' "$workspace/lib/math.sh"
bash "$workspace/tests/acceptance.sh"
bash "$workspace/tests/regression.sh"
[[ "$(sha256sum "$workspace/README.md" | cut -d' ' -f1)" == "$(sha256sum "$fixture/snapshot/README.md" | cut -d' ' -f1)" ]]
