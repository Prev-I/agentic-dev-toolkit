#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"

# Scorer attribution hardening (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
# section "Reviewer scorer attribution"). Traced root cause: the scorer credits
# a seeded case as "detected" whenever ANY material/blocking finding is
# reported against the case's override filename -- it never checks whether
# the finding's content is actually about the seeded defect. Confirmed real
# via a live R-BOUNDARY dispatch that was credited "material" for an entirely
# different, unrelated bug in the same file.
#
# KNOWN, DOCUMENTED LIMITATION: the current Reviewer output contract
# (file/severity/one-sentence-summary, no structured defect-identity field)
# gives the scorer no way to mechanically distinguish "the one material
# finding against this file IS the seeded defect" from "the one material
# finding against this file is a DIFFERENT, unrelated defect" -- both are the
# same shape of input. Solving that fully would require either an LLM
# semantic judge (explicitly out of scope for this remediation) or a change
# to the Reviewer's own output contract (explicitly out of scope: this
# remediation does not tune the Reviewer prompt). This suite does NOT claim
# to solve that case, and says so explicitly below.
#
# What IS mechanically fixable, and is fixed here: when MULTIPLE material
# findings are reported against the same override file, the scorer
# previously picked the highest-severity one silently ("highest severity the
# reviewer reported against the case's override file" -- the adapter's own
# stated normalization) with no signal that the case was ambiguous. That
# silently discards exactly the kind of noise that could mask a real
# detection or manufacture a false one. The fix: 2+ material findings against
# the same override file is UNAMBIGUOUSLY unresolvable by this scorer and
# must fail closed (not detected), rather than guessing via severity rank.

fixture="$root/fixtures/reviewer-seeded-defects"
findings_path="$fixture/.attribution-test-findings.json"
trap 'rm -f "$findings_path"' EXIT

write_findings() {
  # $1 = json for the "seeded" R-BOUNDARY entry's all_reported array
  python3 - "$findings_path" "$1" <<'PY'
import json, sys
path, all_reported_json = sys.argv[1:]
all_reported = json.loads(all_reported_json)
seeded = [
    {"id": "R-CONCURRENCY", "severity": "material", "files": ["counter.sh"],
     "all_reported": [{"file": "counter.sh", "severity": "material", "summary": "s"}]},
    {"id": "R-AUTH", "severity": "blocking", "files": ["authorization.sh"],
     "all_reported": [{"file": "authorization.sh", "severity": "blocking", "summary": "s"}]},
    {"id": "R-API", "severity": "material", "files": ["api.sh"],
     "all_reported": [{"file": "api.sh", "severity": "material", "summary": "s"}]},
    {"id": "R-ERROR", "severity": "material", "files": ["storage.sh"],
     "all_reported": [{"file": "storage.sh", "severity": "material", "summary": "s"}]},
    {"id": "R-BOUNDARY", "files": ["pagination.sh"], "all_reported": all_reported,
     "severity": (max((f["severity"] for f in all_reported), default="none"))},
]
json.dump({"seeded": seeded, "clean": []}, open(path, "w"))
PY
}

# --- baseline: exactly one material finding against the override file,
# matching (as far as the contract can tell) the expected defect -> detected ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "pageSize zero accepted"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- exactly one material finding, worded differently, same file (the only
# "structured identity" this contract supports is the file match) -> credited ---
write_findings '[{"file": "pagination.sh", "severity": "blocking", "summary": "boundary check allows 0, spec requires 1..100"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- no finding against the override file at all -> missed ---
write_findings '[]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- only a non-material (suggestion) finding -> missed ---
write_findings '[{"file": "pagination.sh", "severity": "suggestion", "summary": "style nit"}]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- KNOWN LIMITATION, asserted explicitly rather than silently passing:
# a SINGLE material finding against the override file that is actually about
# an unrelated defect (not the seeded one) is STILL credited. This is the
# exact shape of the real incident (R-BOUNDARY's live rerun: one material
# finding, entirely about a different bug). The scorer cannot distinguish
# this from a correct detection without content judgment this remediation is
# explicitly not permitted to add (no LLM judge, no Reviewer prompt change).
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "leading-zero octal reinterpretation in bash arithmetic, unrelated to the zero-boundary defect"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- multiple material findings against the override file, one of which IS
# the expected defect: UNRESOLVABLE by file+severity alone -> fails closed
# (not credited), rather than the old "pick highest severity" guess ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "pageSize zero accepted"}, {"file": "pagination.sh", "severity": "blocking", "summary": "unrelated octal bug"}]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- multiple material findings against the override file, NEITHER of which
# is the expected defect: also fails closed, via the identical mechanism ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "unrelated bug A"}, {"file": "pagination.sh", "severity": "blocking", "summary": "unrelated bug B"}]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- backward compatibility: a findings.json without "all_reported"/"files"
# (the minimal shape reviewer-ground-truth-test.sh's synthetic fixtures use)
# falls back to trusting the top-level severity field directly, unchanged. ---
python3 - "$findings_path" <<'PY'
import json, sys
seeded = [{"id": cid, "severity": "material"} for cid in
          ["R-CONCURRENCY", "R-AUTH", "R-API", "R-BOUNDARY", "R-ERROR"]]
json.dump({"seeded": seeded, "clean": []}, open(sys.argv[1], "w"))
PY
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

printf 'PASS: reviewer scorer attribution\n'
