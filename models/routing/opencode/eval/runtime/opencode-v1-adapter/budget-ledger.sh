#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ledger_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ledger_root/provenance.sh"

ledger_init() {
  local ledger=$1 budgets=$2
  [[ -f "$ledger" ]] && return 0
  python3 - "$ledger" "$budgets" <<'PY'
import json
import sys

ledger_path, budgets_path = sys.argv[1:]
budgets = json.load(open(budgets_path, encoding="utf-8"))
document = {
    "caps": {
        "evaluation": budgets["eval_budget_credits"],
        "recovery": budgets["phase_r_recovery_budget_credits"],
    },
    "recovery_reclaimable_for_eval": budgets["recovery_budget_reclaimable_for_eval"],
    "organization_guardrail_credits": budgets["organizational_user_guardrail_credits"],
    "at_guardrail": budgets["at_guardrail"],
    "entries": [],
}
with open(ledger_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

ledger_spent() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

ledger, account = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
total = sum(entry["credits"] for entry in document["entries"] if entry["account"] == account)
print(int(total) if float(total).is_integer() else total)
PY
}

ledger_admit() {
  local ledger=$1 account=$2 projected=$3 reclaim=${4:-}
  [[ "$reclaim" != "--reclaim-recovery" ]] || return 1
  python3 - "$ledger" "$account" "$projected" <<'PY'
import json
import sys

ledger, account, projected = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
cap = document["caps"][account]
spent = sum(entry["credits"] for entry in document["entries"] if entry["account"] == account)
raise SystemExit(0 if spent + float(projected) <= cap else 1)
PY
}

ledger_append() {
  local ledger=$1 account=$2 label=$3 provider=$4 credits=$5
  python3 - "$ledger" "$account" "$label" "$provider" "$credits" <<'PY'
import datetime
import json
import sys

ledger, account, label, provider, credits = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
document["entries"].append({
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "account": account,
    "label": label,
    "provider": provider,
    "credits": float(credits),
})
with open(ledger, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

ledger_credits_from_cost() {
  local provider=$1 cost=$2
  [[ -n "$cost" && "$cost" != null ]] || { printf 'null\n'; return; }
  derive_copilot_credits "$provider" USD copilot_provider_reported "$cost"
}
