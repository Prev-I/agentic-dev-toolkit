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

# Every case runs against stubs, so none reaches the real mise: a `mise` whose
# behaviour STUB_MISE selects, the interpreter it resolves to, and a `python3`
# first on PATH. The real interpreter is found once, before the stubs go on
# PATH. Both stub interpreters hand off to it after recording their working
# directory, their first three arguments and the two install settings.
real_python=$(python3 -c 'import sys; print(sys.executable)')
stubs="$workdir/stubs"
mkdir -p "$stubs" "$workdir/resolved" "$workdir/home"
for which in stubs resolved; do
  cat >"$workdir/$which/python3" <<SH
#!/bin/sh
printf '%s|%s %s %s|%s %s\n' "\$PWD" "\$1" "\$2" "\$3" \
  "\${MISE_AUTO_INSTALL-unset}" "\${MISE_NOT_FOUND_AUTO_INSTALL-unset}" >"$workdir/ran-$which"
exec "$real_python" "\$@"
SH
done
cat >"$stubs/mise" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_LOG.args"
printf '%s %s\n' "${MISE_AUTO_INSTALL-unset}" "${MISE_NOT_FOUND_AUTO_INSTALL-unset}" >"$STUB_LOG.env"
cat >"$STUB_LOG.stdin"
case $STUB_MISE in
  ok) printf '%s\n' "$STUB_RESOLVED" ;;
  exit1) exit 1 ;;
  exit2) exit 2 ;;
  garbage) printf 'not a path\n' ;;
  relative) printf 'resolved/python3\n' ;;
  nonexistent) printf '/nonexistent/python3\n' ;;
  twolines) printf '%s\n%s\n' "$STUB_RESOLVED" "$STUB_RESOLVED" ;;
  hang) sleep 30 ;;
esac
SH
chmod +x "$stubs/python3" "$workdir/resolved/python3" "$stubs/mise"
export PATH="$stubs:$PATH" HOME="$workdir/home" STUB_MISE=ok \
  STUB_LOG="$workdir/mise" STUB_RESOLVED="$workdir/resolved/python3"
reset_stubs() {
  rm -f "$workdir"/ran-* "$workdir"/mise.*
}

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

# Python runs isolated: a json.py in the session's directory, in $HOME, where
# the hook runs Python, or on PYTHONPATH must never be imported. A repository
# is untrusted input to the hook.
mkdir "$workdir/planted" "$workdir/clean"
printf 'open(__file__ + ".ran", "w").close()\nraise SystemExit(7)\n' >"$workdir/planted/json.py"
cp "$workdir/planted/json.py" "$HOME/json.py"
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
  [[ ! -e "$workdir/planted/json.py.ran" && ! -e "$HOME/json.py.ran" ]] ||
    fail "$how: hook imported a planted json.py"
  assert_eq 0 "$rc"
  assert_contains "$out" '"updatedInput"'
  [[ "$out" != *'"model"'* ]] || fail "$how: model must be stripped: $out"
done
rm "$HOME/json.py"

# The interpreter comes from mise as configured for $HOME, with automatic
# installs off and nothing on mise's stdin; python3 on PATH is not used. It
# runs in $HOME, isolated, with installs still off.
reset_stubs
run_hook "$event"
assert_eq 0 "$rc"; assert_contains "$out" '"updatedInput"'
[[ -e "$workdir/ran-resolved" && ! -e "$workdir/ran-stubs" ]] || fail "mise's interpreter was not the one used"
assert_eq "-C $HOME which python3" "$(cat "$workdir/mise.args")"
assert_eq "false false" "$(cat "$workdir/mise.env")"
assert_eq "" "$(cat "$workdir/mise.stdin")"
assert_eq "$HOME|-I -S -c|false false" "$(cat "$workdir/ran-resolved")"

