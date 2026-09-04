#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"

ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
assert_eq '0' "$(ledger_spent "$ledger" evaluation)"
assert_eq '0' "$(ledger_spent "$ledger" recovery)"

ledger_admit "$ledger" evaluation 40 || fail "rejected a run inside the evaluation budget"
ledger_append "$ledger" evaluation preflight-plan github-copilot 40
assert_eq '40' "$(ledger_spent "$ledger" evaluation)"

ledger_admit "$ledger" evaluation 60 || fail "rejected a run that exactly fills the budget"
ledger_append "$ledger" evaluation build-run-1 github-copilot 60
assert_eq '100' "$(ledger_spent "$ledger" evaluation)"

if ledger_admit "$ledger" evaluation 1; then
  fail "admitted a run that would exceed the 100-credit evaluation budget"
fi
if ledger_admit "$ledger" evaluation 1 --reclaim-recovery; then
  fail "allowed evaluation to reclaim the non-reclaimable recovery budget"
fi

ledger_admit "$ledger" recovery 250 || fail "rejected a run inside the recovery budget"
ledger_append "$ledger" recovery bisect-build github-copilot 250
if ledger_admit "$ledger" recovery 1; then
  fail "admitted a run that would exceed the 250-credit recovery budget"
fi

assert_eq 'null' "$(ledger_credits_from_cost openai 0.5)"
assert_eq 'null' "$(ledger_credits_from_cost github-copilot null)"
assert_eq '50.0' "$(ledger_credits_from_cost github-copilot 0.5)"

assert_contains "$(<"$ledger")" '"recovery_reclaimable_for_eval": false'
assert_contains "$(<"$ledger")" '"organization_guardrail_credits": 7600'

printf 'PASS: Phase R budget ledger\n'
