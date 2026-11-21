#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2. Changes: caps
# come from a JSON object {account: cap} instead of a budgets file, the
# recovery-reclaim path is gone, and credits are derived for every provider
# (cost * 100, rounded to 10 places) because OpenCode 2 reports cost itself.
# Writes are atomic, admission tolerates float noise and exits 2 on malformed
# input (1 means over budget), and python runs isolated (-I -B).
set -Eeuo pipefail
IFS=$'\n\t'
ledger_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/provenance.sh disable=SC1091 # path built from this script's own directory at run time
source "$ledger_root/provenance.sh"

ledger_init() {
  local ledger=$1 caps=$2
  [[ -f "$ledger" ]] && return 0
  python3 -I -B - "$ledger" "$caps" <<'PY'
import json
import sys

ledger_path, caps = sys.argv[1:]
document = {"caps": json.loads(caps), "entries": []}
import os
import tempfile
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(ledger_path)))
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
os.replace(tmp, ledger_path)
PY
}

ledger_spent() {
  python3 -I -B - "$1" "$2" <<'PY'
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
  python3 -I -B - "$ledger" "$account" "$projected" <<'PY'
import json
import sys

ledger, account, projected = sys.argv[1:]
try:
    document = json.load(open(ledger, encoding="utf-8"))
    cap = float(document["caps"][account])
    spent = sum(entry["credits"] for entry in document["entries"] if entry["account"] == account)
    projected = float(projected)
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(2)
raise SystemExit(0 if round(spent + projected, 10) <= round(cap, 10) else 1)
PY
}

ledger_append() {
  local ledger=$1 account=$2 label=$3 provider=$4 credits=$5
  python3 -I -B - "$ledger" "$account" "$label" "$provider" "$credits" <<'PY'
import datetime
import json
import os
import sys
import tempfile

ledger, account, label, provider, credits = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
document["entries"].append({
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "account": account,
    "label": label,
    "provider": provider,
    "credits": float(credits),
})
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(ledger)))
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
os.replace(tmp, ledger)
PY
}

ledger_credits_from_cost() {
  local cost=$1
  [[ -n "$cost" && "$cost" != null ]] || { printf 'null\n'; return; }
  python3 -I -B - "$cost" <<'PY'
import sys
print(round(float(sys.argv[1]) * 100, 10))
PY
}
