#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/compaction.sh"
oracle="$root/fixtures/compaction-invariants/oracle.json"
w=$(mktemp); trap 'rm -f "$w"' EXIT
cat >"$w" <<'JSON'
{"invariants":{"INV-RUNTIME":"OpenCode V1","INV-BREAKGLASS":"human-selected primary only","INV-BUDGET":"250 credits reserved; evaluation cannot reclaim them","INV-FAILURE":"valid controller failures stay in the denominator"},"contradictions":[]}
JSON
assert_eq pass "$(compaction_structured_gate "$oracle" "$w")"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["invariants"].pop("INV-FAILURE"); json.dump(d,open(p,"w"))' "$w"
assert_eq block "$(compaction_structured_gate "$oracle" "$w")"
cat >"$w" <<'JSON'
{"invariants":{"INV-RUNTIME":"target_runtime=opencode-v1","INV-BREAKGLASS":"breakglass=primary-human-only","INV-BUDGET":"phase-r-recovery-budget=250-credits-non-reclaimable","INV-FAILURE":"valid-controller-failure=remains-in-denominator"},"contradictions":[{"id":"INV-BUDGET","value":"evaluation may reclaim unused recovery credits"}]}
JSON
assert_eq block "$(compaction_structured_gate "$oracle" "$w")"
printf 'PASS: Compaction ground truth\n'
