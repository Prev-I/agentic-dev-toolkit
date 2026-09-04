#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build A/B preflight (docs/decisions/2026-09-04-phase3-build-ab-preflight.md):
# mechanically proves the frozen manifest is internally consistent and
# genuinely grounded in the repository -- not merely well-worded prose.
# In particular this guards against the exact inconsistency an earlier
# Reviewer remediation had to correct: a proposed tranche below its own
# stated conservative ceiling.

manifest="$root/manifests/phase3-build-ab-preflight.json"
assert_file "$manifest"

python3 -c '
import json
m = json.load(open("'"$manifest"'"))

assert m["status"] == "EXECUTED"
assert m["final_decision"] == "KEEP_OPUS"
assert m["additional_live_spend_this_task"] == 0
assert m["no_weighted_aggregate_score"] is True
assert m["tie_or_inconclusive_policy"] == "KEEP_OPUS"

# approval amendment: budget is approved at the conservative ceiling,
# not a separately invented number
b0 = m["proposed_phase3_build_ab_budget"]
assert b0["status"] == "APPROVED"
assert b0["approved_cap_credits"] == 158
assert b0["approved_cap_credits"] == b0["conservative_ceiling_credits"]

# final adoption rule: frozen adjudication policy is present and exact
far = m["final_adoption_rule"]
assert far["functional_regression"]["decision"] == "KEEP_OPUS"
assert far["functional_improvement"]["decision"] == "ADOPT_SONNET"
assert far["functional_tie"]["required_threshold_relative_range"] == 0.378885
assert far["functional_tie"]["required"]["build-feature"]
assert far["functional_tie"]["required"]["build-bugfix"]
assert far["anything_else"]["decision"] == "KEEP_OPUS"
assert far["cost"] == "observational only -- cannot trigger adoption under any branch of this rule"
assert m["incumbent"] == {"model": "github-copilot/claude-opus-5", "variant": "high"}
assert m["challenger"] == {"model": "github-copilot/claude-sonnet-5", "variant": "high"}
assert m["canonical_starting_baseline"] == "profiles/v1-restored-2026-09.jsonc"

# excluded fixture matches its own committed metadata
assert m["excluded_from_selection"] == ["build-restoration-gate"]

# initial sample math is self-consistent
s = m["initial_sample"]
assert s["pairs"] == 2
assert s["opus_dispatches"] == 2
assert s["sonnet_dispatches"] == 2
assert s["total_dispatches"] == s["opus_dispatches"] + s["sonnet_dispatches"] == 4

# historical budgets preserved verbatim, not touched
hb = m["historical_budgets"]
assert hb["evaluation"]["approved"] == 100
assert hb["evaluation"]["observed"] == 289.012037
assert hb["evaluation"]["status"] == "BREACHED"
assert hb["recovery"]["approved"] == 250
assert hb["recovery"]["observed"] == 349.944275
assert hb["recovery"]["status"] == "BREACHED"

# THE consistency check: the proposed tranche must cover its own stated
# worst case -- ceiling must exceed the central estimate.
b = m["proposed_phase3_build_ab_budget"]
assert b["conservative_ceiling_credits"] > b["central_estimate_credits"], \
    "ceiling must exceed the central estimate"

d = b["derivation"]
opus = d["opus_cost_per_run"]
sonnet = d["sonnet_cost_per_run"]
assert opus["min"] <= opus["mean"] <= opus["max"]

# ceiling must be >= (4 dispatches at the Opus historical max, i.e. no
# assumed Sonnet savings) + a full replacement pair at that same ceiling --
# the proposal explicit says it assumes zero Sonnet savings for the
# ceiling; verify the arithmetic actually reflects that, not just prose.
no_savings_floor = 4 * opus["max"]
replacement_floor = 2 * opus["max"]
required_floor = no_savings_floor + replacement_floor
msg = "ceiling too low for 4 dispatches + 1 replacement pair at Opus ceiling"
assert b["conservative_ceiling_credits"] >= required_floor, msg

# organizational guardrail recorded as a distinct, separate control
assert m["organizational_guardrail_credits_per_billing_cycle"] == 7600
assert m["organizational_guardrail_is_separate_control"] is True
'

# --- the initial workloads must be real, dispatchable fixtures, not just
# referenced by name in the manifest ---
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

# --- the conditional workload is explicitly marked not-ready, and
# genuinely has no fixture content yet (so the manifest cannot silently
# drift out of sync with reality) ---
python3 -c '
import json, os
m = json.load(open("'"$manifest"'"))
c = m["conditional_workload"]
assert c["id"] == "build-refactor"
assert c["fixture_ready"] is False
d = "'"$root"'/fixtures/build-workloads/" + c["id"]
assert not os.path.isfile(os.path.join(d, "task.md")), \
    "build-refactor now has content -- update fixture_ready and the manifest"
'

# --- build-restoration-gate really is excluded by its OWN committed
# metadata, not merely by this manifest'"'"'s say-so ---
python3 -c '
import json
gate = json.load(open("'"$root"'/fixtures/build-workloads/build-restoration-gate/fixture.json"))
assert gate.get("excluded_from_phase_3_selection") is True
'

printf 'PASS: Phase-3 Build A/B preflight manifest is internally consistent\n'
