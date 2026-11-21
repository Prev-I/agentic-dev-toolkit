#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/verify-effective-routing.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/runtime/opencode-v2-adapter/verify-effective-routing.sh"

# verify_effective_routing_v2 against fake-api.py serving fixtures-v2/api.

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
mkdir -p "$workdir/neutral" "$workdir/project"

# serve DIR: start the fake on a free port; sets $base, $server_pid.
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

# fresh NAME [keep-lazy]: a private copy of the canned fixtures.
fresh() {
  local d="$workdir/fx-$1"
  rm -rf "${d:?}"
  cp -r "$canned" "$d"
  if [[ "${2:-}" != keep-lazy ]]; then
    find "$d" -name '*.lazy' -delete
  fi
  printf '%s' "$d"
}

# edit FILE JQ-FILTER...: rewrite a fixture in place.
edit() {
  local f=$1
  shift
  jq "$@" "$f" >"$f.new" && mv "$f.new" "$f"
}

# run_verify NAME [extra args]: sets $rc and $out ($workdir/NAME/effective-routing.json).
run_verify() {
  local name=$1
  shift
  rc=0
  verify_effective_routing_v2 --server "$base" --credentials "$workdir/ok.env" \
    --targets "$targets" --outdir "$workdir/$name" --neutral-cwd "$workdir/neutral" "$@" \
    >"$workdir/$name.log" 2>&1 || rc=$?
  out="$workdir/$name/effective-routing.json"
}

role_status() { jq -r --arg r "$1" '.roles[$r].status' "$out"; }

roles=$(jq -r '.agents | keys[]' "$targets")
assert_eq 11 "$(wc -l <<<"$roles")"

# no_watchdog CALLER: within 5 s, no verifier watchdog started for the caller
# shell CALLER (its BASHPID) is left; the watchdog's command line carries
# `_vr_watchdog CALLER INNER`.
no_watchdog() {
  local left=''
  for _ in $(seq 1 50); do
    left=$(pgrep -f "_vr_watchdog $1 " || true)
    [[ -z "$left" ]] && return 0
    sleep 0.1
  done
  fail "verifier watchdog still running for caller $1: $left"
}