# Whatever mise does short of naming an absolute path to an executable regular
# file, the hook falls back to python3 on PATH, run the same way, and pins.
printf '#!/bin/sh\nexit 0\n' >"$workdir/not-executable"
mkdir -p "$HOME/resolved"
cp "$workdir/resolved/python3" "$HOME/resolved/python3"
for mode in exit1 exit2 garbage relative nonexistent twolines not-executable directory; do
  reset_stubs
  case $mode in
    not-executable) STUB_MISE=ok STUB_RESOLVED="$workdir/not-executable" run_hook "$event" ;;
    directory) STUB_MISE=ok STUB_RESOLVED="$workdir/resolved" run_hook "$event" ;;
    *) STUB_MISE=$mode run_hook "$event" ;;
  esac
  assert_eq 0 "$rc"; assert_contains "$out" '"updatedInput"'
  [[ -e "$workdir/ran-stubs" && ! -e "$workdir/ran-resolved" ]] || fail "$mode: no fallback to python3 on PATH"
  assert_eq "$HOME|-I -S -c|false false" "$(cat "$workdir/ran-stubs")"
done
rm -r "$HOME/resolved"

# mise absent, or no usable HOME: mise is never asked, and Python runs from
# $HOME or, without one, from /. A HOME with spaces is still used.
mkdir "$workdir/nomise" "$workdir/home with space"
ln -s "$stubs/python3" "$workdir/nomise/python3"
ln -s "$(command -v bash)" "$workdir/nomise/bash"
: >"$workdir/not-a-directory"
for case in absent unset-home relative-home file-home spaced-home; do
  reset_stubs
  set +e
  case $case in
    absent) printf '%s' "$event" | PATH="$workdir/nomise" "$hook" ;;
    unset-home) printf '%s' "$event" | env -u HOME "$hook" ;;
    relative-home) printf '%s' "$event" | HOME=relative "$hook" ;;
    file-home) printf '%s' "$event" | HOME="$workdir/not-a-directory" "$hook" ;;
    spaced-home) printf '%s' "$event" | HOME="$workdir/home with space" "$hook" ;;
  esac >"$workdir/out" 2>"$workdir/err"
  rc=$?
  set -e
  assert_eq 0 "$rc"; assert_contains "$(cat "$workdir/out")" '"updatedInput"'
  case $case in
    absent)
      [[ ! -e "$workdir/mise.args" ]] || fail "absent: mise must not be asked"
      assert_eq "$HOME|-I -S -c|false false" "$(cat "$workdir/ran-stubs")" ;;
    spaced-home)
      assert_eq "-C $workdir/home with space which python3" "$(cat "$workdir/mise.args")"
      assert_eq "$workdir/home with space|-I -S -c|false false" "$(cat "$workdir/ran-resolved")" ;;
    *)
      [[ ! -e "$workdir/mise.args" ]] || fail "$case: mise must not be asked"
      assert_eq "/|-I -S -c|false false" "$(cat "$workdir/ran-stubs")" ;;
  esac
done

# A hanging mise query is cut off, and the call still pins. Only the query is
# bounded: a fallback python3 that is itself a shim is not.
if command -v timeout >/dev/null 2>&1; then
  reset_stubs
  SECONDS=0
  STUB_MISE=hang run_hook "$event"
  assert_eq 0 "$rc"; assert_contains "$out" '"updatedInput"'
  ((SECONDS < 15)) || fail "a hanging mise was not cut off (${SECONDS}s)"
fi

# An interpreter that exits 2 on its own, as on an option it does not know,
# must not block delegation, whether mise named it or PATH did.
mkdir "$workdir/exit2"
printf '#!/bin/sh\n: >"%s/ran-exit2"\nexit 2\n' "$workdir" >"$workdir/exit2/python3"
chmod +x "$workdir/exit2/python3"
reset_stubs
STUB_RESOLVED="$workdir/exit2/python3" run_hook "$event"
assert_eq 1 "$rc"; [[ -e "$workdir/ran-exit2" ]] || fail "mise's exit-2 interpreter did not run"
reset_stubs
STUB_MISE=exit1 PATH="$workdir/exit2:$PATH" run_hook "$event"
assert_eq 1 "$rc"; [[ -e "$workdir/ran-exit2" ]] || fail "PATH's exit-2 interpreter did not run"

printf 'PASS: hook-test\n'
