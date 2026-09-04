#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build Opus-vs-Sol preflight
# (docs/decisions/2026-09-04-phase3-build-gpt-preflight.md): mechanically
# proves the frozen manifest is internally consistent and genuinely grounded
# in the repository -- not merely well-worded prose. Mirrors
# phase3-build-ab-preflight-test.sh for the Sonnet experiment.

manifest="$root/manifests/phase3-build-gpt-preflight.json"
assert_file "$manifest"

python3 -c '
import json
m = json.load(open("'"$manifest"'"))

assert m["status"] == "APPROVED"
assert m["additional_live_spend_this_task"] == 0
assert m["no_weighted_aggregate_score"] is True
assert m["incumbent"] == {"model": "github-copilot/claude-opus-5", "variant": "high"}
assert m["challenger"] == {"model": "github-copilot/gpt-5.6-sol", "variant": "high"}
assert m["canonical_starting_baseline"] == "profiles/v1-restored-2026-09.jsonc"

# current production routing recorded matches what this preflight assumes
cpr = m["current_production_routing"]
assert cpr["build"] == {"model": "github-copilot/claude-opus-5", "variant": "high"}
assert cpr["reviewer"] == {"model": "github-copilot/gpt-5.6-sol", "variant": "high"}

# excluded fixture matches its own committed metadata
assert m["excluded_from_selection"] == ["build-restoration-gate"]
assert m["no_new_fixtures"] is True

# initial sample math is self-consistent
s = m["initial_sample"]
assert s["pairs"] == 2
assert s["opus_dispatches"] == 2
assert s["sol_dispatches"] == 2
assert s["total_dispatches"] == s["opus_dispatches"] + s["sol_dispatches"] == 4

# final adoption rule: frozen adjudication policy is present and exact,
# same threshold as the Opus-vs-Sonnet experiment
far = m["final_adoption_rule"]
assert far["functional_regression"]["decision"] == "KEEP_OPUS"
assert far["functional_improvement"]["decision"] == "SOL_WINS_BUILD_EXPERIMENT"
assert far["functional_tie"]["required_threshold_relative_range"] == 0.378885
assert far["functional_tie"]["required"]["build-feature"]
assert far["functional_tie"]["required"]["build-bugfix"]
assert far["anything_else"]["decision"] == "KEEP_OPUS"
assert far["cost"] == "observational only -- cannot trigger adoption under any branch of this rule"
assert far["functional_tie"]["aggregation"].startswith("none"), \
    "wall-clock adjudication must not be averaged across workloads"

# activation policy: a Sol win never silently changes production routing
ap = m["activation_policy"]
assert ap["gpt_loses_ties_or_inconclusive"]["decision"] == "KEEP_OPUS"
gw = ap["gpt_wins"]
assert gw["decision"] == "SOL_WINS_BUILD_EXPERIMENT"
assert gw["record"]["preferred_build"] == "SOL_HIGH"
assert gw["record"]["status"] == "PENDING_REVIEWER_SEPARATION_DECISION"
assert "remains UNCHANGED" in gw["action"] or "remains unchanged" in gw["action"].lower()

# historical budgets preserved verbatim, not touched; the immediately
# preceding Phase-3 Build budget is recorded closed, not reused
hb = m["historical_budgets"]
assert hb["evaluation"]["approved"] == 100
assert hb["evaluation"]["observed"] == 289.012037
assert hb["evaluation"]["status"] == "BREACHED"
assert hb["recovery"]["approved"] == 250
assert hb["recovery"]["observed"] == 349.944275
assert hb["recovery"]["status"] == "BREACHED"
prev = hb["phase3_build_opus_vs_sonnet"]
assert prev["approved_cap"] == 158
assert prev["consumed"] == 76.83485
assert prev["status"] == "COMPLETE_CLOSED"

# THE consistency check: the proposed tranche must cover its own stated
# worst case -- ceiling must exceed the central estimate, and must cover
# 4 dispatches at ceiling rates plus one full replacement pair at ceiling
# rates, with no slack fudge.
b = m["proposed_phase3_build_gpt_budget"]
assert b["status"] == "APPROVED"
assert b["approved_cap_credits"] == 264
assert b["approved_cap_credits"] == b["conservative_ceiling_credits"]
assert b["conservative_ceiling_credits"] > b["central_estimate_credits"], \
    "ceiling must exceed the central estimate"

d = b["derivation"]
opus = d["opus_cost_per_run"]
sol = d["sol_cost_per_run"]
assert opus["build_feature"] == 28.62365
assert opus["build_bugfix"] == 26.9589
assert abs(opus["central_2_runs"] - (opus["build_feature"] + opus["build_bugfix"])) < 1e-9
assert opus["ceiling_per_run"] == max(opus["build_feature"], opus["build_bugfix"])