# wait_plan_poll: within 10 s, the verifier has asked for the plan agent (the
# never-resolving one), so it is inside the poll.
wait_plan_poll() {
  for _ in $(seq 1 100); do
    grep -q '^GET /api/agent/plan ' "$workdir/requests.log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# 1. all eleven roles PASS, with every agent fixture marked lazy (Review focus 4).
fx=$(fresh pass keep-lazy)
assert_eq 11 "$(find "$fx" -name 'api_agent_*.lazy' | wc -l)"
serve "$fx"
run_verify pass
assert_eq 0 "$rc"
assert_eq PASS "$(jq -r .overall "$out")"
assert_eq 2.3.0 "$(jq -r .runtime_version "$out")"
assert_eq "$base" "$(jq -r .server "$out")"
for r in $roles; do assert_eq PASS "$(role_status "$r")"; done
assert_eq 11 "$(jq '.roles | length' "$out")"
assert_eq deny "$(jq -r '.roles.build.neutral.subagent_breakglass.effect' "$out")"
assert_eq null "$(jq -c '.roles.breakglass.neutral.subagent_breakglass' "$out")"
assert_eq high "$(jq -r '.roles.build.neutral.resolved.variant' "$out")"
stop_server
# every lazy agent really was requested twice (404 then 200).
assert_eq 22 "$(grep -c '^GET /api/agent/' "$workdir/requests.log")"

# 2. a wrong variant is a MISMATCH naming the field.
fx=$(fresh variant)
edit "$fx/api_agent_build.json" '.data.model.variant = "low"'
serve "$fx"
run_verify variant
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_contains "$(jq -r '.roles.build.neutral.mismatches | join(" ")' "$out")" "variant: expected 'high', got 'low'"
assert_eq PASS "$(role_status plan)"
assert_contains "$(<"$workdir/variant.log")" "MISMATCH"
stop_server

# 3. a variant /api/model does not offer for the model is a MISMATCH.
fx=$(fresh novariant)
edit "$fx/api_model.json" '(.data[] | select(.id == "gpt-6.1-sol") | .variants) |= map(select(.id != "high"))'
serve "$fx"
run_verify novariant
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
assert_contains "$(jq -r '.roles.build.neutral.mismatches | join(" ")' "$out")" "is not offered"
assert_eq PASS "$(role_status general)"
stop_server

# 4. breakglass reachable as a subagent is a MISMATCH, whether re-allowed by name
# or by a later wildcard.
fx=$(fresh bgname)
edit "$fx/api_agent_build.json" '.data.permissions += [{"action":"subagent","resource":"breakglass","effect":"allow"}]'
serve "$fx"
run_verify bgname
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
assert_contains "$(jq -r '.roles.build.neutral.mismatches | join(" ")' "$out")" "permissions"
assert_eq allow "$(jq -r '.roles.build.neutral.subagent_breakglass.effect' "$out")"
stop_server
fx=$(fresh bgwild)
edit "$fx/api_agent_plan.json" '.data.permissions += [{"action":"subagent","resource":"*","effect":"allow"}]'
serve "$fx"
run_verify bgwild
assert_eq MISMATCH "$(role_status plan)"
assert_eq '*' "$(jq -r '.roles.plan.neutral.subagent_breakglass.resource' "$out")"
stop_server

# 5. a forbidden model reference and the forbidden effective state are MISMATCHes.
fx=$(fresh forbidden)
edit "$fx/api_agent_expert.json" '.data.model = {"id":"gpt-5.6-sol","providerID":"openai","variant":"high"}'
edit "$fx/api_agent_reviewer.json" '.data.model.id = "claude-opus-4.6"'
serve "$fx"
run_verify forbidden
assert_eq MISMATCH "$(role_status expert)"
assert_contains "$(jq -r '.roles.expert.neutral.mismatches | join(" ")' "$out")" "forbidden_effective_state"
assert_contains "$(jq -r '.roles.reviewer.neutral.mismatches | join(" ")' "$out")" "forbidden reference"
stop_server

# 6. an agent that never resolves is a MISMATCH, not a hang.
fx=$(fresh gone)
rm -f "${fx:?}/api_agent_scout.json"
serve "$fx"
V2_AGENT_POLL_TIMEOUT=1 run_verify gone
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status scout)"
assert_contains "$(jq -r '.roles.scout.neutral.mismatches | join(" ")' "$out")" "did not resolve"
stop_server

# 7. a project-directory answer that differs is PROJECT_OVERRIDE, exit 0. The fake
# ignores the query string, so the project answer is rewritten in a wrapper.
orig_v2_agent_get=$(declare -f v2_agent_get)
eval "${orig_v2_agent_get/v2_agent_get/real_v2_agent_get}"
project_role=build
project_filter='.model.variant = "max"'
# shellcheck disable=SC2329
v2_agent_get() {
  if [[ "$3" == "$workdir/project" && "$2" == "$project_role" ]]; then
    [[ "$project_filter" != FAIL ]] || return 1
    real_v2_agent_get "$@" | jq -c "$project_filter"
  else
    real_v2_agent_get "$@"
  fi
}
fx=$(fresh project)
serve "$fx"
run_verify project --project-cwd "$workdir/project"
assert_eq 0 "$rc"
assert_eq PROJECT_OVERRIDE "$(role_status build)"
assert_eq PROJECT_OVERRIDE "$(jq -r .overall "$out")"
assert_eq max "$(jq -r '.roles.build.project.resolved.variant' "$out")"
assert_eq PASS "$(role_status plan)"
assert_contains "$(<"$workdir/project.log")" "project differs on: variant"
# both working directories reach the server as the directory= query.
enc_neutral=$(jq -rn --arg d "$workdir/neutral" '$d|@uri')
enc_project=$(jq -rn --arg d "$workdir/project" '$d|@uri')
grep -qxF "GET /api/agent/build auth=ok query=directory=$enc_neutral" "$workdir/requests.log" \
  || fail "neutral directory not sent"
grep -qxF "GET /api/agent/build auth=ok query=directory=$enc_project" "$workdir/requests.log" \
  || fail "project directory not sent"
