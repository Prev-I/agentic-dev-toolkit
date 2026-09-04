#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-R scope amendment (docs/decisions/2026-09-04-phase-r-scope-amendment.md):
# proves the two statements the amendment depends on simultaneously being
# true, mechanically, so neither can silently drift out of sync with the
# other in a future change:
#
#   1. Reviewer 5/5 + clean-zero remains the Reviewer QUALITY-benchmark
#      threshold -- UNCHANGED.
#   2. That benchmark is NOT a Phase-R RESTORATION hard gate -- it is
#      reclassified to Phase-3.
#
# This is deliberately the smallest possible test for the distinction: it
# does not re-implement gate logic, re-score any fixture, or touch the
# scorer/dispatch code. It reads the two manifests that declare each claim
# and asserts they agree with each other and with the fixture's own oracle.

fixture="$root/fixtures/reviewer-seeded-defects"
gate_set="$root/manifests/phase-r-gate-set.json"

assert_file "$fixture/oracle.json"
assert_file "$gate_set"

# --- statement 1: the quality-benchmark threshold is unchanged ---
python3 -c '
import json
oracle = json.load(open("'"$fixture"'/oracle.json"))
assert oracle["required_seeded_detections"] == 5, oracle["required_seeded_detections"]
assert oracle["allowed_clean_material_findings"] == 0, oracle["allowed_clean_material_findings"]
assert set(oracle["expected_ids"]) == {"R-API", "R-AUTH", "R-BOUNDARY", "R-CONCURRENCY", "R-ERROR"}
'

# --- statement 2: that same benchmark is declared NOT a Phase-R hard gate ---
python3 -c '
import json
gates = json.load(open("'"$gate_set"'"))
hard_gate_names = {g["gate"] for g in gates["hard_gates"]}
assert "reviewer_seeded_defects_quality_benchmark" not in hard_gate_names, \
    "the quality benchmark must not appear in hard_gates"
assert "reviewer_operational_integration" in hard_gate_names, \
    "operational integration must be a hard gate"

not_hard = {b["benchmark"]: b for b in gates["not_a_hard_gate"]}
assert "reviewer_seeded_defects_quality_benchmark" in not_hard
b = not_hard["reviewer_seeded_defects_quality_benchmark"]
assert b["classification"] == "phase_3_targeted_quality_evaluation"
assert b["reclassified_from"] == "phase_r_restoration_hard_gate"
assert b["threshold_unchanged"] is True
assert b["historical_runs"] == "inadmissible_for_quality_adjudication"
assert b["reference"] == "eval/fixtures/reviewer-seeded-defects/oracle.json"
'

# --- the operational gate requires no quantitative defect-recall evidence ---
python3 -c '
import json
gates = json.load(open("'"$gate_set"'"))
op = next(g for g in gates["hard_gates"] if g["gate"] == "reviewer_operational_integration")
required = set(op["required_properties"])
forbidden = {"defect_recall", "seeded_detection_count", "clean_material_findings"}
assert not (required & forbidden), f"operational gate must not require quality metrics: {required & forbidden}"
expected = {"model_resolves", "variant_correct", "routing_correct", "permissions_read_only",
            "successful_execution", "adapter_output_path_traversal", "no_security_regression"}
assert required == expected, required
'

# --- all seven amended Phase-R hard gates are declared, each with evidence ---
python3 -c '
import json
gates = json.load(open("'"$gate_set"'"))
names = [g["gate"] for g in gates["hard_gates"]]
expected = ["routing_resolution", "security_permissions", "breakglass_boundary",
            "build_operational_restoration", "explore_operational_gate",
            "compaction_invariant_preservation", "reviewer_operational_integration"]
assert names == expected, names
for g in gates["hard_gates"]:
    assert g.get("evidence"), g["gate"] + " has no evidence reference"
'

printf 'PASS: Phase-R scope amendment (quality threshold unchanged, not a restoration gate)\n'
