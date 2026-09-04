#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/compaction.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
oracle="$root/fixtures/compaction-invariants/oracle.json"

fake_with() {
  python3 - "$workspace/opencode-fake" "$1" <<'PY'
import json
import sys
path, summary = sys.argv[1:]
script = f'''#!/usr/bin/env bash
if [[ "${{1:-}}" == --version ]]; then printf '1.18.27\\n'; exit 0; fi
printf '%s\\n' "$*" >"${{COMPACTION_ARGS_SINK:-/dev/null}}"
printf '{{"type":"step_finish","part":{{"cost":0.01,"tokens":{{"total":500}}}}}}\\n'
printf '%s\\n' {json.dumps(json.dumps({"type": "text", "part": {"text": summary}}))}
'''
open(path, "w", encoding="utf-8").write(script)
PY
  chmod +x "$workspace/opencode-fake"
}

all_four='Summary. [INV-RUNTIME] target_runtime=opencode-v1
[INV-BREAKGLASS] breakglass=primary-human-only
[INV-BUDGET] phase-r-recovery-budget=250-credits-non-reclaimable
[INV-FAILURE] valid-controller-failure=remains-in-denominator'
fake_with "$all_four"
good="$workspace/good"
COMPACTION_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-fake" \
  run_compaction_gate --outdir "$good" --ledger "$ledger" || fail "healthy compaction dispatch reported failure"
assert_contains "$(<"$workspace/args.txt")" '--agent compaction'
assert_file "$good/summary.txt"
assert_eq 'pass' "$(compaction_structured_gate "$oracle" "$good/actual.json")"

# An alias emitted inside the tag is the scorer's call, not the runner's.
aliased='[INV-RUNTIME] OpenCode V1
[INV-BREAKGLASS] human-selected primary only
[INV-BUDGET] 250 credits reserved; evaluation cannot reclaim them
[INV-FAILURE] valid controller failures stay in the denominator'
fake_with "$aliased"
alias_dir="$workspace/alias"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$alias_dir" --ledger "$ledger" || true
assert_eq 'pass' "$(compaction_structured_gate "$oracle" "$alias_dir/actual.json")"

# A dropped invariant blocks; the runner must not invent it.
three='[INV-RUNTIME] target_runtime=opencode-v1
[INV-BREAKGLASS] breakglass=primary-human-only
[INV-BUDGET] phase-r-recovery-budget=250-credits-non-reclaimable'
fake_with "$three"
short="$workspace/short"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$short" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); assert a["invariants"]["INV-FAILURE"] is None, a' "$short/actual.json"
assert_eq 'block' "$(compaction_structured_gate "$oracle" "$short/actual.json")"

# A contradictory restatement is recorded, not silently deduplicated.
contradictory="$all_four
Correction: [INV-BUDGET] phase-r-recovery-budget=0-credits"
fake_with "$contradictory"
conflict="$workspace/conflict"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$conflict" --ledger "$ledger" || true
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); assert "INV-BUDGET" in a["contradictions"], a' "$conflict/actual.json"
assert_eq 'block' "$(compaction_structured_gate "$oracle" "$conflict/actual.json")"

runner="$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
for forbidden in 'opencode-v1' 'primary-human-only' '250-credits' 'required_preserved' 'aliases'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "compaction runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: compaction gate runner\n'
