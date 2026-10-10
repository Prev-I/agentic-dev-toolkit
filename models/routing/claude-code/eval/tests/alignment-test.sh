#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/claude-code/eval/tests/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

# check-alignment.sh must catch what changes routing or permissions (DRIFT),
# tolerate prose edits (STALE), and never report what belongs to the user. A
# check that flags a user's own hooks or env vars would cry wolf and stop
# being run.

check="$bundle/eval/check-alignment.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
# live is $HOME/.claude for a fake HOME, so the fragment's "~/.claude/..."
# hook command resolves to the installed hook exactly as on a real machine.
home="$workdir/home"
live="$home/.claude"

# The check runs the installed hook, which asks mise for its interpreter. A
# stub mise and a stub python3 first on PATH keep the suite off the real mise:
# STUB_PY names the interpreter the stub mise reports, or it fails and the hook
# falls back to the stub python3, which hands off to the real interpreter by
# its absolute path, found once here.
stubs="$workdir/stubs"
mkdir -p "$stubs"
cat >"$stubs/mise" <<'SH'
#!/bin/sh
[ -n "${STUB_PY:-}" ] || exit 1
printf '%s\n' "$STUB_PY"
SH
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(python3 -c 'import sys; print(sys.executable)')" >"$stubs/python3"
chmod +x "$stubs/mise" "$stubs/python3"

