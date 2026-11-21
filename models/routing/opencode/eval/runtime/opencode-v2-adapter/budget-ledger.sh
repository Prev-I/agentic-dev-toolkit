#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2. Changes: caps
# come from a JSON object {account: cap} instead of a budgets file, the
# recovery-reclaim path is gone, and credits are derived for every provider
# (cost * 100) because OpenCode 2 reports cost itself.
set -Eeuo pipefail
IFS=$'\n\t'
ledger_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/provenance.sh disable=SC1091 # path built from this script's own directory at run time
source "$ledger_root/provenance.sh"

ledger_init() {
  local ledger=$1 caps=$2
  [[ -f "$ledger" ]] && return 0
  python3 - "$ledger" "$caps" <<'PY'
import json
import sys

ledger_path, caps = sys.argv[1:]
document = {"caps": json.loads(caps), "entries": []}
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
  local ledger=$1 account=$2 projected=$3
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
  local cost=$1
  [[ -n "$cost" && "$cost" != null ]] || { printf 'null\n'; return; }
  python3 - "$cost" <<'PY'
import sys
print(float(sys.argv[1]) * 100)
PY
}
