#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fake="$w/opencode"
cat >"$fake" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf 'test-runtime\n'; exit 0; fi
trap 'exit 143' TERM
printf '%s\n' '{"type":"step_finish","part":{"cost":0.3}}'
sleep 2
printf '%s\n' '{"type":"step_finish","part":{"cost":0.3}}'
sleep 30
SH
chmod +x "$fake"

set +e
output=$(EVAL_REAL_OPENCODE="$fake" EVAL_CALL_STOP_CREDITS=50 \
  bash "$root/runtime/opencode-v1-adapter/capped-opencode.sh" run 2>&1)
status=$?
set -e
assert_eq 143 "$status" "completed-step wrapper must stop at the credit threshold"
assert_contains "$output" 'EVAL_BUDGET_STOP'
assert_contains "$output" '"cost":0.3'

version=$(EVAL_REAL_OPENCODE="$fake" EVAL_CALL_STOP_CREDITS=50 \
  bash "$root/runtime/opencode-v1-adapter/capped-opencode.sh" --version)
assert_eq test-runtime "$version" "version probes must reach the wrapped binary"

cat >"$fake" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf 'test-runtime\n'; exit 0; fi
printf '%s\n' '{"type":"step_finish","part":{"cost":0.1}}'
SH
chmod +x "$fake"
under=$(EVAL_REAL_OPENCODE="$fake" EVAL_CALL_STOP_CREDITS=50 \
  bash "$root/runtime/opencode-v1-adapter/capped-opencode.sh" run)
assert_contains "$under" '"cost":0.1'

printf 'PASS: completed-step budget wrapper enforces the in-flight threshold\n'
