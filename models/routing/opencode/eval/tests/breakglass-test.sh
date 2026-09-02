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
file=$(mktemp)
printf '{"mode":"primary","model":"openai/gpt-5.6-sol","variant":"max","breakglass":{"mode":"all"}}' >"$file"
if validate_breakglass "$file"; then fail "accepted unrelated primary mode"; fi
rm -f "$file"
printf 'PASS: Breakglass invariant\n'
