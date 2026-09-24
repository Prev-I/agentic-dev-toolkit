#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/validate.sh"
is_blank ""
is_blank "   "
if is_blank "x"; then
  echo "is_blank(x) must be false" >&2
  exit 1
fi
