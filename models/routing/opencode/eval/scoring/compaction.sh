#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

compaction_gate() { if (( $1 == $2 )); then printf 'pass\n'; else printf 'block\n'; fi; }

compaction_structured_gate() {
  python3 - "$1" "$2" <<'PY'
import json,sys
oracle=json.load(open(sys.argv[1],encoding="utf-8"))
actual=json.load(open(sys.argv[2],encoding="utf-8"))
preserved=0
for key, canonical in oracle["canonical"].items():
    value=actual.get("invariants",{}).get(key)
    if value == canonical or value in oracle.get("aliases",{}).get(key,[]): preserved += 1
contradictions=actual.get("contradictions",[])
passed=preserved==oracle["required_preserved"] and len(contradictions)==oracle["allowed_contradictions"]
print("pass" if passed else "block")
PY
}
