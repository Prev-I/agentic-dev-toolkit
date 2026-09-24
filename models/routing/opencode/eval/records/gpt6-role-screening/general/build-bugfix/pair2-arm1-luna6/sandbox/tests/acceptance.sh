#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/lib/validate.sh"
if is_positive 0; then
  echo "is_positive(0) must be false" >&2
  exit 1
fi
is_positive 1
if is_positive -3; then
  echo "is_positive(-3) must be false" >&2
  exit 1
fi
