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
expected["model"] = "github-copilot/gpt-6-sol"
for role, model in {
    "plan": "github-copilot/claude-opus-5.5",
    "build": "github-copilot/gpt-6-sol",
    "general": "github-copilot/gpt-6-luna",
    "reviewer": "github-copilot/claude-opus-5.5",
    "expert": "openai/gpt-6-astra",
    "breakglass": "openai/gpt-6-sol",
}.items():
    expected["agent"][role]["model"] = model
assert current == expected, "Only approved models/default may change; preserve all permissions and other roles"
targets = json.load(open(sys.argv[1], encoding="utf-8"))
assert targets["profile_id"] == "v3-aligned-plan-breakglass-2026-09-25"
assert targets["decision_reference"] == "docs/decisions/2026-09-25-plan-breakglass-alignment.md"
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
    "plan": "plan-breakglass-alignment/capability/plan-opus55-max/dispatch.json",
    "breakglass": "plan-breakglass-alignment/capability/breakglass-sol6-max/dispatch.json",
}
records_root = os.path.join(os.path.dirname(sys.argv[1]), "..", "records")
for role, relative in records.items():
    record = json.load(open(os.path.join(records_root, relative), encoding="utf-8"))
    target = targets["agents"][role]
    assert record["dispatch_target"] == target["model"], role
    assert record["variant"] == target["variant"], role
    assert record["classification"] == "OK", role
    assert record["provider_error_text"] is None, role
print("PASS: current routing changes only approved models/default")
PY