observed = sol["observed_reviewer_dispatch_credits"]
assert len(observed) == 6
assert abs(sol["mean"] - sum(observed) / len(observed)) < 1e-6
assert abs(sol["min"] - min(observed)) < 1e-6
assert abs(sol["max"] - max(observed)) < 1e-6
assert abs(sol["ceiling_per_run_estimate"] - max(observed)) < 1e-6

# central estimate arithmetic: must actually equal opus + sol central rates,
# not a hand-typed figure that drifted from its own inputs
assert abs(b["central_estimate_credits"] - (opus["central_2_runs"] + sol["central_2_runs"])) < 0.01

# role-transfer margin: the ceiling must use the MARGINED sol per-run rate,
# not the raw cross-workload max with no headroom (independent review found
# the raw max left ~0% margin against a same-turn-depth Sol Build projection)
margin = sol["role_transfer_margin"]
assert margin["factor"] > 1.0
margined_sol_ceiling = sol["ceiling_per_run_estimate"] * margin["factor"]
assert abs(margin["ceiling_per_run_with_margin"] - margined_sol_ceiling) < 1e-3

no_savings_floor = 2 * opus["ceiling_per_run"] + 2 * margin["ceiling_per_run_with_margin"]
replacement_floor = opus["ceiling_per_run"] + margin["ceiling_per_run_with_margin"]
required_floor = no_savings_floor + replacement_floor
assert b["conservative_ceiling_credits"] >= required_floor, \
    "ceiling too low for 4 dispatches + 1 replacement pair at margined ceiling rates"

# organizational guardrail recorded as a distinct, separate control
assert m["organizational_guardrail_credits_per_billing_cycle"] == 7600
assert m["organizational_guardrail_is_separate_control"] is True

# cost-accounting mechanism must point at the current, corrected
# implementation, not the historical undercounting one
assert "dispatch-fixture.sh" in b["cost_accounting_mechanism"]
assert "505d35a" in b["cost_accounting_mechanism"]
'

# --- the initial workloads must be real, dispatchable fixtures, reused
# unchanged from the Opus-vs-Sonnet experiment -- not new, not modified ---
python3 -c '
import json, os
m = json.load(open("'"$manifest"'"))
fixtures_root = "'"$root"'/fixtures/build-workloads"
for w in m["initial_workloads"]:
    d = os.path.join(fixtures_root, w["id"])
    for required in ("task.md", "oracle.sh", "snapshot/README.md",
                      "snapshot/tests/acceptance.sh", "snapshot/tests/regression.sh"):
        assert os.path.isfile(os.path.join(d, required)), w["id"] + "/" + required + " missing"
'

# --- the Sol cost evidence cited really exists on disk with the exact
# credits claimed -- not merely asserted in the manifest ---
python3 -c '
import json
m = json.load(open("'"$manifest"'"))
sol = m["proposed_phase3_build_gpt_budget"]["derivation"]["sol_cost_per_run"]
records_root = "'"$root"'/records/phase-r/reviewer"
outcome = json.load(open(records_root + "/outcome.json"))
target = outcome["target"]
assert target == {"role": "reviewer", "model": "github-copilot/gpt-5.6-sol", "variant": "high"}, \
    "the cited Reviewer dispatches are not confirmed as github-copilot/gpt-5.6-sol high"
cases = ["R-API", "R-AUTH", "R-BOUNDARY", "R-CONCURRENCY", "R-ERROR", "clean"]
observed = []
for case in cases:
    d = json.load(open(records_root + "/" + case + "/dispatch/dispatch.json"))
    assert d["dispatch_target"] == "agent:reviewer"
    observed.append(d["derived_credits"])
observed.sort()
claimed = sorted(sol["observed_reviewer_dispatch_credits"])
for a, b in zip(observed, claimed):
    assert abs(a - b) < 1e-9, "manifest Sol cost evidence does not match the raw dispatch.json records"
'

# --- the Opus cost evidence cited really exists on disk, from the actually
# executed Opus-vs-Sonnet experiment -- not a fresh invented figure ---
python3 -c '
import json
m = json.load(open("'"$manifest"'"))
opus = m["proposed_phase3_build_gpt_budget"]["derivation"]["opus_cost_per_run"]
records_root = "'"$root"'/records/phase3-build-ab"
feature = json.load(open(records_root + "/build-feature/pair1-arm1-opus/attempt.json"))
bugfix = json.load(open(records_root + "/build-bugfix/pair2-arm2-opus/attempt.json"))
assert feature["dispatch"]["dispatch_target"] == "github-copilot/claude-opus-5"
assert bugfix["dispatch"]["dispatch_target"] == "github-copilot/claude-opus-5"
assert abs(feature["dispatch"]["derived_credits"] - opus["build_feature"]) < 1e-9
assert abs(bugfix["dispatch"]["derived_credits"] - opus["build_bugfix"]) < 1e-9
'

printf 'PASS: Phase-3 Build Opus-vs-Sol preflight manifest is internally consistent\n'
