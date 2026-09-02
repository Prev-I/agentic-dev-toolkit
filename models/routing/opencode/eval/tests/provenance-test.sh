#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/provenance.sh"

record=$(emit_run_record profile sha 1.18.26 1 copilot model high standard)
for field in routing_profile_id routing_profile_commit runtime_version eval_runner_version timestamp provider model variant pricing_regime observed_cost normalized_steady_state_cost; do
  assert_contains "$record" "\"$field\""
done
assert_contains "$record" '"observed_cost":null'
validate_installed_manifest "$root/manifests/installed-profile.json"
invalid=$(mktemp)
trap 'rm -f "$invalid"' EXIT
printf 'profile_id source_commit installed_at opencode_version' >"$invalid"
if validate_installed_manifest "$invalid"; then fail "malformed manifest accepted"; fi
printf 'PASS: provenance and manifest\n'
