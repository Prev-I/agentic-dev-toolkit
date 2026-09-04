#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/strings.sh"
declare -F reverse >/dev/null
[[ "$(reverse abc)" == cba ]]
