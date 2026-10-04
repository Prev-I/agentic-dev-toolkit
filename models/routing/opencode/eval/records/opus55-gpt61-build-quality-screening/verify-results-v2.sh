#!/usr/bin/env bash
set -Eeuo pipefail
# Explicit executable, never discovered through the host PATH/mise shim.
[[ -x /usr/bin/python3 ]] || { printf 'Required interpreter absent: /usr/bin/python3\n' >&2; exit 2; }
/usr/bin/python3 -c 'import pathlib,sys,tomllib; p=pathlib.Path(sys.executable).resolve(); assert str(p).startswith("/usr/bin/python3"), p'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec /usr/bin/python3 "$root/verify-results-v2.py" "$@"
