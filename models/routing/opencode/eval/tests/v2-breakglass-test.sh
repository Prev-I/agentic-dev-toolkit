#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/probe-breakglass.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/runtime/opencode-v2-adapter/probe-breakglass.sh"

# probe_breakglass_v2 against fake-api.py serving fixtures-v2/api.

workdir=$(mktemp -d)
server_pid=''
stop_server() {
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  server_pid=''
}
cleanup() {
  stop_server
  rm -rf "${workdir:?}"
}
trap cleanup EXIT

targets="$root/../v2/manifests/current-routing-targets.json"
canned="$root/tests/fixtures-v2/api"
printf 'OPENCODE_PASSWORD=test-only\n' >"$workdir/ok.env"
mkdir -p "$workdir/cwd"
export V2_AGENT_POLL_TIMEOUT=2

serve() {
  local out="$workdir/server.out"
  : >"$out"
  FAKE_API_LOG="$workdir/requests.log" python3 "$root/tests/fixtures-v2/fake-api.py" 0 "$1" >"$out" &
  server_pid=$!
  for _ in $(seq 1 100); do
    [[ -s "$out" ]] && break
    sleep 0.05
  done
  [[ -s "$out" ]] || fail "fake-api.py did not report its port"
  local port
  IFS=" " read -r port _ <"$out"
  base="http://127.0.0.1:$port"
}

fresh() {
  local d="$workdir/fx-$1"
  rm -rf "${d:?}"
  cp -r "$canned" "$d"
  find "$d" -name '*.lazy' -delete
  printf '%s' "$d"
}

edit() {
  local f=$1
  shift
  jq "$@" "$f" >"$f.new" && mv "$f.new" "$f"
}

# run_probe NAME [extra args]: sets $rc and $out ($workdir/NAME/breakglass.json).
run_probe() {
  local name=$1
  shift
  rc=0
  probe_breakglass_v2 --server "$base" --credentials "$workdir/ok.env" \
    --targets "$targets" --outdir "$workdir/$name" --cwd "$workdir/cwd" "$@" \
    >"$workdir/$name.log" 2>&1 || rc=$?
  out="$workdir/$name/breakglass.json"
}

# 0. the script names no model.
if grep -E 'gpt-|claude-' "$root/runtime/opencode-v2-adapter/probe-breakglass.sh"; then
  fail "probe-breakglass.sh contains a model id"
fi

# 1. fixtures: PASS, primary, the manifest's model, every other agent a deny.
fx=$(fresh pass)
serve "$fx"
run_probe pass
assert_eq 0 "$rc"
assert_eq PASS "$(jq -r .status "$out")"
assert_eq true "$(jq -r .resolved_primary "$out")"
assert_eq 'openai/gpt-6.1-sol#max' "$(jq -r .model "$out")"
assert_eq 10 "$(jq '.non_exposure | length' "$out")"
assert_eq deny "$(jq -r '.non_exposure.build' "$out")"
for a in build general explore plan compaction title summary scout reviewer expert; do
  assert_eq deny "$(jq -r --arg a "$a" '.non_exposure[$a]' "$out")"
done
assert_eq null "$(jq -c '.non_exposure.breakglass' "$out")"
assert_eq null "$(jq -c '.called' "$out")"
grep -q '^GET /api/agent ' "$workdir/requests.log" || fail "no agent list request"
grep -q 'query=directory=' "$workdir/requests.log" || fail "no directory query"
stop_server

# 2. breakglass served as a subagent: FAIL.
fx=$(fresh sub)
edit "$fx/api_agent_breakglass.json" '.data.mode = "subagent"'
edit "$fx/api_agent.json" '(.data[] | select(.id == "breakglass") | .mode) = "subagent"'
serve "$fx"
run_probe sub
assert_eq 1 "$rc"
assert_eq FAIL "$(jq -r .status "$out")"
assert_eq false "$(jq -r .resolved_primary "$out")"
assert_contains "$(<"$workdir/sub.log")" "FAIL"
assert_contains "$(<"$workdir/sub.log")" "mode is 'subagent', expected 'primary'"
stop_server

# 3. breakglass on the wrong model: FAIL.
fx=$(fresh wrongmodel)
edit "$fx/api_agent_breakglass.json" '.data.model.variant = "low"'
serve "$fx"
run_probe wrongmodel
assert_eq 1 "$rc"
assert_eq FAIL "$(jq -r .status "$out")"
assert_eq false "$(jq -r .resolved_primary "$out")"
assert_contains "$(<"$workdir/wrongmodel.log")" "model is openai/gpt-6.1-sol#low, expected openai/gpt-6.1-sol#max"
stop_server

