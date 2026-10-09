#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# Pins the user-selected profile, as amended by the records under
# docs/decisions/, and its permission invariants.
# Changing the profile means changing EXPECTED below on purpose, together with
# a decision record under docs/decisions/.

py - "$bundle" <<'PY' || fail "profile assertions failed"
import sys
from pathlib import Path
from routing import (PERMISSION_FIELDS, ROUTING_FIELDS, load_json, normalized,
                     parse_agent, registers_pin_hook)

bundle = Path(sys.argv[1])
EXPECTED = {
    "planner": {"model": "claude-opus-5-5", "effort": "xhigh", "permissionMode": "plan",
                "disallowedTools": "Edit, Write, NotebookEdit"},
    "general-purpose": {"model": "claude-sonnet-5-5", "effort": "medium"},
    "Explore": {"model": "claude-haiku-5-5", "effort": "medium", "tools": "Read, Grep, Glob"},
    "scout": {"model": "claude-haiku-5-5", "effort": "low", "tools": "WebSearch, WebFetch, Read, Grep, Glob"},
    "reviewer": {"model": "claude-opus-5-5", "effort": "high", "tools": "Read, Grep, Glob"},
    "expert": {"model": "claude-fable-5-1", "effort": "xhigh", "maxTurns": "6",
               "tools": "Read, Grep, Glob",
               "disallowedTools": "Edit, Write, NotebookEdit, Bash, WebFetch, WebSearch, Agent"},
}

agents = {path.stem: path for path in (bundle / "agents").glob("*.md")}
assert set(agents) == set(EXPECTED), f"agent set {sorted(agents)} != {sorted(EXPECTED)}"
assert not any(p.name.lower().startswith("breakglass") for p in bundle.rglob("*")), "breakglass must not exist"
assert not any(p.name == ".claude" for p in bundle.rglob("*")), "no .claude/ directory in the bundle"

for name, path in agents.items():
    fields, body = parse_agent(path)
    assert fields.get("name") == name, f"{name}: name field {fields.get('name')!r}"
    assert fields.get("description"), f"{name}: empty description"
    assert body.strip(), f"{name}: empty prompt body"
    for field in ROUTING_FIELDS + PERMISSION_FIELDS:
        want = normalized(field, EXPECTED[name].get(field))
        have = normalized(field, fields.get(field))
        assert want == have, f"{name}.{field}: expected {want!r}, got {have!r}"

for name in ("reviewer", "expert", "Explore", "scout"):
    tools = normalized("tools", parse_agent(agents[name])[0]["tools"])
    for forbidden in ("Edit", "Write", "NotebookEdit", "Agent", "Bash"):
        assert forbidden not in tools, f"{name} must not have {forbidden}"
    # Claude Code 2.1.291 ignores Bash(...) patterns in a subagent's `tools`
    # and grants unrestricted Bash (evidence P5), so none may appear.
    assert not any(tool.startswith("Bash") for tool in tools), f"{name}: no Bash in any form"

fragment = load_json(bundle / "settings.fragment.json")
assert set(fragment) == {"model", "effortLevel", "env", "hooks"}, sorted(fragment)
assert fragment["model"] == "claude-opus-5-5"
assert fragment["effortLevel"] == "high"
assert fragment["env"] == {"ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-5-5"}
assert registers_pin_hook(fragment)

policy = (bundle / "model-routing.md").read_text(encoding="utf-8")
for needle in ("reviewer", "expert", "general-purpose", "Explore", "scout", "planner",
               "Decision Packet", "Omit the `model` parameter"):
    assert needle in policy, f"model-routing.md must mention {needle!r}"
for model_id in ("claude-opus", "claude-sonnet", "claude-haiku", "claude-fable"):
    assert model_id not in policy, f"model-routing.md must never assign a model ({model_id})"
PY

printf 'PASS: profile-test\n'
