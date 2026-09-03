#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
validate_phase0_readiness() {
  python3 - "$1" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except (OSError,json.JSONDecodeError): raise SystemExit(1)
required={"candidate_model_capability","variant_effort_capability","agent_inventory","reviewer_permissions","expert_permissions","breakglass_normal_agent_non_exposure","breakglass_human_primary_execution","eval_budget","phase_r_recovery_budget","self_variance","continuous_thresholds","eval_provenance","installed_profile_manifest","build_restoration_fixture","reviewer_clean_control","compaction_invariants","governance","sol_pricing_regime_handling"}
rows=d.get("gates",[]); names={r.get("gate") for r in rows}; allowed={"PASS","BLOCKED_EXTERNAL","BLOCKED_DECISION","FAIL"}
valid=names==required and len(rows)==len(required) and all(r.get("status") in allowed and r.get("evidence") for r in rows)
complete=valid and all(r["status"]=="PASS" for r in rows)
raise SystemExit(0 if valid and d.get("phase_0_complete") is complete else 1)
PY
}
