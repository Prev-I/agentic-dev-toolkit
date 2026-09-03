#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

reviewer_gate() {
  local required=$1 detected=$2 allowed_clean=$3 clean_findings=$4
  if (( detected >= required && clean_findings <= allowed_clean )); then printf 'pass\n'; else printf 'block\n'; fi
}

reviewer_structured_gate() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

oracle = json.load(open(sys.argv[1], encoding="utf-8"))
findings = json.load(open(sys.argv[2], encoding="utf-8"))
material = set(oracle["material_severities"])
detected = {item["id"] for item in findings["seeded"] if item.get("severity") in material}
clean_material = [item for item in findings["clean"] if item.get("severity") in material]
passed = detected == set(oracle["expected_ids"]) and len(clean_material) == oracle["allowed_clean_material_findings"]
print("pass" if passed else "block")
PY
}
