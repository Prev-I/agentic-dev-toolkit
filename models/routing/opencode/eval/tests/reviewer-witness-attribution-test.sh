#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"

# Witness-based deterministic attribution (docs/evidence/
# 2026-09-04-reviewer-fixture-integrity-remediation.md, part 2, "Revisit
# scorer attribution from first principles").
#
# Prior state: reviewer_structured_gate credited a case whenever exactly one
# material finding was reported against its override file, with NO check
# that the finding's content was actually about the seeded defect (fixed
# for the 2+-finding case in 3079235; the single-wrong-finding case was left
# explicitly open -- this is that follow-up).
#
# Investigated whether deterministic (non-LLM, non-fuzzy, non-seed-leaking)
# single-finding attribution is achievable for the current Reviewer output
# contract (file, severity, summary). Answer: PARTIALLY, and the split is
# principled, not arbitrary --
#
# R-API, R-BOUNDARY, R-ERROR are ADDITION/SUBSTITUTION mutations: the
# vulnerable version contains a literal token absent from the safe version
# (R-API: `{"name"` vs `{"displayName"`; R-BOUNDARY: `10#$1 >= 0` vs
# `>= 1`; R-ERROR: `2>/dev/null` addition). A mechanically-computed,
# diff-derived "witness" substring exists for each (see each case's
# ground-truth.json), verified present-in-override/absent-from-clean by
# this suite itself. This makes deterministic, exact-substring evidence
# matching possible WITHOUT an LLM judge and WITHOUT leaking the seed ID:
# the eval-only dispatch contract (run-reviewer-gate.sh's reviewer_request,
# NOT the production Reviewer prompt) now asks for an "evidence" field --
# a verbatim quoted snippet -- and the scorer checks whether it contains
# the case's own witness substring.
#
# R-AUTH and R-CONCURRENCY are pure REMOVALS (a safety check deleted
# outright). Verified directly: R-AUTH's override is not derivable as an
# addition of any new literal token -- it is a strict character-range
# deletion from clean, nothing new appears. R-CONCURRENCY's override does
# introduce one incidental new token ("local n", an artifact of how the
# de-synchronized version happens to be written) but it is NOT the
# semantically meaningful evidence of the mutation (the meaningful fact is
# the ABSENCE of flock/locking, not the presence of "local n") -- treating
# it as a witness would be an arbitrary, fragile hack a reviewer's genuine
# evidence would have no natural reason to quote, not a real anchor.
# NEITHER CASE HAS A WITNESS. This is deliberate and documented, not an
# oversight: these two retain the file+severity attribution, which is
# NOW justified specifically because fixture-integrity-test.sh mechanically
# proves each of these files carries EXACTLY one known material defect and
# none of the other 8 detector classes apply to authorization.sh/counter.sh
# at all -- there is nothing else in that file to be materially wrong
# about, among KNOWN defect classes. This does not protect against a model
# hallucinating an unrelated concern; that residual risk is acknowledged
# explicitly, not hidden.

fixture="$root/fixtures/reviewer-seeded-defects"

# --- witnesses are genuinely diff-derived, not hand-wavy: present in the
# override, absent from clean, for exactly the three witness-bearing cases ---
for case_id in R-API R-BOUNDARY R-ERROR; do
  gt="$fixture/cases/$case_id/ground-truth.json"
  witness=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["witness"])' "$gt")
  override_rel=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["overrides"][0])' "$gt")
  clean_content=$(<"$fixture/clean/$override_rel")
  override_content=$(<"$fixture/cases/$case_id/$override_rel")
  assert_contains "$override_content" "$witness"
  if [[ "$clean_content" == *"$witness"* ]]; then
    fail "$case_id's witness '$witness' is present in clean/$override_rel -- not diff-derived, does not discriminate"
  fi
done

# --- R-AUTH and R-CONCURRENCY deliberately have no witness field ---
for case_id in R-AUTH R-CONCURRENCY; do
  gt="$fixture/cases/$case_id/ground-truth.json"
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))["witness"]' "$gt" 2>/dev/null; then
    fail "$case_id has a witness field -- expected none (pure-removal mutation, no addable literal token)"
  fi
done

