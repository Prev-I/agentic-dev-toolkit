#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"

make_fake() { local n=$1; cat >"$workspace/$n"; chmod +x "$workspace/$n"; }

make_fake opencode-solves <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$PWD" >"${BUILD_CWD_SINK:-/dev/null}"
printf '%s\n' "$*" >"${BUILD_ARGS_SINK:-/dev/null}"
cat >>lib/math.sh <<'SH'

double() {
  printf '%s\n' $(( $1 * 2 ))
}
SH
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"added double"}}\n'
FAKE

make_fake opencode-idle <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":10}}}\n'
printf '{"type":"text","part":{"text":"nothing to do"}}\n'
FAKE

make_fake opencode-scope <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
cat >>lib/math.sh <<'SH'

double() {
  printf '%s\n' $(( $1 * 2 ))
}
SH
printf 'tampered\n' >>README.md
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"done"}}\n'
FAKE

make_fake opencode-regress <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
cat >lib/math.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
double() { printf '%s\n' $(( $1 * 2 )); }
SH
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"done"}}\n'
FAKE

pass_dir="$workspace/pass"
BUILD_CWD_SINK="$workspace/cwd.txt" BUILD_ARGS_SINK="$workspace/args.txt" \
  OPENCODE_BIN="$workspace/opencode-solves" \
  run_build_restoration_gate --outdir "$pass_dir" --ledger "$ledger" --attempt 1 \
  || fail "a correct implementation did not satisfy the committed oracle"
assert_contains "$(<"$workspace/args.txt")" '--agent build'
assert_contains "$(<"$pass_dir/attempt.json")" '"oracle_passed": true'
assert_contains "$(<"$pass_dir/attempt.json")" '"acceptance_initially_failing": true'
assert_contains "$(<"$pass_dir/attempt.json")" '"fixture": "build-restoration-gate"'
assert_contains "$(<"$pass_dir/attempt.json")" '"runner_decides_gate_outcome": false'
assert_file "$pass_dir/dispatch/raw.jsonl"

for fake in idle scope regress; do
  target="$workspace/fail-$fake"
  if OPENCODE_BIN="$workspace/opencode-$fake" \
       run_build_restoration_gate --outdir "$target" --ledger "$ledger" --attempt 1; then
    fail "oracle accepted the '$fake' outcome"
  fi
  assert_contains "$(<"$target/attempt.json")" '"oracle_passed": false'
done

model_dir="$workspace/control"
BUILD_ARGS_SINK="$workspace/control-args.txt" OPENCODE_BIN="$workspace/opencode-solves" \
  run_build_restoration_gate --outdir "$model_dir" --ledger "$ledger" --attempt 1 \
    --model github-copilot/claude-sonnet-5 --variant high \
  || fail "explicit fixture-control dispatch failed"
assert_contains "$(<"$workspace/control-args.txt")" '--model github-copilot/claude-sonnet-5 --variant high'

# The adapter must not re-implement the state machine or classification.
runner="$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
for forbidden in VALID_CONTROLLER_FAILURE FIXTURE_DEFECT build_gate 'n=5' '4/5' '3/3'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "build runner re-implements committed decision logic: $forbidden"
  fi
done

printf 'PASS: build restoration gate runner\n'
