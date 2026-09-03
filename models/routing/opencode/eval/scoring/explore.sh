#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

explore_gate() {
  python3 - "$1" "$2" <<'PY'
import json,sys
expected=json.load(open(sys.argv[1],encoding="utf-8"))
actual=json.load(open(sys.argv[2],encoding="utf-8"))
passed=(actual.get("ordered_path")==expected["ordered_path"] and actual.get("reported_hops")==expected["required_hops"] and actual.get("terminal_symbol")==expected["terminal_symbol"] and actual.get("terminal_value")==expected["terminal_value"])
print("pass" if passed else "block")
PY
}
