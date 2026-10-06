#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# The README's model map is what a human reads; the frontmatter and fragment
# are what Claude Code reads. This keeps the two from disagreeing silently.

py - "$bundle" <<'PY' || fail "README model map disagrees with the bundle"
import re, sys
from pathlib import Path
from routing import load_json, parse_agent

bundle = Path(sys.argv[1])
readme = (bundle / "README.md").read_text(encoding="utf-8")
section = readme.split("## Model map", 1)[1].split("\n## ", 1)[0]
row = re.compile(r"^\| (?P<role>[^|]+?) \| `(?P<where>[^`]+)` \| `(?P<model>[^`]+)` \| (?P<effort>[^|]+?) \|$")
rows = [m.groupdict() for m in map(row.match, section.splitlines()) if m]
assert rows, "no model-map rows found"

def effort(cell):
    return None if cell == "—" else cell.strip("`")

fragment = load_json(bundle / "settings.fragment.json")
seen = set()
for r in rows:
    where = r["where"]
    if where.startswith("agents/"):
        fields, _ = parse_agent(bundle / where)
        actual = (fields.get("model"), fields.get("effort"))
        seen.add(where)
    elif where == "settings.fragment.json":
        actual = (fragment["model"], fragment["effortLevel"])
    elif where == "env.ANTHROPIC_DEFAULT_HAIKU_MODEL":
        actual = (fragment["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"], None)
    else:
        raise AssertionError(f"unknown location {where}")
    assert (r["model"], effort(r["effort"])) == actual, f"{r['role']}: README {r} vs bundle {actual}"

agents = {f"agents/{p.name}" for p in (bundle / "agents").glob("*.md")}
assert seen == agents, f"README rows {sorted(seen)} vs agent files {sorted(agents)}"
PY

printf 'PASS: docs-test\n'
