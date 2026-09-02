#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/math.sh"
declare -F double >/dev/null
[[ "$(double 3)" == 6 ]]
