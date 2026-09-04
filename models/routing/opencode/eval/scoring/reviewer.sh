#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

reviewer_gate() {
  local required=$1 detected=$2 allowed_clean=$3 clean_findings=$4
  if (( detected >= required && clean_findings <= allowed_clean )); then printf 'pass\n'; else printf 'block\n'; fi
}

# Attribution note (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
# part 2, "Revisit scorer attribution from first principles"):
#
# A case is credited only when a material/blocking finding against its own
# override file(s) is UNAMBIGUOUSLY attributable to its seeded defect.
# "Attributable" means one of two things, depending on whether the case has
# a diff-derived witness substring (cases/<id>/ground-truth.json's
# "witness" field, present for addition/substitution mutations where the
# vulnerable version contains a literal token absent from the safe
# version -- R-API, R-BOUNDARY, R-ERROR as of this writing):
#
#   - WITH a witness: the finding's "evidence" field (the eval-only
#     dispatch contract's verbatim-quote request, run-reviewer-gate.sh's
#     reviewer_request -- NOT the production Reviewer prompt) must contain
#     the witness substring as an exact match. This is deterministic exact
#     string containment, not fuzzy/semantic matching and not an LLM
#     judge. Zero matching findings: missed. Exactly one: detected. Two or
#     more: UNRESOLVABLE, fails closed as "ambiguous" rather than guessing.
#     No evidence field at all (model did not comply with the extended
#     contract): treated as non-matching, fails closed.
#     KNOWN, ACCEPTED RESIDUAL LIMITATION, wider than just whole-line
#     quoting: every fixture file is a single line, so ANY evidence quote
#     spanning enough of that line to include the witness will match --
#     including a SUB-LINE quote about a genuinely different concern that
#     happens to overlap the witness's position (independent review
#     constructed exactly this for R-API: a hallucinated finding about
#     JSON-injection, evidence `json.dumps({"name": sys.argv[1]})` -- the
#     "smallest snippet demonstrating the issue" a well-behaved model would
#     naturally quote for THAT concern -- scores "detected" because it
#     happens to contain R-API's witness, `{"name"`). This is not solved
#     here -- solving it fully would require restructuring the fixture
#     files so each concern occupies a separately-quotable region, out of
#     scope for this fix. The witness mechanism substantially narrows this
#     remediation's original incident (a DIFFERENT, unrelated finding
#     wrongly credited with no overlap check at all) without claiming to
#     eliminate every coincidental-overlap case.
#
#   - WITHOUT a witness (R-AUTH, R-CONCURRENCY -- both PURE REMOVALS of a
#     safety check, verified to introduce no usable literal token a genuine
#     finding would naturally quote): falls back to file+severity only,
#     the same rule as before. Stated precisely, not overclaimed:
#     fixture-integrity-test.sh proves these files trigger none of the 8
#     detectors currently defined -- but only ONE detector exists for
#     each of authorization.sh/counter.sh, so this is "no other KNOWN
#     defect class has a detector here yet", not "nothing else could
#     possibly be wrong". It does NOT protect against a hallucinated,
#     unrelated finding, and does so less substantively than for
#     pagination.sh/api.sh (2 detectors each); that residual
#     risk is real and not claimed to be closed.
#
# Findings payloads without "all_reported"/"files" at all (older/simplified
# shapes) fall back further, to trusting the top-level severity field
# directly -- unchanged from before, a real leniency path, flagged on
# stderr so a malformed/truncated/hand-edited findings.json doesn't score
# leniently without anyone noticing.
_reviewer_attribution_py() {
  cat <<'PY'
import json
import os
import sys

# Sentinel distinguishing "ground-truth.json read/parsed but has no witness
# key" (a genuine, expected non-witness case -- fall back to file+severity)
# from "ground-truth.json could not be read at all" (a configuration
# problem -- e.g. oracle.json used detached from its fixture tree -- that
# must fail closed for every case, not silently disable witness
# enforcement the way returning None for both would). An empty-string
# witness is also routed through UNREADABLE: "" is a substring of every
# string in Python, so treating it as a real witness would match anything.
UNREADABLE = object()

def load_witness(fixture_root, case_id):
    path = os.path.join(fixture_root, "cases", case_id, "ground-truth.json")
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"reviewer_structured_gate: cannot read {path} to resolve {case_id}'s "
              f"witness ({exc}) -- failing closed rather than assuming no witness applies",
              file=sys.stderr)
        return UNREADABLE
    witness = data.get("witness")
    if witness == "":
        print(f"reviewer_structured_gate: {case_id}'s witness is an empty string -- "
              f"an empty substring matches anything, treating as invalid and failing closed",
              file=sys.stderr)
        return UNREADABLE
    return witness

def classify(item, material, fixture_root):
    all_reported = item.get("all_reported")
    files = item.get("files")
    if all_reported is None or files is None:
        print(f"reviewer_structured_gate: {item.get('id')} has no all_reported/files "
              f"evidence -- falling back to trusting its top-level severity directly",
              file=sys.stderr)
        return "detected" if item.get("severity") in material else "missed"
    override_names = {os.path.basename(str(f)) for f in files}
    file_matches = [f for f in all_reported
                     if os.path.basename(str(f.get("file", ""))) in override_names
                     and f.get("severity") in material]
    witness = load_witness(fixture_root, item["id"])
    if witness is UNREADABLE:
        matches = []
    elif witness is not None:
        matches = [f for f in file_matches
                   if isinstance(f.get("evidence"), str) and witness in f["evidence"]]
    else:
        matches = file_matches
    if len(matches) == 0:
        return "missed"
    if len(matches) == 1:
        return "detected"
    return "ambiguous"

oracle_path = sys.argv[1]
oracle = json.load(open(oracle_path, encoding="utf-8"))
findings = json.load(open(sys.argv[2], encoding="utf-8"))
material = set(oracle["material_severities"])
fixture_root = os.path.dirname(os.path.abspath(oracle_path))
classification = {item["id"]: classify(item, material, fixture_root) for item in findings["seeded"]}
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
