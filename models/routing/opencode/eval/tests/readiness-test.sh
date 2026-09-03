#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/validate-readiness.sh"
manifest="$root/manifests/phase-0-readiness.json"
validate_phase0_readiness "$manifest"
assert_contains "$(<"$manifest")" '"phase_0_complete": true'
w=$(mktemp); trap 'rm -f "$w"' EXIT
python3 - "$manifest" "$w" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["gates"][0]["status"]="UNKNOWN"; json.dump(d,open(sys.argv[2],"w"))
PY
if validate_phase0_readiness "$w"; then fail "accepted unknown readiness status"; fi
printf 'PASS: Phase 0 readiness matrix\n'
