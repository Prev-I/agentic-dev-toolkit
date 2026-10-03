#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"
CURRENT=$(load_routing_profile "$root/../opencode.jsonc") \
RESTORED=$(load_routing_profile "$root/../profiles/v1-restored-2026-09.jsonc") \
python3 - "$root/manifests/current-routing-targets.json" <<'PY'
import json
import os
import sys

current = json.loads(os.environ["CURRENT"])
expected = json.loads(os.environ["RESTORED"])
expected["model"] = "github-copilot/gpt-6.1-sol"
approved = {
    "plan": ("github-copilot/claude-opus-5.5", "xhigh"),
    "build": ("github-copilot/gpt-6.1-sol", "high"),
    "general": ("github-copilot/gpt-6.1-sol", "medium"),
    "explore": ("github-copilot/gpt-6-luna", "medium"),
    "scout": ("github-copilot/gpt-6-luna", "low"),
    "reviewer": ("github-copilot/claude-opus-5.5", "high"),
    "expert": ("openai/gpt-6-astra", "xhigh"),
    "breakglass": ("openai/gpt-6.1-sol", "max"),
    "compaction": ("github-copilot/claude-sonnet-5.5", "low"),
    "title": ("github-copilot/gpt-6-luna", "low"),
    "summary": ("github-copilot/gpt-6-luna", "low"),
}
for role, (model, variant) in approved.items():
    expected["agent"][role]["model"] = model
    expected["agent"][role]["variant"] = variant
assert current == expected, "Only approved models/default/variants may change; preserve all permissions and modes"
targets = json.load(open(sys.argv[1], encoding="utf-8"))
assert targets["profile_id"] == "v6-current-routing-2026-10-03"
assert targets["decision_reference"] == "docs/decisions/2026-10-03-current-routing-alignment.md"
assert targets["routing_authority"] == "opencode.jsonc agent block"
assert targets["markdown_agents_carry_routing_fields"] is False
assert targets["default_model"] == current["model"]
assert set(targets["agents"]) == set(current["agent"])
for role, target in targets["agents"].items():
    row = current["agent"][role]
    for field in ("model", "variant", "mode"):
        if target[field] is not None:
            assert row.get(field) == target[field], (role, field)
records = {
    "explore": "gpt6-role-screening/recovery/explore/pair1-arm2-luna6/dispatch/dispatch.json",
    "scout": "navigation-model-alignment/capability/scout-luna6-low/dispatch.json",
}
records_root = os.path.join(os.path.dirname(sys.argv[1]), "..", "records")
for role, relative in records.items():
    record = json.load(open(os.path.join(records_root, relative), encoding="utf-8"))
    target = targets["agents"][role]
    assert record["dispatch_target"] == target["model"], role
    assert record["variant"] == target["variant"], role
    assert record["classification"] == "OK", role
    assert record["provider_error_text"] is None, role
adjudication = json.load(open(os.path.join(records_root, "gpt6-role-screening", "adjudication.json"), encoding="utf-8"))
explore_result = next(
    item for item in adjudication["results"]["explore"]["workloads"]
    if item["model"] == "gpt-6-luna"
)
assert explore_result["gate_passed"] is True
print("PASS: current routing changes only approved models/default/variants")
PY
