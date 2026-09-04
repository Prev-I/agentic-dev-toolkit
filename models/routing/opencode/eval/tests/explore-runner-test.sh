#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/explore.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
oracle="$root/fixtures/explore-dependency-chain/oracle.json"

# Builds a fake `opencode` binary that reports $1 as its final-line answer.
# The answer is passed through python3's json.dumps at runtime rather than
# interpolated into a printf format string, because printf's own backslash
# processing can silently mangle a literal `\"` sequence embedded in a
# format string (unlike an argument passed positionally via %s).
fake_with() {
  local answer=$1
  cat >"$workspace/opencode-fake" <<FAKE
#!/usr/bin/env bash
if [[ "\${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "\$*" >>"\${EXPLORE_ARGS_SINK:-/dev/null}"
ls entry.sh >/dev/null || exit 3
printf '{"type":"step_finish","part":{"cost":0.01,"tokens":{"total":200}}}\n'
python3 -c 'import json,sys; print(json.dumps({"type":"text","part":{"text":sys.argv[1]}}))' '$answer'
FAKE
  chmod +x "$workspace/opencode-fake"
}

correct='{"ordered_path":["entry","facade","service","adapter","protocol"],"reported_hops":4,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}'
fake_with "$correct"
good="$workspace/good"
EXPLORE_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-fake" \
  run_explore_gate --outdir "$good" --ledger "$ledger" || fail "healthy explore dispatch reported failure"
assert_contains "$(<"$workspace/args.txt")" '--agent explore'
assert_eq 'pass' "$(explore_gate "$oracle" "$good/actual.json")"

# Terminal value alone must not pass: the oracle checks the whole chain.
partial='{"ordered_path":["entry","protocol"],"reported_hops":1,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}'
fake_with "$partial"
short="$workspace/short"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$short" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
assert_eq 'block' "$(explore_gate "$oracle" "$short/actual.json")"

# Right chain, wrong hop count still blocks.
miscount='{"ordered_path":["entry","facade","service","adapter","protocol"],"reported_hops":5,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}'
fake_with "$miscount"
bad="$workspace/bad"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$bad" --ledger "$ledger" || true
assert_eq 'block' "$(explore_gate "$oracle" "$bad/actual.json")"

# Unparseable prose produces a null-filled record, not a repaired one.
fake_with 'I traced it and the answer is v3.'
prose="$workspace/prose"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$prose" --ledger "$ledger" || true
python3 - "$prose/actual.json" <<'PY'
import json
import sys
actual = json.load(open(sys.argv[1], encoding="utf-8"))
assert actual["ordered_path"] is None, actual
assert actual["reported_hops"] is None, actual
assert actual["terminal_value"] is None, actual
PY
assert_eq 'block' "$(explore_gate "$oracle" "$prose/actual.json")"

runner="$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
for forbidden in 'PROTOCOL_VERSION' 'required_hops' '"v3"' 'facade'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "explore runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: explore gate runner\n'