stop_server
# the same wrapper with a neutral MISMATCH stays MISMATCH.
edit "$fx/api_agent_build.json" '.data.model.variant = "low"'
serve "$fx"
run_verify projmismatch --project-cwd "$workdir/project"
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
stop_server

# 7b. a project answer that weakens routing is a MISMATCH naming the reason; only
# a pure allowed difference is PROJECT_OVERRIDE.
fx=$(fresh projbad)
serve "$fx"
project_role=build
project_filter='.permissions += [{"action":"subagent","resource":"breakglass","effect":"allow"}]'
run_verify projbg --project-cwd "$workdir/project"
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq MISMATCH "$(role_status build)"
assert_eq PASS "$(jq -r '.roles.build.neutral.status' "$out")"
assert_eq allow "$(jq -r '.roles.build.project.subagent_breakglass.effect' "$out")"
assert_contains "$(jq -r '.roles.build.project.other_mismatches | join(" ")' "$out")" "permissions"
assert_contains "$(<"$workdir/projbg.log")" "project: permissions"
project_filter='.model.id = "claude-opus-4.6"'
run_verify projforbid --project-cwd "$workdir/project"
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq MISMATCH "$(role_status build)"
assert_contains "$(jq -r '.roles.build.project.other_mismatches | join(" ")' "$out")" "forbidden reference"
project_filter='.model.variant = "nonesuch"'
run_verify projnovar --project-cwd "$workdir/project"
assert_eq 1 "$rc"
assert_contains "$(jq -r '.roles.build.project.other_mismatches | join(" ")' "$out")" "is not offered"
project_filter='.model.variant = "xhigh"'
run_verify projok --project-cwd "$workdir/project"
assert_eq 0 "$rc"
assert_eq PROJECT_OVERRIDE "$(jq -r .overall "$out")"
assert_eq variant "$(jq -r '.roles.build.project.differs | join(",")' "$out")"
project_filter=FAIL
run_verify projgone --project-cwd "$workdir/project"
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq MISMATCH "$(role_status build)"
assert_contains "$(jq -r '.roles.build.project.other_mismatches | join(" ")' "$out")" "did not resolve"
stop_server
unset -f v2_agent_get
eval "${orig_v2_agent_get}"

# 8. a password with a backslash exits 2 and makes no request (Review focus 5).
fx=$(fresh backslash)
serve "$fx"
: >"$workdir/requests.log"
printf 'OPENCODE_PASSWORD=bad\\pw\n' >"$workdir/bs.env"
rc=0
verify_effective_routing_v2 --server "$base" --credentials "$workdir/bs.env" --targets "$targets" \
  --outdir "$workdir/bs" --neutral-cwd "$workdir/neutral" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
assert_eq 0 "$(wc -c <"$workdir/requests.log")"
[[ ! -e "$workdir/bs/effective-routing.json" ]] || fail "wrote a result for refused credentials"
# usage errors also exit 2.
rc=0; verify_effective_routing_v2 --server "$base" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0; verify_effective_routing_v2 --bogus >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
assert_eq 0 "$(wc -c <"$workdir/requests.log")"
stop_server

# 9. --call: the recorded 2.x run output and the message fixture give called.used.
fx=$(fresh call)
serve "$fx"
export FAKE_OPENCODE_LOG="$workdir/opencode.log"
: >"$FAKE_OPENCODE_LOG"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify call --call
assert_eq 0 "$rc"
assert_eq PASS "$(jq -r .overall "$out")"
assert_eq 'build@github-copilot/gpt-6.1-sol#high' "$(jq -r '.roles.build.called.used' "$out")"
assert_eq 'expert@openai/gpt-6-astra#xhigh' "$(jq -r '.roles.expert.called.used' "$out")"
assert_eq true "$(jq -r '.roles.build.called.tool_called' "$out")"
assert_eq 0.026 "$(jq -r '.roles.build.called.cost' "$out")"
assert_eq 11 "$(grep -c '^password_set=yes ' "$FAKE_OPENCODE_LOG")"
if grep -q 'test-only' "$FAKE_OPENCODE_LOG"; then fail "password reached the child's argv"; fi
grep -q -- '\[--server\] \[http://127.0.0.1:' "$FAKE_OPENCODE_LOG" || fail "no --server in argv"
grep -q -- '\[--agent\] \[build\] \[--format\] \[json\] \[--archived\] \[--auto\]' "$FAKE_OPENCODE_LOG" \
  || fail "argv shape: $(head -1 "$FAKE_OPENCODE_LOG")"
