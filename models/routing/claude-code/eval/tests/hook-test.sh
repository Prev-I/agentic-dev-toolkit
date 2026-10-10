#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# The hook is the deterministic half of routing: Superpowers always passes a
# per-call `model`, and a caller may pass `effort`; either would otherwise beat
# the agent's frontmatter. These cases pin what it rewrites, what it must leave
# alone, and that a failure is never blocking (exit 2 would block every
# delegation).

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

# Every pinned role: model and effort stripped, everything else preserved.
for role in reviewer expert scout Explore planner; do
  run_hook "$(agent_event "$role" '"model":"sonnet","effort":"max","run_in_background":true,"isolation":"worktree"')"
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

# A present key is an override whatever its value, and either key alone is
# enough to rewrite the call.
for key in model effort; do
  for value in null '""' '"low"'; do
    run_hook "$(agent_event reviewer "\"$key\":$value")"
    assert_eq 0 "$rc"
    assert_contains "$out" '"updatedInput"'
    [[ "$out" != *"\"$key\""* ]] || fail "$key:$value must be stripped: $out"
  done
done

# Not pinned, or nothing to strip: no output at all.
run_hook "$(agent_event general-purpose '"model":"haiku","effort":"max"')"
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

# Python runs isolated: a json.py in the working directory or on PYTHONPATH
# must never be imported. A repository is untrusted input to the hook.
mkdir "$workdir/planted" "$workdir/clean"
printf 'open(__file__ + ".ran", "w").close()\nraise SystemExit(7)\n' >"$workdir/planted/json.py"
event=$(agent_event scout '"model":"sonnet"')
for how in cwd pythonpath; do
  set +e
  if [[ $how == cwd ]]; then
    (cd "$workdir/planted" && printf '%s' "$event" | "$hook") >"$workdir/out" 2>"$workdir/err"
  else
    (cd "$workdir/clean" && printf '%s' "$event" | PYTHONPATH="$workdir/planted" "$hook") >"$workdir/out" 2>"$workdir/err"
  fi
  rc=$?
  set -e
  out=$(cat "$workdir/out")
  [[ ! -e "$workdir/planted/json.py.ran" ]] || fail "$how: hook imported a planted json.py"
  assert_eq 0 "$rc"
  assert_contains "$out" '"updatedInput"'
  [[ "$out" != *'"model"'* ]] || fail "$how: model must be stripped: $out"
done

# An interpreter that exits 2 on its own, as on an option it does not know,
# must not block delegation.
mkdir "$workdir/bin"
printf '#!/bin/sh\nexit 2\n' >"$workdir/bin/python3"
chmod +x "$workdir/bin/python3"
set +e
printf '%s' "$event" | PATH="$workdir/bin:$PATH" "$hook" >"$workdir/out" 2>"$workdir/err"
rc=$?
set -e
assert_eq 1 "$rc"

printf 'PASS: hook-test\n'
