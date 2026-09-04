#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build A/B result (docs/decisions/2026-09-04-phase3-build-ab-result.md):
# mechanically re-derives the adjudication from the raw per-arm attempt.json
# records on disk -- not from the adjudication.json's own say-so -- so a
# hand-edited or stale result document cannot silently pass review.

records="$root/records/phase3-build-ab"
adjudication="$records/adjudication.json"
assert_file "$adjudication"

python3 -c '
import json

records_root = "'"$records"'"
adj = json.load(open("'"$adjudication"'"))

def load(rel):
    return json.load(open(records_root + "/" + rel))

# --- recompute every wall-clock/credit/pass value from the raw attempt.json
# records, independent of what adjudication.json claims ---
feature_opus = load("build-feature/pair1-arm1-opus/attempt.json")
feature_sonnet = load("build-feature/pair1-arm2-sonnet/attempt.json")
bugfix_sonnet = load("build-bugfix/pair2-arm1-sonnet/attempt.json")
bugfix_opus = load("build-bugfix/pair2-arm2-opus/attempt.json")

for a in (feature_opus, feature_sonnet, bugfix_sonnet, bugfix_opus):
    assert a["dispatch_classification"] == "OK", a["label"] + " must be a valid, healthy dispatch"
    assert a["oracle_passed"] is True, a["label"] + " oracle must have passed"
    assert a["regression_passed"] is True, a["label"] + " regression must have passed"
    assert a["dispatch"]["retry_count"] == 0

# no replacement pairs were needed -- exactly 4 dispatches, matching the
# frozen initial sample, no more
assert adj["budget"]["replacement_pairs_used"] == 0
assert len(adj["replacement_pairs"]) == 0

def rel_range(a, b):
    spread = max(a, b) - min(a, b)
    median = (a + b) / 2
    return spread / median

opus_feature_wc = feature_opus["dispatch"]["wall_clock_ms"]
sonnet_feature_wc = feature_sonnet["dispatch"]["wall_clock_ms"]
sonnet_bugfix_wc = bugfix_sonnet["dispatch"]["wall_clock_ms"]
opus_bugfix_wc = bugfix_opus["dispatch"]["wall_clock_ms"]

rf = rel_range(opus_feature_wc, sonnet_feature_wc)
rb = rel_range(opus_bugfix_wc, sonnet_bugfix_wc)

# adjudication.json'"'"'s own recorded relative ranges must match the recomputation
assert abs(adj["pairs"][0]["wall_clock_relative_range"] - rf) < 1e-9
assert abs(adj["pairs"][1]["wall_clock_relative_range"] - rb) < 1e-9

THRESHOLD = 0.378885
feature_clears = rf >= THRESHOLD and sonnet_feature_wc < opus_feature_wc
bugfix_clears = rb >= THRESHOLD and sonnet_bugfix_wc < opus_bugfix_wc

assert adj["pairs"][0]["wall_clock_clears_threshold"] == feature_clears
assert adj["pairs"][1]["wall_clock_clears_threshold"] == bugfix_clears

# --- re-derive the final decision from the frozen adoption rule, independent
# of adjudication.json'"'"'s own claimed decision ---
functional_tie = True  # all 4 attempts: oracle_passed, regression_passed, 0 retries -- verified above
if functional_tie:
    decision = "ADOPT_SONNET" if (feature_clears and bugfix_clears) else "KEEP_OPUS"
else:
    decision = "UNDETERMINED"

assert decision == "KEEP_OPUS", "re-derivation disagrees with the frozen rule: expected KEEP_OPUS"
assert adj["final_decision"] == decision, "adjudication.json final_decision does not match re-derivation"

# --- budget: consumed sum must match the sum of the 4 real dispatch costs,
# and must not exceed the approved cap ---
total_credits = sum(
    a["dispatch"]["derived_credits"]
    for a in (feature_opus, feature_sonnet, bugfix_sonnet, bugfix_opus)
)
assert abs(adj["budget"]["consumed_credits"] - total_credits) < 1e-6
assert adj["budget"]["consumed_credits"] <= adj["budget"]["approved_cap_credits"]
assert adj["budget"]["approved_cap_credits"] == 158

# --- the manifest agrees with the result, not just the standalone doc ---
manifest = json.load(open("'"$root"'/manifests/phase3-build-ab-preflight.json"))
assert manifest["status"] == "EXECUTED"
assert manifest["final_decision"] == adj["final_decision"]
assert abs(manifest["credits_consumed"] - adj["budget"]["consumed_credits"]) < 1e-6
'

# --- production routing files were never touched by this experiment ---
git -C "$root/.." diff --name-only main -- \
  'models/routing/opencode/profiles/v1-restored-2026-09.jsonc' \
  'models/routing/opencode/opencode.jsonc' 2>/dev/null | \
  grep -q . && fail "experiment touched a production routing file" || true

printf 'PASS: Phase-3 Build A/B result is independently re-derivable from raw evidence\n'