install_bundle() {
  rm -rf "$live"
  mkdir -p "$live/agents" "$live/hooks" "$live/rules"
  cp "$bundle"/agents/*.md "$live/agents/"
  cp -p "$bundle/hooks/pin-agent-model.sh" "$live/hooks/"
  cp "$bundle/model-routing.md" "$live/rules/"
  cp "$bundle/settings.fragment.json" "$live/settings.json"
}

run_check() {
  set +e
  HOME="$home" CLAUDE_CONFIG_DIR="$live" PATH="$stubs:$PATH" \
    bash "$check" --json "$workdir/report.json" >"$workdir/out" 2>"$workdir/err"
  rc=$?
  set -e
  out=$(cat "$workdir/out")
  err=$(cat "$workdir/err")
}

status() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$workdir/report.json"
}

edit_settings() {
  # $1 = Python statement operating on `s`
  python3 - "$live/settings.json" "$1" <<'PY'
import json, sys
path, statement = sys.argv[1], sys.argv[2]
s = json.load(open(path))
exec(statement)
json.dump(s, open(path, "w"))
PY
}

# Aligned.
install_bundle; run_check
assert_eq 0 "$rc"; assert_eq ALIGNED "$(status)"; assert_contains "$out" "STATUS: ALIGNED"

# User-owned extras are never reported.
install_bundle
printf -- '---\nname: mine\ndescription: x\nmodel: claude-haiku-4-5\n---\nmine\n' >"$live/agents/mine.md"
printf 'my rule\n' >"$live/rules/mine.md"
edit_settings 's["theme"]="dark"; s["env"]["MY_VAR"]="1"; s["hooks"]["PreToolUse"].append({"matcher":"Bash","hooks":[{"type":"command","command":"/bin/true"}]}); s["modelSettings"]["claude-sonnet-5-5"]={"effortLevel":"low"}; s["modelSettings"]["claude-opus-5-5"]["autoCompactWindow"]="auto"'
run_check
assert_eq 0 "$rc"; assert_eq ALIGNED "$(status)"

# Tool-list order is not drift.
install_bundle
sed -i 's/^tools: Read, Grep, Glob$/tools: Glob, Read, Grep/' "$live/agents/expert.md"
run_check
assert_eq 0 "$rc"; assert_eq ALIGNED "$(status)"

# A changed agent model is drift, and the report names agent and field.
install_bundle
sed -i 's/^model: claude-opus-5-5$/model: claude-sonnet-5-5/' "$live/agents/reviewer.md"
run_check
assert_eq 1 "$rc"; assert_eq DRIFT "$(status)"
assert_contains "$out" "agents/reviewer.md"; assert_contains "$out" "model"

# A missing installed agent is drift.
install_bundle; rm "$live/agents/expert.md"; run_check
assert_eq 1 "$rc"; assert_contains "$out" "agents/expert.md"

# A changed prompt body is only stale.
install_bundle; printf 'extra prose\n' >>"$live/agents/reviewer.md"; run_check
assert_eq 0 "$rc"; assert_eq STALE "$(status)"; assert_contains "$out" "STALE"

# Settings routing keys.
install_bundle; edit_settings 's["model"]="claude-sonnet-5-5"'; run_check
assert_eq 1 "$rc"; assert_contains "$out" "settings.model"
install_bundle; edit_settings 's["modelSettings"]["claude-opus-5-5"]["effortLevel"]="medium"'; run_check
assert_eq 1 "$rc"; assert_contains "$out" "settings.modelSettings.claude-opus-5-5.effortLevel"
install_bundle; edit_settings 'del s["modelSettings"]'; run_check
assert_eq 1 "$rc"; assert_contains "$out" "settings.modelSettings.claude-opus-5-5.effortLevel"
install_bundle; edit_settings 's["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"]="claude-sonnet-5-5"'; run_check
assert_eq 1 "$rc"; assert_contains "$out" "ANTHROPIC_DEFAULT_HAIKU_MODEL"
install_bundle; edit_settings 'del s["hooks"]'; run_check
assert_eq 1 "$rc"; assert_contains "$out" "settings.hooks.PreToolUse"

# The registered command must reach the installed hook, not merely end in its
# name: otherwise every Agent call errors and the check still says ALIGNED.
install_bundle
edit_settings 's["hooks"]["PreToolUse"][0]["hooks"][0]["command"]="/nonexistent/pin-agent-model.sh"'
run_check
assert_eq 1 "$rc"; assert_contains "$out" "settings.hooks.PreToolUse"; assert_contains "$out" "/nonexistent"
install_bundle
edit_settings 's["hooks"]["PreToolUse"][0]["hooks"][0]["command"]="\"" + "$" + "HOME/.claude/hooks/pin-agent-model.sh\""'
run_check
assert_eq 0 "$rc"; assert_eq ALIGNED "$(status)"
install_bundle
edit_settings "s['hooks']['PreToolUse'][0]['hooks'][0]['command']='$live/hooks/pin-agent-model.sh'"
run_check
assert_eq 0 "$rc"; assert_eq ALIGNED "$(status)"

# A config dir other than ~/.claude with the fragment's "~/.claude" command:
# the hook it names is not the one installed there.
install_bundle
other="$workdir/other"; rm -rf "$other"; cp -a "$live" "$other"
set +e
HOME="$home" CLAUDE_CONFIG_DIR="$other" PATH="$stubs:$PATH" bash "$check" >"$workdir/out" 2>&1; rc=$?
set -e
assert_eq 1 "$rc"; assert_contains "$(cat "$workdir/out")" "settings.hooks.PreToolUse"

# Hook script: content, presence and the exec bit.
install_bundle; printf '# local edit\n' >>"$live/hooks/pin-agent-model.sh"; run_check
assert_eq 1 "$rc"; assert_contains "$out" "hooks/pin-agent-model.sh"
install_bundle; chmod -x "$live/hooks/pin-agent-model.sh"; run_check
assert_eq 1 "$rc"; assert_contains "$out" "not executable"
install_bundle; rm "$live/hooks/pin-agent-model.sh"; run_check
assert_eq 1 "$rc"; assert_contains "$out" "not installed"

# The installed hook is run, and a run that does not pin is drift even when
# its bytes match: here mise names an interpreter that fails.
printf '#!/bin/sh\necho "broken interpreter" >&2\nexit 1\n' >"$workdir/broken-python"
chmod +x "$workdir/broken-python"
install_bundle; STUB_PY="$workdir/broken-python" run_check
assert_eq 1 "$rc"; assert_eq DRIFT "$(status)"
assert_contains "$out" "hooks/pin-agent-model.sh  run: exit 1: broken interpreter"

# An interpreter that answers but does not pin is drift too.
printf '#!/bin/sh\necho "{}"\n' >"$workdir/wrong-python"
chmod +x "$workdir/wrong-python"
install_bundle; STUB_PY="$workdir/wrong-python" run_check
assert_eq 1 "$rc"; assert_contains "$out" "run: unexpected output for reviewer: '{}'"

# A hook that differs from the bundle is reported and never run.
install_bundle
printf 'touch "%s/ran"\n' "$workdir" >>"$live/hooks/pin-agent-model.sh"
run_check
assert_eq 1 "$rc"; assert_contains "$out" "content differs"
[[ ! -e "$workdir/ran" ]] || fail "a hook that differs from the bundle must not run"

# A hook that never answers is cut off at the timeout.
printf '#!/bin/sh\nsleep 30\n' >"$workdir/hang.sh"
chmod +x "$workdir/hang.sh"
SECONDS=0
detail=$(py - "$workdir/hang.sh" <<'PY'
import sys
from pathlib import Path
from check_alignment import probe_hook
print(probe_hook(Path(sys.argv[1]), timeout=1))
PY
)
assert_eq "no result within 1 s" "$detail"
((SECONDS < 10)) || fail "the hook timeout did not cut the run off (${SECONDS}s)"

# A hook that cannot be started is reported, not raised.
detail=$(py - "$workdir/does-not-exist" <<'PY'
import sys
from pathlib import Path
from check_alignment import probe_hook
print(probe_hook(Path(sys.argv[1])))
PY
)
assert_contains "$detail" "could not start"

# Values must keep their JSON type: Python alone would equate true and 1.
py - <<'PY' || fail "canonical comparison equates true and 1"
from check_alignment import canonical
assert canonical({"a": True}) != canonical({"a": 1})
assert canonical({"a": 1}) != canonical({"a": 1.0})
assert canonical({"a": 1, "b": [None]}) == canonical({"b": [None], "a": 1})
PY

# Policy: missing is drift, edited is stale.
install_bundle; rm "$live/rules/model-routing.md"; run_check
assert_eq 1 "$rc"; assert_contains "$out" "rules/model-routing.md"
install_bundle; printf 'local note\n' >>"$live/rules/model-routing.md"; run_check
assert_eq 0 "$rc"; assert_eq STALE "$(status)"

# Nothing installed, and unreadable settings: exit 2, no traceback.
rm -rf "$live"; mkdir -p "$live"; run_check
assert_eq 2 "$rc"; assert_contains "$err" "nothing installed"
install_bundle; printf '{ not json' >"$live/settings.json"; run_check
assert_eq 2 "$rc"; assert_contains "$err" "not valid JSON"
[[ "$err" != *Traceback* ]] || fail "invalid settings must not produce a traceback"
install_bundle; printf '[]' >"$live/settings.json"; run_check
assert_eq 2 "$rc"; [[ "$err" != *Traceback* ]] || fail "non-object settings must not produce a traceback"

# Usage error.
set +e; HOME="$home" CLAUDE_CONFIG_DIR="$live" bash "$check" --bogus >/dev/null 2>&1; rc=$?; set -e
assert_eq 2 "$rc"

printf 'PASS: alignment-test\n'