write_findings() {
  # $1 = json for the "seeded" R-BOUNDARY entry's all_reported array
  python3 - "$root/fixtures/reviewer-seeded-defects/.witness-test-findings.json" "$1" <<'PY'
import json, sys
path, all_reported_json = sys.argv[1:]
all_reported = json.loads(all_reported_json)
seeded = [
    {"id": "R-API", "files": ["api.sh"], "all_reported": [], "severity": "none"},
    {"id": "R-AUTH", "files": ["authorization.sh"], "all_reported": [{"file": "authorization.sh", "severity": "blocking", "summary": "s"}], "severity": "blocking"},
    {"id": "R-BOUNDARY", "files": ["pagination.sh"], "all_reported": all_reported,
     "severity": (max((f["severity"] for f in all_reported), default="none"))},
    {"id": "R-CONCURRENCY", "files": ["counter.sh"], "all_reported": [{"file": "counter.sh", "severity": "material", "summary": "s"}], "severity": "material"},
    {"id": "R-ERROR", "files": ["storage.sh"], "all_reported": [], "severity": "none"},
]
json.dump({"seeded": seeded, "clean": []}, open(path, "w"))
PY
}

findings_path="$fixture/.witness-test-findings.json"
trap 'rm -f "$findings_path"' EXIT

attr() {
  reviewer_structured_attribution "$fixture/oracle.json" "$findings_path" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["R-BOUNDARY"])'
}

# --- correct finding: evidence contains the witness -> credited ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "pageSize 0 accepted", "evidence": "10#$1 >= 0"}]'
assert_eq detected "$(attr)"

# --- unrelated material finding in ANOTHER file -> not credited (missed) ---
write_findings '[{"file": "storage.sh", "severity": "material", "summary": "unrelated", "evidence": "irrelevant"}]'
assert_eq missed "$(attr)"

# --- unrelated material finding in the SAME file, evidence does not
# contain the witness -> not credited (missed, not detected) ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "leading zeros are read as octal", "evidence": "[[ \"$1\" =~ ^[0-9]+$ ]]"}]'
assert_eq missed "$(attr)"

# --- correct file, correct severity, but evidence describes different
# behavior (no witness overlap) -> not credited ---
write_findings '[{"file": "pagination.sh", "severity": "blocking", "summary": "octal reinterpretation", "evidence": "(( ${#1} <= 18 ))"}]'
assert_eq missed "$(attr)"

# --- no finding at all -> missed ---
write_findings '[]'
assert_eq missed "$(attr)"

# --- multiple findings, only one correct (evidence contains witness) ->
# credited exactly once, i.e. "detected" not "ambiguous" ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "octal", "evidence": "^[0-9]+$"}, {"file": "pagination.sh", "severity": "material", "summary": "boundary", "evidence": "10#$1 >= 0"}]'
assert_eq detected "$(attr)"

# --- multiple material findings, NONE correct -> still missed, not ambiguous ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "octal", "evidence": "^[0-9]+$"}, {"file": "pagination.sh", "severity": "blocking", "summary": "length guard", "evidence": "<= 18"}]'
assert_eq missed "$(attr)"

# --- THE EXACT HISTORICAL REGRESSION (Section 10's explicit requirement):
# reconstructing the real R-BOUNDARY dispatch's finding as closely as
# possible from eval/records/phase-r/reviewer/R-BOUNDARY/dispatch/response.txt --
# summary about leading-zero octal reinterpretation, evidence quoting the
# regex/arithmetic guard, zero mention of the >= 0 boundary. Must NOT be
# detected. ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "validate_page_size accepts out-of-range values because (( )) reinterprets digit strings, so leading-zero inputs are read as octal (0144 passes as 100) and values above INTMAX wrap around", "evidence": "[[ \"$1\" =~ ^[0-9]+$ ]] || return 1"}]'
assert_eq missed "$(attr)"

# --- no evidence field at all (model did not comply with the extended
# eval-only contract) -> fails closed, not credited ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "pageSize 0 accepted"}]'
assert_eq missed "$(attr)"

# --- known, documented, ACCEPTED residual limitation: a model that quotes
# the ENTIRE line as evidence defeats the discrimination, because the
# witness-bearing sandbox's own full line legitimately contains the
# witness substring too. Asserted explicitly, not hidden. ---
write_findings '[{"file": "pagination.sh", "severity": "material", "summary": "octal reinterpretation", "evidence": "validate_page_size() { [[ \"$1\" =~ ^[0-9]+$ ]] || return 1; (( ${#1} <= 18 )) || return 1; (( 10#$1 >= 0 && 10#$1 <= 100 )); }"}]'
assert_eq detected "$(attr)"

printf 'PASS: witness-based scorer attribution\n'
