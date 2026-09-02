#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/probe.sh"

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
mkdir "$fake/repo"
git -C "$fake/repo" init -q
git -C "$fake/repo" config user.email phase0@example.invalid
git -C "$fake/repo" config user.name "Phase 0 Test"
git -C "$fake/repo" commit --allow-empty -qm baseline
expected_commit=$(git -C "$fake/repo" rev-parse HEAD)
cat >"$fake/opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf '1.18.26\n'; exit 0; fi
if [[ "$*" == *fail-model* ]]; then printf 'provider unavailable\n' >&2; exit 7; fi
printf '%s\n' '{"type":"text","part":{"text":"CAPABILITY_OK","metadata":{"provider":{"itemId":"sensitive"}}}}' '{"type":"step_finish","part":{"tokens":{"total":12,"input":10,"output":2,"reasoning":0,"cache":{"write":0,"read":0}},"cost":1.25}}'
FAKE
chmod +x "$fake/opencode"
output="$fake/result.json"
OPENCODE_BIN="$fake/opencode" PROBE_REPOSITORY="$fake/repo" probe_model_variant github-copilot/test-model high "$output"
assert_contains "$(<"$output")" '"classification": "USABLE"'
assert_contains "$(<"$output")" '"variant": "high"'
assert_contains "$(<"$output")" '"exact_invocation"'
assert_contains "$(<"$output")" '"observed_cost": 1.25'
assert_contains "$(<"$output")" '"tokens": 12'
assert_contains "$(<"$output")" "\"repository_commit\": \"$expected_commit\""
assert_contains "$(<"$output")" '"environment"'
if grep -q 'sensitive\|raw_response\|sessionID' "$output"; then fail "raw provider metadata persisted"; fi
OPENCODE_BIN="$fake/opencode" probe_model_variant openai/gpt-5.6-sol max "$fake/openai.json"
assert_contains "$(<"$fake/openai.json")" '"pricing_regime": "standard"'
if OPENCODE_BIN="$fake/opencode" probe_model_variant github-copilot/fail-model high "$fake/failure.json"; then
  fail "failed probe returned success"
fi
assert_contains "$(<"$fake/failure.json")" '"exit_status": 7'
assert_contains "$(<"$fake/failure.json")" '"error_text": "provider unavailable"'
printf 'PASS: OpenCode probe adapter\n'
