#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# The README's merge and rollback snippets are what a person actually runs
# against their own settings.json. This runs both, verbatim, and pins that a
# merge followed by a rollback gives back exactly what the user had, however
# often it is repeated: restoring an old backup instead would throw away every
# settings change made since the first install.

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

py - "$bundle/README.md" "$workdir" <<'PY' || fail "README snippets could not be extracted"
import re, sys
from pathlib import Path
readme, work = Path(sys.argv[1]).read_text(encoding="utf-8"), Path(sys.argv[2])
for marker, name in (("Merge the settings fragment", "merge.py"), ("To roll back", "rollback.py")):
    section = readme.split(marker, 1)[1]
    block = re.search(r"<<'PY'\n(.*?)\nPY\n", section, re.S)
    assert block, f"no python snippet after {marker!r}"
    (work / name).write_text(block.group(1) + "\n", encoding="utf-8")
PY

user='{"theme": "dark", "env": {"MY_VAR": "1"}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/bin/true"}]}]}, "modelSettings": {"claude-opus-5-5": {"effortLevel": "high"}}}'
printf '%s\n' "$user" >"$workdir/settings.json"

for _ in 1 2; do
  python3 "$workdir/merge.py" "$bundle/settings.fragment.json" "$workdir/settings.json"
done
py - "$workdir/settings.json" <<'PY' || fail "merge did not add the routing keys exactly once"
import json, sys
from routing import pin_hook_commands
s = json.load(open(sys.argv[1]))
assert s["model"] == "claude-opus-5-5" and s["effortLevel"] == "high", s
assert s["env"] == {"MY_VAR": "1", "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5"}, s["env"]
assert len(pin_hook_commands(s)) == 1, s["hooks"]
assert s["theme"] == "dark" and s["modelSettings"], s
PY

python3 "$workdir/rollback.py" "$workdir/settings.json"
py - "$workdir/settings.json" "$user" <<'PY' || fail "rollback did not restore the user's own settings"
import json, sys
assert json.load(open(sys.argv[1])) == json.loads(sys.argv[2]), open(sys.argv[1]).read()
PY

printf 'PASS: install-docs-test\n'
