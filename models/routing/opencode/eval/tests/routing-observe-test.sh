#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
python3 "$root/observe/tests/test_observe.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/observe/tests/test_populations.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/observe/tests/test_activation.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/observe/tests/test_runtime.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/observe/tests/test_closure.py"
