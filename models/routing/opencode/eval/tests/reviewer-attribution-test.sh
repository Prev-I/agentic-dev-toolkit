#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"

# Scorer attribution hardening (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
# section "Reviewer scorer attribution"). Traced root cause: the scorer credited
# a seeded case as "detected" whenever ANY material/blocking finding was
# reported against the case's override filename -- it never checked whether
# the finding's content was actually about the seeded defect. Confirmed real
# via a live R-BOUNDARY dispatch that was credited "material" for an entirely
# different, unrelated bug in the same file.
#
# This file tests the file+severity attribution mechanism as it applies to
# R-AUTH and R-CONCURRENCY specifically -- the two seeds with no diff-derived
# witness (pure-removal mutations; see reviewer-witness-attribution-test.sh's
# header for why). For R-API, R-BOUNDARY, and R-ERROR, which DO have a
# witness, single-wrong-finding attribution is now solved by witness-matched
# evidence -- see reviewer-witness-attribution-test.sh, not this file. Using
# R-AUTH as the varying example below keeps this file testing the
# file+severity mechanism in isolation, unaffected by witness matching.
#
# What IS mechanically fixable at the file+severity level, and is fixed
# here: when MULTIPLE material findings are reported against the same
# override file, the scorer previously picked the highest-severity one
# silently ("highest severity the reviewer reported against the case's
# override file" -- the adapter's own former normalization) with no signal
# that the case was ambiguous. The fix: 2+ material findings against the
# same override file is UNAMBIGUOUSLY unresolvable by this scorer and must
# fail closed (not detected), rather than guessing via severity rank.
#
# KNOWN, DOCUMENTED LIMITATION for R-AUTH/R-CONCURRENCY specifically: a
# SINGLE material finding against the override file that is actually about
# an unrelated (hallucinated or otherwise incorrect) defect is still
# credited -- there is no witness for these two, so file+severity is all
# this scorer has. This remains justified because fixture-integrity-test.sh
# mechanically proves each of these files carries exactly one known material
# defect and none of the other detector classes apply -- but it does not
# protect against a hallucinated finding, and that residual risk is not
# claimed to be closed.

fixture="$root/fixtures/reviewer-seeded-defects"
findings_path="$fixture/.attribution-test-findings.json"
trap 'rm -f "$findings_path"' EXIT

write_findings() {
  # $1 = json for the "seeded" R-AUTH entry's all_reported array
  python3 - "$findings_path" "$1" <<'PY'
import json, sys
path, all_reported_json = sys.argv[1:]
all_reported = json.loads(all_reported_json)
seeded = [
    {"id": "R-CONCURRENCY", "severity": "material", "files": ["counter.sh"],
     "all_reported": [{"file": "counter.sh", "severity": "material", "summary": "s"}]},
    {"id": "R-AUTH", "files": ["authorization.sh"], "all_reported": all_reported,
     "severity": (max((f["severity"] for f in all_reported), default="none"))},
    {"id": "R-API", "severity": "material", "files": ["api.sh"],
     "all_reported": [{"file": "api.sh", "severity": "material", "summary": "s", "evidence": '{"name"'}]},
    {"id": "R-ERROR", "severity": "material", "files": ["storage.sh"],
     "all_reported": [{"file": "storage.sh", "severity": "material", "summary": "s", "evidence": "|| printf '[]"}]},
    {"id": "R-BOUNDARY", "severity": "material", "files": ["pagination.sh"],
     "all_reported": [{"file": "pagination.sh", "severity": "material", "summary": "s", "evidence": "10#$1 >= 0"}]},
]
json.dump({"seeded": seeded, "clean": []}, open(path, "w"))
PY
}

# --- baseline: exactly one material finding against the override file,
# matching (as far as the contract can tell) the expected defect -> detected ---
write_findings '[{"file": "authorization.sh", "severity": "blocking", "summary": "callers not compared"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- exactly one material finding, worded differently, same file (the only
# "structured identity" this contract supports here is the file match) -> credited ---
write_findings '[{"file": "authorization.sh", "severity": "material", "summary": "any caller can read any owner resource"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- no finding against the override file at all -> missed ---
write_findings '[]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- only a non-material (suggestion) finding -> missed ---
write_findings '[{"file": "authorization.sh", "severity": "suggestion", "summary": "style nit"}]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- KNOWN LIMITATION, asserted explicitly rather than silently passing:
# a SINGLE material finding against the override file that is actually about
# an unrelated defect (not the seeded one) is STILL credited, for cases with
# no witness. The scorer cannot distinguish this from a correct detection
# without content judgment this remediation is explicitly not permitted to
# add (no LLM judge, no Reviewer prompt change) and no diff-derived witness
# is available for a pure-removal mutation like R-AUTH's.
write_findings '[{"file": "authorization.sh", "severity": "material", "summary": "unrelated concern, not about caller/owner comparison at all"}]'
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- multiple material findings against the override file, one of which IS
# the expected defect: UNRESOLVABLE by file+severity alone -> fails closed
# (not credited), rather than the old "pick highest severity" guess ---
write_findings '[{"file": "authorization.sh", "severity": "material", "summary": "callers not compared"}, {"file": "authorization.sh", "severity": "blocking", "summary": "unrelated concern"}]'
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$findings_path")"

# --- multiple material findings against the override file, NEITHER of which
# is the expected defect: also fails closed, via the identical mechanism ---
write_findings '[{"file": "authorization.sh", "severity": "material", "summary": "unrelated bug A"}, {"file": "authorization.sh", "severity": "blocking", "summary": "unrelated bug B"}]'
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
