#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/probe.sh"

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
cat >"$fake/opencode" <<'FAKE'
#!/usr/bin/env bash
printf '{"type":"text","part":{"text":"CAPABILITY_OK"}}\n'
FAKE
chmod +x "$fake/opencode"
output="$fake/result.json"
OPENCODE_BIN="$fake/opencode" probe_model_variant github-copilot/test-model high "$output"
assert_contains "$(<"$output")" '"classification": "USABLE"'
assert_contains "$(<"$output")" '"variant": "high"'
assert_contains "$(<"$output")" '"exact_invocation"'
printf 'PASS: OpenCode probe adapter\n'
