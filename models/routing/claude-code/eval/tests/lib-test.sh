#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# routing.py is the one parser every other suite and the alignment check use.
# A lenient parser would let a malformed installed agent compare as "equal";
# these cases pin that anything it does not understand is an error.

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

printf -- '---\nname: probe\nmodel: claude-opus-5-5\ntools: Read, Bash(git diff:*), Grep\n---\n\nBody line.\n' \
  >"$workdir/ok.md"
printf -- 'name: probe\n' >"$workdir/no-open.md"
printf -- '---\nname: probe\n' >"$workdir/no-close.md"
printf -- '---\nname: a\nname: b\n---\n' >"$workdir/dup.md"
printf -- '---\n  nested: value\n---\n' >"$workdir/nested.md"

py - "$workdir" <<'PY' || fail "routing.py library assertions failed"
import sys
from pathlib import Path
from routing import FrontmatterError, normalized, parse_agent, registers_pin_hook

work = Path(sys.argv[1])

fields, body = parse_agent(work / "ok.md")
assert fields == {"name": "probe", "model": "claude-opus-5-5",
                  "tools": "Read, Bash(git diff:*), Grep"}, fields
assert body == "\nBody line.\n", repr(body)

for name in ("no-open.md", "no-close.md", "dup.md", "nested.md"):
    try:
        parse_agent(work / name)
    except FrontmatterError as error:
        assert str(work / name) in str(error), error
    else:
        raise AssertionError(f"{name} must raise FrontmatterError")

assert normalized("tools", "Read, Grep") == normalized("tools", "Grep,Read")
assert normalized("tools", None) is None
assert normalized("model", "claude-opus-5-5") == "claude-opus-5-5"

hook = {"type": "command", "command": "~/.claude/hooks/pin-agent-model.sh"}
assert registers_pin_hook({"hooks": {"PreToolUse": [{"matcher": "Agent", "hooks": [hook]}]}})
assert not registers_pin_hook({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [hook]}]}})
assert not registers_pin_hook({})
assert not registers_pin_hook({"hooks": {"PreToolUse": "not-a-list"}})
PY

printf 'PASS: lib-test\n'
