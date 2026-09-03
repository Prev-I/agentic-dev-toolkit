#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/validate-budget.sh"

manifest="$root/manifests/phase-0-budgets.json"
validate_phase0_budget "$manifest"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
for mutation in eval recovery reclaim native approval headroom; do
  python3 - "$manifest" "$workspace/$mutation.json" "$mutation" <<'PY'
import json
import sys
source, output, mutation = sys.argv[1:]
data = json.load(open(source, encoding="utf-8"))
changes = {
    "eval": ("eval_budget_credits", 99),
    "recovery": ("phase_r_recovery_budget_credits", 249),
    "reclaim": ("recovery_budget_reclaimable_for_eval", True),
    "native": ("opencode_native_enforcement", "enabled"),
    "approval": ("approval_reference", ""),
    "headroom": ("current_remaining_headroom_credits", 7269),
}
key, value = changes[mutation]
data[key] = value
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
  if validate_phase0_budget "$workspace/$mutation.json"; then
    fail "accepted invalid budget mutation: $mutation"
  fi
done
printf 'PASS: Phase 0 budget decision\n'