# the child ran in a directory holding probe.txt, removed afterwards.
probe_dir=$(sed -n 's/.* cwd=\(.*\) probe=probe-.*/\1/p' "$FAKE_OPENCODE_LOG" | head -1)
[[ -n "$probe_dir" ]] || fail "child did not see probe.txt: $(sed -n 2p "$FAKE_OPENCODE_LOG")"
[[ ! -e "$probe_dir" ]] || fail "probe directory was not cleaned"
# the child got its own XDG directories under the probe dir, never the runner's.
for kind in config data state cache; do
  var="XDG_${kind^^}_HOME"
  seen=$(sed -n "s/^xdg_$kind=//p" "$FAKE_OPENCODE_LOG" | head -1)
  [[ "$seen" == "$probe_dir"/* ]] || fail "$var not under the probe dir: '$seen'"
  [[ "$seen" != "${!var:-}" ]] || fail "$var is the runner's own: $seen"
done
assert_eq 44 "$(grep -c '^xdg_' "$FAKE_OPENCODE_LOG")"
stop_server

# 10. --call with a different model in the session messages is a MISMATCH.
edit "$fx/api_session_ses_build_message.json" '(.data[] | select(.type == "assistant") | .model.id) = "gpt-6-luna"'
serve "$fx"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify callbad --call
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
assert_eq 'build@github-copilot/gpt-6-luna#high' "$(jq -r '.roles.build.called.used' "$out")"
assert_contains "$(jq -r '.roles.build.called_mismatches | join(" ")' "$out")" "expected build@github-copilot/gpt-6.1-sol#high"
assert_eq PASS "$(jq -r '.roles.build.neutral.status' "$out")"
assert_eq PASS "$(role_status plan)"
stop_server

# 11. effective permissions ending in a later wildcard or glob allow reopen breakglass.
fx=$(fresh bgstar)
edit "$fx/api_agent_build.json" '.data.permissions += [{"action":"*","resource":"*","effect":"allow"}]'
edit "$fx/api_agent_plan.json" '.data.permissions += [{"action":"subagent","resource":"break*","effect":"allow"}]'
serve "$fx"
run_verify bgstar
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq MISMATCH "$(role_status build)"
assert_eq '*' "$(jq -r '.roles.build.neutral.subagent_breakglass.action' "$out")"
assert_contains "$(jq -r '.roles.build.neutral.mismatches | join(" ")' "$out")" "permissions"
assert_eq MISMATCH "$(role_status plan)"
assert_eq 'break*' "$(jq -r '.roles.plan.neutral.subagent_breakglass.resource' "$out")"
assert_eq PASS "$(role_status general)"
stop_server

# 12. a failed run never leaves a stale PASS behind; refused credentials exit 2.
mkdir -p "$workdir/stale"
printf '{"overall":"PASS"}\n' >"$workdir/stale/effective-routing.json"
dead_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
base="http://127.0.0.1:$dead_port"
run_verify stale
[[ "$rc" != 0 ]] || fail "an unreachable server exited 0"
assert_eq 1 "$rc"
[[ ! -e "$workdir/stale/effective-routing.json" ]] || fail "stale effective-routing.json survived"
fx=$(fresh auth)
serve "$fx"
mkdir -p "$workdir/auth401"
printf '{"overall":"PASS"}\n' >"$workdir/auth401/effective-routing.json"
printf 'OPENCODE_PASSWORD=wrong-pw\n' >"$workdir/wrong.env"
rc=0
verify_effective_routing_v2 --server "$base" --credentials "$workdir/wrong.env" --targets "$targets" \
  --outdir "$workdir/auth401" --neutral-cwd "$workdir/neutral" >"$workdir/auth401.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
assert_contains "$(<"$workdir/auth401.log")" "refused the credentials"
[[ ! -e "$workdir/auth401/effective-routing.json" ]] || fail "stale file survived a refused login"
stop_server

# 13. --call: a probe that never reads is recorded, not failed; a non-zero exit is a MISMATCH.
fx=$(fresh callvar)
serve "$fx"
FAKE_OPENCODE_NOTOOL=1 OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify notool --call
assert_eq 0 "$rc"
assert_eq PASS "$(jq -r .overall "$out")"
assert_eq false "$(jq -r '.roles.build.called.tool_called' "$out")"
FAKE_OPENCODE_EXIT=3 OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify callexit --call
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq 3 "$(jq -r '.roles.build.called.exit_code' "$out")"
assert_contains "$(jq -r '.roles.build.called_mismatches | join(" ")' "$out")" "exited 3"
stop_server

# 14. odd message shapes: nulls and empty models are a MISMATCH, never a traceback;
# a top-level assistant message (no .info) is accepted.
fx=$(fresh callshape)
printf '%s' '{"data":[{"info":null},{"info":{"role":"assistant","model":{}}},null]}' >"$fx/api_session_ses_build_message.json"
jq '.data = [.data[] | select(.type == "assistant") | del(.type) + {role: "assistant"}]' "$canned/api_session_ses_plan_message.json" >"$fx/api_session_ses_plan_message.json"
serve "$fx"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify callshape --call
assert_eq 1 "$rc"
assert_eq MISMATCH "$(role_status build)"
assert_contains "$(jq -r '.roles.build.called_mismatches | join(" ")' "$out")" "no assistant message"
assert_eq PASS "$(role_status plan)"
assert_eq 'plan@github-copilot/claude-opus-5.5#xhigh' "$(jq -r '.roles.plan.called.used' "$out")"
if grep -q Traceback "$workdir/callshape.log"; then fail "python traceback on odd messages"; fi
stop_server

# 15. a missing credentials file exits 2 and still removes a stale result.
mkdir -p "$workdir/nocreds"
printf '{"overall":"PASS"}\n' >"$workdir/nocreds/effective-routing.json"
rc=0
verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/absent.env" --targets "$targets" \
  --outdir "$workdir/nocreds" --neutral-cwd "$workdir/neutral" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
[[ ! -e "$workdir/nocreds/effective-routing.json" ]] || fail "stale file survived missing credentials"
# the same for a missing targets file.
printf '{"overall":"PASS"}\n' >"$workdir/nocreds/effective-routing.json"
rc=0
verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/ok.env" --targets "$workdir/none.json" \
  --outdir "$workdir/nocreds" --neutral-cwd "$workdir/neutral" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
[[ ! -e "$workdir/nocreds/effective-routing.json" ]] || fail "stale file survived a missing targets file"
# an empty or missing agents map is refused up front (exit 2, clear message),
# before any request, and still removes a stale result.
for agents_json in '{}' 'null'; do
  jq --argjson a "$agents_json" '.agents = $a' "$targets" >"$workdir/noagents.json"
  printf '{"overall":"PASS"}\n' >"$workdir/nocreds/effective-routing.json"
  rc=0
  verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/ok.env" \
    --targets "$workdir/noagents.json" --outdir "$workdir/nocreds" --neutral-cwd "$workdir/neutral" \
    >"$workdir/noagents.log" 2>&1 || rc=$?
  assert_eq 2 "$rc"
  assert_contains "$(<"$workdir/noagents.log")" "declares no agents"
  [[ ! -e "$workdir/nocreds/effective-routing.json" ]] || fail "stale file survived an empty agents map"
done

# a whole-file null or false is valid JSON without an agents object.
for whole in null false; do
  printf '%s\n' "$whole" >"$workdir/whole.json"
  rc=0
  verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/ok.env" \
    --targets "$workdir/whole.json" --outdir "$workdir/nocreds" --neutral-cwd "$workdir/neutral" \
    >"$workdir/whole.log" 2>&1 || rc=$?
  assert_eq 2 "$rc"
  assert_contains "$(<"$workdir/whole.log")" "declares no agents"
done
# a targets file that is not JSON gets its own message, still exit 2.
printf 'not json {\n' >"$workdir/badjson.json"
printf '{"overall":"PASS"}\n' >"$workdir/nocreds/effective-routing.json"
rc=0
verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/ok.env" \
  --targets "$workdir/badjson.json" --outdir "$workdir/nocreds" --neutral-cwd "$workdir/neutral" \
  >"$workdir/badjson.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
assert_contains "$(<"$workdir/badjson.log")" "is not valid JSON"
[[ "$(<"$workdir/badjson.log")" != *"declares no agents"* ]] || fail "invalid JSON reported as declaring no agents"
[[ ! -e "$workdir/nocreds/effective-routing.json" ]] || fail "stale file survived an invalid targets file"

# --server defaults to http://127.0.0.1:4096; checked without any network by
# replacing the isolated runner with one that prints its arguments.
default_server=$(
  v2_run_isolated() { shift; printf '%s\n' "$1"; }
  verify_effective_routing_v2 --credentials "$workdir/ok.env" --targets "$targets" \
    --outdir "$workdir/default-server" --neutral-cwd "$workdir/neutral"
)
assert_eq "http://127.0.0.1:4096" "$default_server"

# 16. an unrelated later deny does not count: the last entry that can decide
# subagent breakglass is still the allow.
fx=$(fresh bgother)
edit "$fx/api_agent_build.json" '.data.permissions += [{"action":"subagent","resource":"breakglass","effect":"allow"},{"action":"subagent","resource":"other-agent","effect":"deny"}]'
serve "$fx"
run_verify bgother
assert_eq 1 "$rc"
assert_eq MISMATCH "$(jq -r .overall "$out")"
assert_eq MISMATCH "$(role_status build)"
assert_eq allow "$(jq -r '.roles.build.neutral.subagent_breakglass.effect' "$out")"
assert_contains "$(jq -r '.roles.build.neutral.mismatches | join(" ")' "$out")" "not a deny"
stop_server

# 17. the collector runs in a subshell: a fatal collector (status 3) reaches the
# caller's EXIT trap as 3, and the caller's own traps are never touched.
marker="$workdir/exit-status"
tmpbase="$workdir/tmpbase"
mkdir -p "$tmpbase"
rc=0
(
  trap 'echo "$?" >"$marker"' EXIT
  # shellcheck disable=SC2030,SC2031
  export TMPDIR="$tmpbase"
  # shellcheck disable=SC2329 # replaces the verifier's collector; the verifier calls it
  _vr_collect() { exit 3; }
  verify_effective_routing_v2 --server "http://127.0.0.1:1" --credentials "$workdir/ok.env" \
    --targets "$targets" --outdir "$workdir/fatal" --neutral-cwd "$workdir/neutral"
) >/dev/null 2>&1 || rc=$?
assert_eq 3 "$rc"
assert_eq 3 "$(<"$marker")"
[[ -z "$(ls -A "$tmpbase")" ]] || fail "temp directories left behind: $(ls -A "$tmpbase")"

fx=$(fresh traps)
serve "$fx"
trap 'cleanup_extra=1' INT
trap 'cleanup_extra=2' TERM
before=$(trap -p)
run_verify traps
assert_eq 0 "$rc"
assert_eq "$before" "$(trap -p)"
# a normal run leaves no watchdog behind.
no_watchdog "$$"
trap - INT TERM
stop_server

# 18. TERM sent to the caller while the verifier polls a never-resolving agent:
# the caller's EXIT trap runs, it exits 143, the verifier's temp directories go,
# and this shell survives.
fx=$(fresh term)
rm -f "${fx:?}/api_agent_plan.json"
: >"$workdir/requests.log"
serve "$fx"
marker="$workdir/parent-exit"
rm -rf "${tmpbase:?}"
mkdir -p "$tmpbase"
(
  trap 'echo parent-exit >"$marker"' EXIT
  # shellcheck disable=SC2030,SC2031
  export TMPDIR="$tmpbase"
  V2_AGENT_POLL_TIMEOUT=60 verify_effective_routing_v2 --server "$base" --credentials "$workdir/ok.env" \
    --targets "$targets" --outdir "$workdir/term" --neutral-cwd "$workdir/neutral"
) >/dev/null 2>&1 &
sub=$!
# the per-run neutral directory exists only once _vr_collect runs, after the
# verifier's traps and watchdog are in place; the plan request proves the poll.
for _ in $(seq 1 100); do
  compgen -G "$tmpbase/*/neutral" >/dev/null && break
  sleep 0.05
done
if ! compgen -G "$tmpbase/*/neutral" >/dev/null || ! wait_plan_poll; then
  kill "$sub" 2>/dev/null || true
  fail "verifier never reached the plan-agent poll"
fi
kill -TERM "$sub"
rc=0; wait "$sub" || rc=$?
assert_eq 143 "$rc"
assert_file "$marker"
assert_eq parent-exit "$(<"$marker")"
# the orphaned collector is ended by its watchdog and cleans up.
for _ in $(seq 1 100); do
  [[ -z "$(ls -A "$tmpbase")" ]] && break
  sleep 0.1
done
[[ -z "$(ls -A "$tmpbase")" ]] || fail "temp directories left behind: $(ls -A "$tmpbase")"
no_watchdog "$sub"
kill -0 $$ || fail "the parent test shell died"
stop_server

# 19. a signal sent only to the verifier's collecting subshell (found through
# its watchdog's command line) while the caller lives on: the verifier returns
# 128+N and the watchdog ends with the subshell rather than outliving it. TERM
# goes through the subshell's traps (temp directories removed); KILL runs no
# trap at all, so only the watchdog's own check on the subshell can stop it.
# inner_signal SIG STATUS
inner_signal() {
  local sig=$1 want=$2 fx rcfile stopflag sub wd inner
  fx=$(fresh "inner$sig")
  rm -f "${fx:?}/api_agent_plan.json"
  : >"$workdir/requests.log"
  serve "$fx"
  rcfile="$workdir/inner$sig.rc"
  stopflag="$workdir/inner$sig.stop"
  rm -rf "${tmpbase:?}"
  mkdir -p "$tmpbase"
  (
    # shellcheck disable=SC2030,SC2031
    export TMPDIR="$tmpbase"
    vrc=0
    V2_AGENT_POLL_TIMEOUT=60 verify_effective_routing_v2 --server "$base" --credentials "$workdir/ok.env" \
      --targets "$targets" --outdir "$workdir/inner$sig" --neutral-cwd "$workdir/neutral" || vrc=$?
    echo "$vrc" >"$rcfile"
    for _ in $(seq 1 200); do
      [[ -e "$stopflag" ]] && break
      sleep 0.05
    done
  ) >/dev/null 2>&1 &
  sub=$!
  if ! wait_plan_poll; then
    kill "$sub" 2>/dev/null || true
    fail "$sig: verifier never reached the plan-agent poll"
  fi
  wd=$(pgrep -f "_vr_watchdog $sub " | head -n1 || true)
  if [[ -z "$wd" ]]; then
    kill "$sub" 2>/dev/null || true
    fail "$sig: no watchdog found for caller $sub"
  fi
  inner=$(tr '\0' '\n' <"/proc/$wd/cmdline" | tail -n1)
  if ! [[ "$inner" =~ ^[0-9]+$ && "$inner" != "$sub" ]]; then
    kill "$sub" 2>/dev/null || true
    fail "$sig: bad subshell pid from the watchdog: $inner"
  fi
  kill -s "$sig" "$inner"
  for _ in $(seq 1 100); do
    [[ -s "$rcfile" ]] && break
    sleep 0.1
  done
  if [[ ! -s "$rcfile" ]]; then
    kill "$sub" 2>/dev/null || true
    fail "$sig: verifier did not return after a signal to its subshell"
  fi
  assert_eq "$want" "$(<"$rcfile")"
  # the caller is still alive, and its watchdog is already gone.
  kill -0 "$sub" 2>/dev/null || fail "$sig: caller ended before the watchdog check"
  no_watchdog "$sub"
  if [[ "$sig" == TERM ]]; then
    [[ -z "$(ls -A "$tmpbase")" ]] || fail "temp directories left behind: $(ls -A "$tmpbase")"
  fi
  touch "$stopflag"
  wait "$sub" || fail "$sig: caller failed after the verifier returned"
  stop_server
}
inner_signal TERM 143
inner_signal KILL 137

# 20. run as a script (not sourced): the function runs, the result file is
# written, the status is the exit code; no arguments is a usage error (2).
fx=$(fresh direct)
serve "$fx"
rc=0
bash "$root/runtime/opencode-v2-adapter/verify-effective-routing.sh" --server "$base" \
  --credentials "$workdir/ok.env" --targets "$targets" \
  --outdir "$workdir/direct" --neutral-cwd "$workdir/neutral" >"$workdir/direct.log" 2>&1 || rc=$?
assert_eq 0 "$rc"
[[ -s "$workdir/direct/effective-routing.json" ]] || fail "direct run wrote no effective-routing.json"
rc=0
bash "$root/runtime/opencode-v2-adapter/verify-effective-routing.sh" >"$workdir/direct-none.log" 2>&1 || rc=$?
assert_eq 2 "$rc"
stop_server

# 21. the assistant-message predicate on the shape OpenCode 2.3.0 returns
# (measured 2026-11-21: newest first, `type` instead of `role`, top-level
# agent/model, idle and agent-switched records), and on the older `.info` shape.
real='{"data":[{"id":"e1","type":"idle","outcome":"completed","time":{}},
 {"id":"m2","type":"assistant","agent":"build","model":{"id":"gpt-sol","providerID":"gw","variant":"high"},"cost":0.04,"content":[]},
 {"id":"m1","type":"user","text":"probe","files":[]},
 {"id":"e0","type":"agent-switched","agent":"build","previous":null}]}'
