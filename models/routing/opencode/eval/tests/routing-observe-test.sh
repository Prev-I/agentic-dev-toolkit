#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
python3 "$root/observe/tests/test_observe.py"