# 4. each other agent whose last matching entry allows breakglass: FAIL, naming it.
for a in build general explore plan compaction title summary scout reviewer expert; do
  fx=$(fresh "ex-$a")
  edit "$fx/api_agent_$a.json" '.data.permissions += [{"action":"subagent","resource":"*","effect":"allow"}]'
  serve "$fx"
  run_probe "ex-$a"
  assert_eq 1 "$rc"
  assert_eq FAIL "$(jq -r .status "$out")"
  assert_eq EXPOSED "$(jq -r --arg a "$a" '.non_exposure[$a]' "$out")"
  assert_contains "$(<"$workdir/ex-$a.log")" "EXPOSED  $a"
  assert_eq PASS "$(jq -r 'if (.non_exposure | to_entries | map(select(.value == "EXPOSED")) | length) == 1 then "PASS" else "many" end' "$out")"
  stop_server
done

# 5. a wildcard glob and the catch-all re-open it; an earlier allow does not.
fx=$(fresh glob)
edit "$fx/api_agent_plan.json" '.data.permissions += [{"action":"subagent","resource":"break*","effect":"allow"}]'
edit "$fx/api_agent_scout.json" '.data.permissions += [{"action":"*","resource":"*","effect":"allow"}]'
edit "$fx/api_agent_explore.json" '.data.permissions = [{"action":"subagent","resource":"*","effect":"allow"},{"action":"subagent","resource":"breakglass","effect":"deny"}]'
serve "$fx"
run_probe glob
assert_eq 1 "$rc"
assert_eq EXPOSED "$(jq -r .non_exposure.plan "$out")"
assert_eq EXPOSED "$(jq -r .non_exposure.scout "$out")"
assert_eq deny "$(jq -r .non_exposure.explore "$out")"
stop_server

# 6. no matching entry at all is exposure (the default is not a deny).
fx=$(fresh nomatch)
edit "$fx/api_agent_title.json" '.data.permissions = []'
serve "$fx"
run_probe nomatch
assert_eq 1 "$rc"
assert_eq EXPOSED "$(jq -r .non_exposure.title "$out")"
stop_server

# 7. an agent the server lists but the manifest does not is covered too.
fx=$(fresh extra)
jq '.data.id = "custom" | .data.name = "Custom" | .data.mode = "subagent"
    | .data.permissions += [{"action":"subagent","resource":"breakglass","effect":"allow"}]' \
  "$fx/api_agent_build.json" >"$fx/api_agent_custom.json"
jq --slurpfile c "$fx/api_agent_custom.json" '.data += [$c[0].data]' "$fx/api_agent.json" >"$fx/api_agent.new" \
  && mv "$fx/api_agent.new" "$fx/api_agent.json"
serve "$fx"
run_probe extra
assert_eq 1 "$rc"
assert_eq EXPOSED "$(jq -r .non_exposure.custom "$out")"
assert_eq 11 "$(jq '.non_exposure | length' "$out")"
assert_contains "$(<"$workdir/extra.log")" "EXPOSED  custom"
stop_server

# 8. an agent in the list that does not resolve is a FAIL, not a silent skip.
fx=$(fresh unresolved)
edit "$fx/api_agent.json" '.data += [{"id":"ghost","name":"Ghost"}]'
serve "$fx"
run_probe unresolved
assert_eq 1 "$rc"
assert_eq UNRESOLVED "$(jq -r .non_exposure.ghost "$out")"
assert_contains "$(<"$workdir/unresolved.log")" "ghost: did not resolve"
stop_server

# 8b. a malformed permissions entry or field never crashes the probe: the
# result is still written, and the agent is not treated as safe.
fx=$(fresh malformed)
edit "$fx/api_agent_title.json" '.data.permissions = ["junk", 3, null]'
edit "$fx/api_agent_summary.json" '.data.permissions = "none"'
serve "$fx"
run_probe malformed
assert_eq 1 "$rc"
assert_eq FAIL "$(jq -r .status "$out")"
assert_eq EXPOSED "$(jq -r .non_exposure.title "$out")"
assert_eq EXPOSED "$(jq -r .non_exposure.summary "$out")"
stop_server

# 8c. an agent list that cannot be read is a FAIL (not a pass on manifest
# roles alone), with breakglass.json written.
for variant in missing notarray; do
  fx=$(fresh "list-$variant")
  if [[ "$variant" == missing ]]; then
    rm -f "$fx/api_agent.json"
  else
    printf '{"data":{"id":"build"}}\n' >"$fx/api_agent.json"
  fi
  jq '.data.id = "custom" | .data.permissions += [{"action":"subagent","resource":"breakglass","effect":"allow"}]' \
    "$fx/api_agent_build.json" >"$fx/api_agent_custom.json"
  serve "$fx"
  run_probe "list-$variant"
  assert_eq 1 "$rc"
  assert_eq FAIL "$(jq -r .status "$out")"
  assert_contains "$(<"$workdir/list-$variant.log")" "agent list for $workdir/cwd could not be read"
  stop_server
done

