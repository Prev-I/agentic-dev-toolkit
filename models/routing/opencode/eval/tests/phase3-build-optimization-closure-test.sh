#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build optimization cycle closure
# (docs/decisions/2026-09-04-phase3-build-optimization-closure.md):
# mechanically proves the closure's factual claims against the authoritative
# per-experiment records and ledgers -- not the closure document's own say-so.

doc="$root/../docs/decisions/2026-09-04-phase3-build-optimization-closure.md"
assert_file "$doc"

# --- both Build experiments really concluded KEEP_OPUS, from their own
# adjudication manifests, not merely re-asserted here ---
python3 -c '
import json
sonnet = json.load(open("'"$root"'/records/phase3-build-ab/adjudication.json"))
sol = json.load(open("'"$root"'/records/phase3-build-gpt/adjudication.json"))
assert sonnet["final_decision"] == "KEEP_OPUS"
assert sol["final_decision"] == "KEEP_OPUS"

sonnet_manifest = json.load(open("'"$root"'/manifests/phase3-build-ab-preflight.json"))
sol_manifest = json.load(open("'"$root"'/manifests/phase3-build-gpt-preflight.json"))
assert sonnet_manifest["status"] == "EXECUTED"
assert sonnet_manifest["final_decision"] == "KEEP_OPUS"
assert sol_manifest["status"] == "EXECUTED"
assert sol_manifest["final_decision"] == "KEEP_OPUS"
'

# --- budget figures the closure cites must match the authoritative ledgers
# exactly, not a rebased or reinterpreted number ---
python3 -c '
import json

phase_r = json.load(open("'"$root"'/records/phase-r/budget-ledger.json"))["i1_correction"]
assert phase_r["corrected_evaluation_total_credits"] == 289.012037
assert phase_r["evaluation_cap"] == 100
assert phase_r["corrected_recovery_total_credits"] == 349.944275
assert phase_r["recovery_cap"] == 250

sonnet_ledger = json.load(open("'"$root"'/records/phase3-build-ab/ledger.json"))
assert sonnet_ledger["caps"]["phase3_build_ab"] == 158
sonnet_spent = sum(e["credits"] for e in sonnet_ledger["entries"])
assert abs(sonnet_spent - 76.83485) < 1e-6

sol_ledger = json.load(open("'"$root"'/records/phase3-build-gpt/ledger.json"))
assert sol_ledger["caps"]["phase3_build_gpt"] == 264
sol_spent = sum(e["credits"] for e in sol_ledger["entries"])
assert abs(sol_spent - 94.038) < 1e-6
'

# --- the closure document actually cites these same figures (not merely
# consistent with them by coincidence) ---
grep -q "289.01" "$doc" || fail "closure doc missing Phase-R evaluation figure"
grep -q "349.94" "$doc" || fail "closure doc missing Phase-R recovery figure"
grep -q "76.83485" "$doc" || fail "closure doc missing Opus-vs-Sonnet spend figure"
grep -q "94.038" "$doc" || fail "closure doc missing Opus-vs-Sol spend figure"

# --- effective production routing really is what the closure claims is
# unchanged -- Build Opus high, Reviewer Sol high ---
python3 -c '
import json
routing = json.load(open("'"$root"'/records/phase-r/effective-routing.json"))
assert routing["status"] == "PASS"
assert routing["mismatches"] == []
roles = {r["role"]: r for r in routing["roles"]}
build = roles["build"]["expected"]
reviewer = roles["reviewer"]["expected"]
assert build["model"] == "github-copilot/claude-opus-5"
assert build["variant"] == "high"
assert reviewer["model"] == "github-copilot/gpt-5.6-sol"
assert reviewer["variant"] == "high"
'

# --- the closure records Reviewer inversion as NOT_TRIGGERED, and this diff
# does not itself open a Reviewer experiment ---
grep -q "NOT_TRIGGERED" "$doc" || fail "closure doc must record Reviewer inversion as NOT_TRIGGERED"

# --- no production routing or evaluation-infrastructure file was touched by
# this closure (documentation/status only) ---
changed=$(git -C "$root/.." diff --name-only main)
for path in \
  'profiles/' \
  'opencode.jsonc' \
  'eval/fixtures/' \
  'eval/scoring/' \
  'eval/runtime/' \
  '.opencode/agents/'; do
  echo "$changed" | grep -q "^$path" && fail "closure touched non-documentation path: $path"
done
true

printf 'PASS: Phase-3 Build optimization cycle closure is factually grounded\n'
