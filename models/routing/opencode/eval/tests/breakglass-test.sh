#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/validate-breakglass.sh"

validate_breakglass "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json"
for mode in missing all subagent; do
  file=$(mktemp)
  if [[ "$mode" == missing ]]; then printf '{"breakglass":{}}' >"$file"; else printf '{"breakglass":{"mode":"%s"}}' "$mode" >"$file"; fi
  if validate_breakglass "$file"; then fail "accepted Breakglass mode $mode"; fi
  rm -f "$file"
done
printf 'PASS: Breakglass invariant\n'
