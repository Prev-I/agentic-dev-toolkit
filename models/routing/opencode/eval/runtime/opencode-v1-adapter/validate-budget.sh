#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

validate_phase0_budget() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

valid = (
    data.get("decision_date") == "2026-09-03"
    and data.get("eval_budget_credits") == 100
    and data.get("phase_r_recovery_budget_credits") == 250
    and data.get("recovery_budget_reclaimable_for_eval") is False
    and isinstance(data.get("approval_reference"), str)
    and bool(data["approval_reference"].strip())
    and data.get("copilot_business_standard_allowance_credits") == 1900
    and data.get("organizational_user_guardrail_multiplier") == 4
    and data.get("organizational_user_guardrail_credits") == 7600
    and data["copilot_business_standard_allowance_credits"]
        * data["organizational_user_guardrail_multiplier"]
        == data["organizational_user_guardrail_credits"]
    and data.get("paid_usage") == "allowed"
    and data.get("enforcement") == "github_billing_organizational_control"
    and data.get("opencode_native_enforcement") == "none"
    and data.get("at_guardrail") == "stop_and_escalate_no_automatic_fallback"
    and data.get("historical_usage_observation") == {
        "credits": 331,
        "date": "2026-09-01",
    }
    and data.get("current_remaining_headroom_credits") is None
)
raise SystemExit(0 if valid else 1)
PY
}