# 9. a list that lacks manifest roles is polled for until the bound, and those
# roles are still checked by name.
fx=$(fresh partial)
edit "$fx/api_agent.json" '.data |= map(select(.id != "reviewer" and .id != "build"))'
serve "$fx"
run_probe partial
assert_eq 0 "$rc"
assert_eq deny "$(jq -r .non_exposure.reviewer "$out")"
assert_eq deny "$(jq -r .non_exposure.build "$out")"
stop_server

# 10. credentials and usage.
fx=$(fresh auth)
serve "$fx"
printf 'OPENCODE_PASSWORD=wrong\n' >"$workdir/bad.env"
rc=0
probe_breakglass_v2 --server "$base" --credentials "$workdir/bad.env" --targets "$targets" \
  --outdir "$workdir/auth" --cwd "$workdir/cwd" >"$workdir/auth.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
[[ ! -f "$workdir/auth/breakglass.json" ]] || fail "result left after refused credentials"
rc=0
probe_breakglass_v2 --server "$base" >"$workdir/usage.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0
probe_breakglass_v2 --bogus >"$workdir/usage.log" 2>&1 || rc=$?
assert_eq 2 "$rc"

# 11. a stale breakglass.json never survives a failed run.
mkdir -p "$workdir/stale"
printf '{"status":"PASS"}\n' >"$workdir/stale/breakglass.json"
rc=0
probe_breakglass_v2 --server "$base" --credentials "$workdir/bad.env" --targets "$targets" \
  --outdir "$workdir/stale" --cwd "$workdir/cwd" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
[[ ! -f "$workdir/stale/breakglass.json" ]] || fail "stale breakglass.json survived"
stop_server

# 12. --call: the recorded run and the message fixture give called.used.
fx=$(fresh call)
serve "$fx"
export FAKE_OPENCODE_LOG="$workdir/opencode.log"
: >"$FAKE_OPENCODE_LOG"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_probe call --call
assert_eq 0 "$rc"
assert_eq PASS "$(jq -r .status "$out")"
assert_eq 'breakglass@openai/gpt-6.1-sol#max' "$(jq -r .called.used "$out")"
assert_eq true "$(jq -r .called.tool_called "$out")"
assert_eq 1 "$(grep -c '^password_set=yes ' "$FAKE_OPENCODE_LOG")"
if grep -q 'test-only' "$FAKE_OPENCODE_LOG"; then fail "password reached the child's argv"; fi
grep -q -- '\[--agent\] \[breakglass\] \[--format\] \[json\]' "$FAKE_OPENCODE_LOG" || fail "argv shape"
stop_server

# 13. --call with a different model used is a FAIL; a failing run too.
fx=$(fresh callbad)
edit "$fx/api_session_ses_breakglass_message.json" '(.data[] | select(.type == "assistant") | .model.id) = "gpt-6-luna"'
serve "$fx"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_probe callbad --call
assert_eq 1 "$rc"
assert_eq FAIL "$(jq -r .status "$out")"
assert_eq 'breakglass@openai/gpt-6-luna#max' "$(jq -r .called.used "$out")"
stop_server
fx=$(fresh callexit)
serve "$fx"
FAKE_OPENCODE_EXIT=3 OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_probe callexit --call
assert_eq 1 "$rc"
assert_eq 3 "$(jq -r .called.exit_code "$out")"
stop_server

# 14. the caller's EXIT, INT and TERM traps are not touched.
saved_exit=$(trap -p EXIT)
trap 'stop_server; rm -rf "${workdir:?}"' EXIT
trap 'echo caller-int' INT
trap 'echo caller-term' TERM
before=$(trap -p EXIT INT TERM)
fx=$(fresh trap)
serve "$fx"
run_probe trap
assert_eq 0 "$rc"
assert_eq "$before" "$(trap -p EXIT INT TERM)"
trap - INT TERM
eval "${saved_exit:-trap - EXIT}"
stop_server

# 15. no bytecode is written next to the scripts.
[[ -z "$(find "$root/runtime/opencode-v2-adapter" -name __pycache__)" ]] \
  || fail "a __pycache__ appeared in the adapter directory"

# 16. run as a script (not sourced): the function runs, the result file is
# written, the status is the exit code; no arguments is a usage error (2).
fx=$(fresh direct)
serve "$fx"
rc=0
bash "$root/runtime/opencode-v2-adapter/probe-breakglass.sh" --server "$base" \
  --credentials "$workdir/ok.env" --targets "$targets" \
  --outdir "$workdir/direct" --cwd "$workdir/cwd" >"$workdir/direct.log" 2>&1 || rc=$?
assert_eq 0 "$rc"
[[ -s "$workdir/direct/breakglass.json" ]] || fail "direct run wrote no breakglass.json"
rc=0
bash "$root/runtime/opencode-v2-adapter/probe-breakglass.sh" >"$workdir/direct-none.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
stop_server

printf 'PASS: v2-breakglass-test\n'