fmt='map("\(.agent) \(.model.providerID)/\(.model.id)#\(.model.variant)") | join(",")'
assert_eq 'build gw/gpt-sol#high' "$(jq -r "$V2_PICK_ASSISTANT | $fmt" <<<"$real")"
legacy='{"data":[{"info":{"role":"user"}},{"info":{"role":"assistant","agent":"plan","model":{"id":"m","providerID":"p","variant":"v"}}}]}'
assert_eq 'plan p/m#v' "$(jq -r "$V2_PICK_ASSISTANT | $fmt" <<<"$legacy")"
# a top-level `role` (no .info wrapper) is accepted too
assert_eq 'x p/m#v' "$(jq -r "$V2_PICK_ASSISTANT | $fmt" <<<'{"data":[{"role":"assistant","agent":"x","model":{"id":"m","providerID":"p","variant":"v"}}]}')"
# idle, agent-switched, and assistant entries with an empty or null model are
# never selected
assert_eq '' "$(jq -r "$V2_PICK_ASSISTANT" <<<'{"data":[{"type":"agent-switched","agent":"build","model":{"id":"x"}},{"type":"idle"},{"type":"assistant","agent":"b","model":{}},{"type":"assistant","agent":"b","model":null}]}')"
# every assistant turn is emitted, in the order the server gave them
assert_eq 'b p/new#high,b p/old#high' "$(jq -r "$V2_PICK_ASSISTANT | $fmt" <<<'{"data":[{"type":"assistant","agent":"b","model":{"id":"new","providerID":"p","variant":"high"}},{"type":"assistant","agent":"b","model":{"id":"old","providerID":"p","variant":"high"}}]}')"

# 22. --call: two assistant turns that agree pass; turns that disagree are a
# MISMATCH whichever comes first (newest-first order must not hide the newer).
fx=$(fresh turns)
jq '.data |= [(.[] | select(.type == "assistant")), (.[] | select(.type == "assistant"))] + .' \
  "$canned/api_session_ses_build_message.json" >"$fx/api_session_ses_build_message.json"
jq '.data |= ([(.[] | select(.type == "assistant") | .model.variant = "low")] + .)' \
  "$canned/api_session_ses_plan_message.json" >"$fx/api_session_ses_plan_message.json"
serve "$fx"
OPENCODE_BIN="$root/tests/fixtures-v2/fake-opencode-run.sh" run_verify turns --call
assert_eq 1 "$rc"
assert_eq PASS "$(role_status build)"
assert_eq MISMATCH "$(role_status plan)"
assert_contains "$(jq -r '.roles.plan.called_mismatches | join(" ")' "$out")" "#low"
assert_contains "$(jq -r '.roles.plan.called.used' "$out")" ","
stop_server

printf 'PASS: v2-effective-routing-test\n'
