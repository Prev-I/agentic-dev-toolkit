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
python3 - "$manifest" "$w" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["gates"].pop(); json.dump(d,open(sys.argv[2],"w"))
PY
if validate_phase0_readiness "$w"; then fail "accepted missing readiness row"; fi
python3 - "$manifest" "$w" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); next(r for r in d["gates"] if r["gate"]=="breakglass_human_primary_execution")["status"]="BLOCKED_EXTERNAL"; d["phase_0_complete"]=False; json.dump(d,open(sys.argv[2],"w"))
PY
validate_phase0_readiness "$w"
assert_contains "$(<"$w")" '"phase_0_complete": false'
python3 - "$manifest" "$w" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["gates"][0].pop("rationale"); json.dump(d,open(sys.argv[2],"w"))
PY
if validate_phase0_readiness "$w"; then fail "accepted missing rationale"; fi
printf 'PASS: Phase 0 readiness matrix\n'
