#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"
source "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

cat >"$workspace/sample.jsonc" <<'JSONC'
{
  // a line comment
  "model": "github-copilot/claude-opus-5",
  /* a block comment */
  "note": "a // slash inside a string is not a comment",
  "agent": {
    "plan": { "variant": "max" },
  }
}
JSONC

read_key() { load_routing_profile "$workspace/sample.jsonc" | python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }
assert_eq 'github-copilot/claude-opus-5' "$(read_key '["model"]')"
assert_eq 'a // slash inside a string is not a comment' "$(read_key '["note"]')"
assert_eq 'max' "$(read_key '["agent"]["plan"]["variant"]')"

printf '{ "broken": ' >"$workspace/broken.jsonc"
if load_routing_profile "$workspace/broken.jsonc" >/dev/null 2>&1; then
  fail "accepted malformed JSONC"
fi

load_routing_profile "$root/../opencode.jsonc" >/dev/null || fail "cannot load the committed routing profile"

printf 'PASS: JSONC routing loader\n'
