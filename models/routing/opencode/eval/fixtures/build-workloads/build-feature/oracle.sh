#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workspace=$1
fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

same_hash() { [[ "$(sha256sum "$1" | cut -d' ' -f1)" == "$(sha256sum "$2" | cut -d' ' -f1)" ]]; }

[[ -f "$workspace/lib/strings.sh" ]]
# style-agnostic: any valid bash function-definition syntax for `reverse`
# is accepted, not just one literal declaration form.
( source "$workspace/lib/strings.sh"; declare -F reverse >/dev/null )
# tests/{acceptance,regression}.sh must not be edited: the test files
# themselves are trusted evidence, not workspace content the task should
# ever need to change.
same_hash "$workspace/tests/acceptance.sh" "$fixture/snapshot/tests/acceptance.sh"
same_hash "$workspace/tests/regression.sh" "$fixture/snapshot/tests/regression.sh"
bash "$workspace/tests/acceptance.sh"
bash "$workspace/tests/regression.sh"
same_hash "$workspace/README.md" "$fixture/snapshot/README.md"
