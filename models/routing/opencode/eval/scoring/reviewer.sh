#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

reviewer_gate() {
  local required=$1 detected=$2 allowed_clean=$3 clean_findings=$4
  if (( detected >= required && clean_findings <= allowed_clean )); then printf 'pass\n'; else printf 'block\n'; fi
}

# Attribution note (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md):
# a case is credited ONLY when the finding evidence is unambiguous -- exactly
# one material/blocking finding reported against the case's own override
# file(s). Zero such findings is a miss. Two or more is UNRESOLVABLE by this
# scorer (file + severity is the only structured evidence the Reviewer
# output contract currently provides -- there is no defect-identity field to
# disambiguate which finding is the seeded one) and fails closed rather than
# guessing via severity rank, as the prior "highest severity wins"
# normalization did. This does NOT solve the case of a single material
# finding that is actually about an unrelated defect -- that is a documented,
# open limitation of the current contract, not something this fix claims to
# fix. Findings payloads without "all_reported"/"files" (older/simplified
# shapes) fall back to trusting the top-level severity field directly.
_reviewer_attribution_py() {
  cat <<'PY'
import json
import os
import sys

def classify(item, material):
    all_reported = item.get("all_reported")
    files = item.get("files")
    if all_reported is None or files is None:
        # legacy/simplified shape: trust the top-level severity as-is.
        return "detected" if item.get("severity") in material else "missed"
    override_names = {os.path.basename(str(f)) for f in files}
    matches = [f for f in all_reported
               if os.path.basename(str(f.get("file", ""))) in override_names
               and f.get("severity") in material]
    if len(matches) == 0:
        return "missed"
    if len(matches) == 1:
        return "detected"
    return "ambiguous"

oracle = json.load(open(sys.argv[1], encoding="utf-8"))
findings = json.load(open(sys.argv[2], encoding="utf-8"))
material = set(oracle["material_severities"])
classification = {item["id"]: classify(item, material) for item in findings["seeded"]}
PY
}

reviewer_structured_gate() {
  { _reviewer_attribution_py; cat <<'PY'
clean_material = [item for item in findings["clean"] if item.get("severity") in material]
expected = set(oracle["expected_ids"])
detected = {case_id for case_id, verdict in classification.items() if verdict == "detected"}
passed = (len(expected) == oracle["required_seeded_detections"] and detected == expected and len(detected) == oracle["required_seeded_detections"] and len(clean_material) == oracle["allowed_clean_material_findings"])
print("pass" if passed else "block")
PY
  } | python3 - "$1" "$2"
}

# Diagnostic companion to reviewer_structured_gate: prints the per-case
# classification (detected/missed/ambiguous) as JSON, without collapsing it
# to a single pass/block verdict. Useful for reporting exactly which cases
# are unresolved rather than only knowing the gate blocked.
reviewer_structured_attribution() {
  { _reviewer_attribution_py; cat <<'PY'
print(json.dumps(classification, indent=2))
PY
  } | python3 - "$1" "$2"
}
