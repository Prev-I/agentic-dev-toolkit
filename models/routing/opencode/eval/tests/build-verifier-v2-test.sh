#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/tests/prerequisites.sh"
require_system_python
require_command direnv
script="$root/records/opus55-gpt61-build-quality-screening/verify-results-v2.sh"
assert_file "$script"
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
/usr/bin/python3 "$root/tools/snapshot-verifier.py" --controls-only --out "$w/result"
/usr/bin/python3 - "$w/result/summary.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['classification'] == 'POST_RUN_DIAGNOSTIC'
assert d['controls_passed'] is True
assert d['reference']['immutable_suite'] == 0
assert d['reference']['candidate_suite'] == 0
assert d['reference']['oracle'] == 0
assert d['reference']['empty_path'] == 0
assert d['reference']['mutation_classification'] == 'BEHAVIORAL_ASSERTION'
assert d['attempts'] == []
assert d['python_executable'].startswith('/usr/bin/python3')
PY
printf 'PASS: verifier v2 controls pass before candidate evaluation\n'
