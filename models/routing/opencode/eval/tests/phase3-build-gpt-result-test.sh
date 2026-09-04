#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build Opus-vs-Sol result
# (docs/decisions/2026-09-04-phase3-build-gpt-result.md): mechanically
# re-derives the adjudication from the raw per-arm attempt.json records on
# disk -- not from adjudication.json's own say-so -- mirroring
# phase3-build-ab-result-test.sh for the Sonnet experiment.

records="$root/records/phase3-build-gpt"
adjudication="$records/adjudication.json"
assert_file "$adjudication"

python3 -c '
import json

records_root = "'"$records"'"
adj = json.load(open("'"$adjudication"'"))

def load(rel):
    return json.load(open(records_root + "/" + rel))

feature_opus = load("build-feature/pair1-arm1-opus/attempt.json")
feature_sol = load("build-feature/pair1-arm2-sol/attempt.json")
bugfix_sol = load("build-bugfix/pair2-arm1-sol/attempt.json")
bugfix_opus = load("build-bugfix/pair2-arm2-opus/attempt.json")

# every dispatch must be a genuinely healthy, valid attempt -- classification
# OK regardless of oracle outcome (a failed oracle is real evidence, not an
# environment failure)
for a in (feature_opus, feature_sol, bugfix_sol, bugfix_opus):
    assert a["dispatch_classification"] == "OK", a["label"] + " must be a valid, healthy dispatch"
    assert a["dispatch_healthy"] is True, a["label"] + " must be dispatch_healthy"
    assert a["dispatch"]["retry_count"] == 0
    assert a["dispatch"]["failure_class"] is None, \
        a["label"] + " must have no failure_class -- a real failure_class would mean INVALID_ENVIRONMENT, not VALID_CONTROLLER_FAILURE"
    assert a["dispatch"]["provider_error_text"] is None, \
        a["label"] + " must have no provider error -- confirms the dispatch itself was healthy"

# the specific, real outcome of each arm, re-read from raw evidence
assert feature_opus["oracle_passed"] is True
assert feature_opus["regression_passed"] is True
assert feature_sol["oracle_passed"] is False, "feature_sol is expected to have FAILED the oracle (real VALID_CONTROLLER_FAILURE)"
assert feature_sol["regression_passed"] is True
assert bugfix_sol["oracle_passed"] is True
assert bugfix_sol["regression_passed"] is True
assert bugfix_opus["oracle_passed"] is True
assert bugfix_opus["regression_passed"] is True

# no replacement pairs were needed -- exactly 4 dispatches, matching the
# frozen initial sample, no more
assert adj["budget"]["replacement_pairs_used"] == 0
assert len(adj["replacement_pairs"]) == 0

# --- re-derive the final decision from the frozen adoption rule, independent
# of adjudication.json'"'"'s own claimed decision ---
sol_regressed = (feature_sol["oracle_passed"] != feature_opus["oracle_passed"] and not feature_sol["oracle_passed"]) or \
                (bugfix_sol["oracle_passed"] != bugfix_opus["oracle_passed"] and not bugfix_sol["oracle_passed"])
assert sol_regressed, "re-derivation expected a genuine Sol regression on criterion 1"
decision = "KEEP_OPUS" if sol_regressed else "UNDETERMINED"
assert decision == "KEEP_OPUS"
assert adj["final_decision"] == decision, "adjudication.json final_decision does not match re-derivation"
assert adj["functional_adjudication"]["adjudication_stops_here"] is True, \
    "a functional regression must stop adjudication before any operational criterion is consulted"

# --- budget: consumed sum must match the sum of the 4 real dispatch costs,
# and must not exceed the approved cap ---
total_credits = sum(
    a["dispatch"]["derived_credits"]
    for a in (feature_opus, feature_sol, bugfix_sol, bugfix_opus)
)
assert abs(adj["budget"]["consumed_credits"] - total_credits) < 1e-6
assert adj["budget"]["consumed_credits"] <= adj["budget"]["approved_cap_credits"]
assert adj["budget"]["approved_cap_credits"] == 264

# --- the manifest agrees with the result, not just the standalone doc ---
manifest = json.load(open("'"$root"'/manifests/phase3-build-gpt-preflight.json"))
assert manifest["status"] == "EXECUTED"
assert manifest["final_decision"] == adj["final_decision"]
assert abs(manifest["credits_consumed"] - adj["budget"]["consumed_credits"]) < 1e-6
'

# --- production routing files were never touched by this experiment ---
# 'profiles/' (not just the one named snapshot file) so any profile, present
# or future, is covered -- not only the canonical restored baseline.
git -C "$root/.." diff --name-only main -- \
  'profiles/' 'opencode.jsonc' | \
  grep -q . && fail "experiment touched a production routing file" || true

printf 'PASS: Phase-3 Build Opus-vs-Sol result is independently re-derivable from raw evidence\n'
