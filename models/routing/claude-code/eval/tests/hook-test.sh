#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# The hook is the deterministic half of routing: Superpowers always passes a
# per-call `model`, which would otherwise beat the agent's frontmatter. These
# cases pin what it rewrites, what it must leave alone, and that a failure is
# never blocking (exit 2 would block every delegation).

hook="$bundle/hooks/pin-agent-model.sh"
[[ -x "$hook" ]] || fail "hook missing or not executable: $hook"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

run_hook() {
  set +e
  printf '%s' "$1" | "$hook" >"$workdir/out" 2>"$workdir/err"
  rc=$?
  set -e
  out=$(cat "$workdir/out")
  err=$(cat "$workdir/err")
}

agent_event() {
  # $1 = subagent_type, $2 = extra JSON members for tool_input (or empty)
  printf '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"%s","description":"d","prompt":"p"%s}}' \
    "$1" "${2:+,$2}"
}

# Every pinned role: model stripped, everything else preserved.
for role in reviewer expert scout Explore planner; do
  run_hook "$(agent_event "$role" '"model":"sonnet","run_in_background":true,"isolation":"worktree"')"
  assert_eq 0 "$rc"
  [[ "$out" != *permissionDecision* ]] || fail "$role: hook must never emit permissionDecision"
  python3 - "$role" "$out" <<'PY' || fail "$role: wrong updatedInput: $out"
import json, sys
role, out = sys.argv[1], json.loads(sys.argv[2])
spec = out["hookSpecificOutput"]
assert spec["hookEventName"] == "PreToolUse"
assert spec["updatedInput"] == {"subagent_type": role, "description": "d", "prompt": "p",
                                "run_in_background": True, "isolation": "worktree"}, spec
PY
done

# A present key is an override whatever its value.
for value in null '""'; do
  run_hook "$(agent_event reviewer "\"model\":$value")"
  assert_eq 0 "$rc"
  assert_contains "$out" '"updatedInput"'
  [[ "$out" != *'"model"'* ]] || fail "model:$value must be stripped: $out"
done

# Not pinned, or nothing to strip: no output at all.
run_hook "$(agent_event general-purpose '"model":"haiku"')"
assert_eq 0 "$rc"; assert_eq "" "$out"
run_hook "$(agent_event reviewer '')"
assert_eq 0 "$rc"; assert_eq "" "$out"
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls","model":"x"}}'
assert_eq 0 "$rc"; assert_eq "" "$out"
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"p","model":"x"}}'
assert_eq 0 "$rc"; assert_eq "" "$out"

# Unreadable input: non-blocking error, never exit 2.
for bad in 'not json' '[]' '{"tool_name":"Agent","tool_input":"string"}'; do
  run_hook "$bad"
  assert_eq 1 "$rc"
  assert_eq "" "$out"
  assert_contains "$err" "pin-agent-model:"
done

printf 'PASS: hook-test\n'
