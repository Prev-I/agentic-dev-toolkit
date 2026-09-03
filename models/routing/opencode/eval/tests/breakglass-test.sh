#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/validate-breakglass.sh"

validate_breakglass "$root/runtime/opencode-v1-adapter/phase-0-security-profile.json"
assert_contains "$(<"$root/runtime/opencode-v1-adapter/phase-0-security-profile.json")" '"breakglass": "deny"'
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
for mutation in human task production; do
  file=$(mktemp)
  case "$mutation" in
    human) printf '{"non_production":true,"breakglass":{"mode":"primary","model":"openai/gpt-5.6-sol","variant":"max","human_selection_only":false,"task_routable":false}}' >"$file" ;;
    task) printf '{"non_production":true,"breakglass":{"mode":"primary","model":"openai/gpt-5.6-sol","variant":"max","human_selection_only":true,"task_routable":true}}' >"$file" ;;
    production) printf '{"non_production":false,"breakglass":{"mode":"primary","model":"openai/gpt-5.6-sol","variant":"max","human_selection_only":true,"task_routable":false}}' >"$file" ;;
  esac
  if validate_breakglass "$file"; then fail "accepted unsafe Breakglass $mutation mutation"; fi
  rm -f "$file"
done
file=$(mktemp)
printf '{"non_production":true,"normal_agent_task_permissions":{"*":"allow","breakglass":"deny"},"breakglass":{"mode":"primary","model":"openai/gpt-5.6-sol","variant":"max","human_selection_only":true,"task_routable":false,"hidden":false}}' >"$file"
validate_breakglass "$file"
rm -f "$file"
printf 'PASS: Breakglass invariant\n'
