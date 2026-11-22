#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
adapter="$root/runtime/opencode-v2-adapter"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/capability-probe.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/capability-probe.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/budget-ledger.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/budget-ledger.sh"

# One screening dispatch against a per-call sandboxed server: capped client,
# routing check, credits, timeout and budget stop, and the capability probe,
# through fixtures-v2/fake-opencode-screening.sh.

fixtures="$root/tests/fixtures-v2"
work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
# Every pid a fake logged; the cleanup stops what is left of them, by pid only.
cleanup() {
  local p
  for p in $(sed -n 's/^\(serve\|run\) pid=\([0-9]*\) .*/\2/p' "$work/state/log" 2>/dev/null || true); do
    kill -s KILL "$p" 2>/dev/null || true
  done
  rm -rf "${work:?}"
}
trap cleanup EXIT

# The canary must never reach the server or the client.
export EVAL_CANARY_SHOULD_NOT_LEAK=canary

state="$work/state"
mkdir -p "$state"
cat >"$work/opencode" <<EOF
#!/usr/bin/env bash
export FAKE_SCREEN_STATE='$state'
exec '$fixtures/fake-opencode-screening.sh' "\$@"
EOF
chmod +x "$work/opencode"
export OPENCODE_BIN="$work/opencode"
export V2_CONFIG_POLL_TIMEOUT=10 V2_AGENT_POLL_TIMEOUT=10

printf '{"providers":{"fakep":{"settings":{"baseURL":"http://127.0.0.1:9/v1"}}}}\n' >"$work/fragment.json"
printf '{"name":"screening-reviewer","row":{"mode":"primary","model":{"providerID":"fakep","model":"m1","variant":"high"}}}\n' >"$work/row.json"
python3 -I -B "$adapter/v2config.py" build-config - "$work/fragment.json" "$work/row.json" "$work/config.json" \
  || fail "build-config failed"
printf '{"fakep":{"type":"api","key":"not-a-real-key"}}\n' >"$work/creds.json"
printf 'review the change\n' >"$work/prompt.txt"
mkdir -p "$work/ws/lib"
printf 'echo old\n' >"$work/ws/lib/old.sh"
parent="$work/sandboxes"

scenario() {
  printf '%s\n' "$1" >"$state/scenario.json"
}

new_ledger() {
  rm -f "$work/ledger.json"
  ledger_init "$work/ledger.json" '{"candidate_x":1000}'
}

# dispatch OUTDIR [OPTION...]: the common options, then OPTION...
dispatch() {
  local out=$1
  shift
  dispatch_fixture --outdir "$out" --label "$(basename "$out")" --prompt-file "$work/prompt.txt" \
    --sandbox-parent "$parent" --config "$work/config.json" --credentials "$work/creds.json" \
    --workspace "$work/ws" --ledger "$work/ledger.json" --account candidate_x "$@"
}

field() {
  jq -c "$2" "$1/dispatch.json"
}

last_pid() {
  sed -n "s/^$1 pid=\\([0-9]*\\) .*/\\1/p" "$state/log" | tail -n 1
}

ledger_total() {
  jq '[.entries[].credits] | add // 0' "$work/ledger.json"
}

# dispatch_ok
new_ledger
scenario '{"screening-reviewer":{"text":"looks fine","steps":2,"cost_per_step":0.026}}'
dispatch "$work/ok" --agent screening-reviewer --profile-id prof-1 --profile-digest abc123 \
  || fail "healthy dispatch failed: $(cat "$work/ok/dispatch.json" 2>/dev/null)"
assert_eq '"OK"' "$(field "$work/ok" .classification)"
assert_eq 5.2 "$(field "$work/ok" .derived_credits)"
assert_eq true "$(field "$work/ok" .cost_known)"
assert_eq '["screening-reviewer@fakep/m1#high"]' "$(field "$work/ok" .routing_observed)"
assert_eq '"screening-reviewer@fakep/m1#high"' "$(field "$work/ok" .routing_expected)"
assert_eq '"2.3.0-fake"' "$(field "$work/ok" .runtime_version)"
assert_eq '"oc2-dispatch-v1"' "$(field "$work/ok" .eval_runner_version)"
assert_eq '"prof-1"' "$(field "$work/ok" .routing_profile_id)"
assert_eq '"abc123"' "$(field "$work/ok" .profile_digest)"
assert_eq '"agent:screening-reviewer"' "$(field "$work/ok" .dispatch_target)"
assert_eq 2 "$(field "$work/ok" '.server_layers.default | length')"
for f in timestamp label attempt routing_profile_commit environment variant timeout_seconds \
    exit_status failure_class provider_error_text provider_status_code observed_cost \
    normalized_steady_state_cost tokens wall_clock_ms retry_count raw_evidence decides_gate_outcome; do
  assert_eq true "$(jq --arg f "$f" 'has($f)' "$work/ok/dispatch.json")"
done
assert_eq 'looks fine' "$(dispatch_response_text "$work/ok")"
assert_eq OK "$(dispatch_classification "$work/ok")"
assert_eq '"screening-reviewer"' "$(jq -c '.[0].agent' "$work/ok/assistant.json")"
assert_eq 1 "$(jq '.entries | length' "$work/ledger.json")"
assert_eq 5.2 "$(jq '.entries[0].credits' "$work/ledger.json")"
assert_eq '"fakep"' "$(jq -c '.entries[0].provider' "$work/ledger.json")"
assert_eq 0 "$(field "$work/ok" .unfinished_steps)"
assert_eq true "$(field "$work/ok" .cost_complete)"
run_line=$(grep '^run pid=' "$state/log" | tail -n 1)
run_cwd=$(sed -n 's/.* cwd=\(.*\) xdg_config=.*/\1/p' <<<"$run_line")
[[ "$run_cwd" == "$parent/"*/work ]] || fail "run cwd not the sandbox's work dir: $run_cwd"
run_xdg=$(sed -n 's/.* xdg_config=\(.*\)$/\1/p' <<<"$run_line")
[[ "$run_xdg" == "$parent/"* && "$run_xdg" != "${run_cwd%/work}/config" ]] \
  || fail "the client's XDG_CONFIG_HOME is not its own, under the sandbox: $run_xdg"
assert_eq '' "$(ls -A "$parent")"
for p in "$(last_pid serve)" "$(last_pid run)"; do
  ! kill -0 "$p" 2>/dev/null || fail "process $p survived the dispatch"
done
# No credential, password or provider setting in the record: layers keep only
# a digest of their config.
! grep -rq 'not-a-real-key' "$work/ok" || fail "the credentials reached the record"
! grep -rq '127.0.0.1:9' "$work/ok" || fail "the provider fragment reached the record"
assert_eq '["info_sha256","path","type"]' "$(field "$work/ok" '.server_layers.default[0] | keys')"
assert_eq 2 "$(field "$work/ok" '.server_layers.directory | length')"
assert_eq 64 "$(field "$work/ok" '.server_layers.default[0].info_sha256 | length')"
assert_eq false "$(field "$work/ok" '[.. | objects | has("info")] | any')"
# The workspace was in place when the server started.
assert_contains ",$(grep '^serve-cwd-entries ' "$state/log" | tail -n 1 | cut -d' ' -f2-)," ,lib,

# env_allowlist: names only, logged by the fake.
serve_env=$(grep '^serve-env ' "$state/log" | tail -n 1)
for name in OPENCODE_DISABLE_AUTOUPDATE OPENCODE_DISABLE_PROJECT_CONFIG \
    OPENCODE_DISABLE_CLAUDE_CODE_SKILLS OPENCODE_DISABLE_EXTERNAL_SKILLS; do
  assert_contains ",${serve_env#serve-env },"  ",$name,"
done
[[ "$serve_env" != *EVAL_CANARY_SHOULD_NOT_LEAK* ]] || fail "the canary reached the server: $serve_env"
run_env=$(grep '^run-env ' "$state/log" | tail -n 1)
assert_contains ",${run_env#run-env }," ,OPENCODE_PASSWORD,
assert_contains ",${run_env#run-env }," ,XDG_CONFIG_HOME,
[[ "$run_env" != *EVAL_CANARY_SHOULD_NOT_LEAK* ]] || fail "the canary reached the client: $run_env"
[[ "$run_env" != *OPENCODE_BIN* ]] || fail "the operator's environment reached the client: $run_env"

# dispatch_quoted_marker: model text quoting the budget marker is not a stop.
scenario '{"screening-reviewer":{"text":"EVAL_BUDGET_STOP: x"}}'
dispatch "$work/quoted" --agent screening-reviewer || fail "quoted marker: $(field "$work/quoted" .classification)"
assert_eq '"OK"' "$(field "$work/quoted" .classification)"

# dispatch_routing_mismatch
scenario '{"screening-reviewer":{"text":"x","observed_model":{"providerID":"fakep","id":"m1","variant":"low"}}}'
rc=0; dispatch "$work/mismatch" --agent screening-reviewer || rc=$?
assert_eq 1 "$rc"
assert_eq '"ROUTING_MISMATCH"' "$(field "$work/mismatch" .classification)"
assert_eq '["screening-reviewer@fakep/m1#low"]' "$(field "$work/mismatch" .routing_observed)"

# dispatch_expect_overrides
scenario '{"screening-reviewer":{"text":"x"}}'
rc=0; dispatch "$work/expect" --agent screening-reviewer --expect 'screening-reviewer@fakep/m2#high' || rc=$?
assert_eq 1 "$rc"
assert_eq '"ROUTING_MISMATCH"' "$(field "$work/expect" .classification)"

# dispatch_capability_failure
scenario '{"screening-reviewer":{"exit":1,"error_message":"Model not found: fakep/nope"}}'
rc=0; dispatch "$work/capfail" --agent screening-reviewer || rc=$?
assert_eq 1 "$rc"
assert_eq '"CAPABILITY_REGRESSION"' "$(field "$work/capfail" .classification)"
assert_eq '"MODEL_UNRESOLVABLE"' "$(field "$work/capfail" .failure_class)"
assert_eq '"Model not found: fakep/nope"' "$(field "$work/capfail" .provider_error_text)"

# dispatch_budget_stop
new_ledger
scenario '{"screening-reviewer":{"text":"x","steps":20,"step_sleep":0.3,"cost_per_step":0.05}}'
mkdir -p "$work/tmpwatch"
rc=0; TMPDIR="$work/tmpwatch" dispatch "$work/budget" --agent screening-reviewer --stop-credits 12 || rc=$?
returned=$SECONDS
assert_eq 1 "$rc"
assert_eq '"BUDGET_STOP"' "$(field "$work/budget" .classification)"
server=$(last_pid serve)
while kill -0 "$server" 2>/dev/null; do
  (( SECONDS - returned <= 3 )) || fail "server $server alive 3 s after a budget stop"
  sleep 0.1
done
! kill -0 "$(last_pid run)" 2>/dev/null || fail "client survived a budget stop"
# At or past the stop, and far short of the uncapped 100 credits.
python3 -I -c 'import sys; sys.exit(0 if 12 <= float(sys.argv[1]) <= 30 else 1)' "$(ledger_total)" \
  || fail "ledger total $(ledger_total) is not just past the 12-credit stop"
[[ "$(grep '^run-env ' "$state/log" | tail -n 1)" != *EVAL_* ]] || fail "the wrapper's variables reached the client"
assert_eq '' "$(ls -A "$parent")"
# The capped client's stream was buffered inside the sandbox, not in TMPDIR or /tmp.
assert_eq '' "$(ls -A "$work/tmpwatch")"
stream=$(grep '^run-stdout ' "$state/log" | tail -n 1 | cut -d' ' -f2-)
[[ "$stream" == "$parent/"*/client/stream.jsonl ]] || fail "capped stream outside the sandbox: $stream"

# dispatch_timeout_kills_server, plain and through the capped client
for capped in no yes; do
  extra=()
  [[ "$capped" == no ]] || extra=(--stop-credits 1000)
  scenario '{"screening-reviewer":{"text":"x","steps":10,"step_sleep":1,"cost_per_step":0.001}}'
  rc=0; dispatch "$work/timeout-$capped" --agent screening-reviewer --timeout 2 "${extra[@]}" || rc=$?
  assert_eq 1 "$rc"
  assert_eq '"TIMEOUT"' "$(field "$work/timeout-$capped" .classification)"
  for p in "$(last_pid serve)" "$(last_pid run)"; do
    ! kill -0 "$p" 2>/dev/null || fail "process $p survived a timeout (capped=$capped)"
  done
done
assert_eq '' "$(ls -A "$parent")"

# dispatch_unknown_cost
new_ledger
scenario '{"screening-reviewer":{"text":"x","cost_per_step":null}}'
dispatch "$work/unknown" --agent screening-reviewer || fail "unknown-cost dispatch failed"
assert_eq false "$(field "$work/unknown" .cost_known)"
assert_eq null "$(field "$work/unknown" .derived_credits)"
assert_eq 0 "$(jq '.entries | length' "$work/ledger.json")"

# dispatch_no_step_costs_zero: no step_start is a known zero.
scenario '{"screening-reviewer":{"exit":1,"error_message":"usage limit reached"}}'
rc=0; dispatch "$work/nostep" --agent screening-reviewer || rc=$?
assert_eq 1 "$rc"
assert_eq true "$(field "$work/nostep" .cost_known)"
assert_eq true "$(field "$work/nostep" ".derived_credits == 0")"

# dispatch_unfinished_step: a call cut off mid-step ledgers its finished steps
# and says its cost is incomplete.
new_ledger
scenario '{"screening-reviewer":{"steps":3,"partial":true,"exit":1,"error_message":"socket closed unexpectedly","cost_per_step":0.01}}'
rc=0; dispatch "$work/partial" --agent screening-reviewer || rc=$?
assert_eq 1 "$rc"
assert_eq 1 "$(field "$work/partial" .unfinished_steps)"
assert_eq false "$(field "$work/partial" .cost_complete)"
assert_eq true "$(field "$work/partial" .cost_known)"
assert_eq true "$(jq '([.entries[].credits] | add) == 2' "$work/ledger.json")"

# dispatch_commit_from_any_cwd: the commit is the adapter's checkout's, not
# the caller's working directory's.
scenario '{"screening-reviewer":{"text":"x"}}'
(cd "$work" && dispatch "$work/commit" --agent screening-reviewer) || fail "commit dispatch failed"
assert_eq "\"$(git -C "$adapter" rev-parse HEAD)\"" "$(field "$work/commit" .routing_profile_commit)"

# dispatch_model_flag
scenario '{"fakep/m1#high":{"text":"direct"}}'
dispatch "$work/model" --model 'fakep/m1#high' || fail "model dispatch failed: $(cat "$work/model/dispatch.json")"
argv=$(grep '^run-argv ' "$state/log" | tail -n 1)
assert_contains "$argv" '[--model] [fakep/m1#high]'
[[ "$argv" != *--variant* ]] || fail "--variant passed: $argv"
assert_contains "$argv" '[--format] [json] [--archived] [--auto]'
assert_eq '"direct-model-evaluation"' "$(field "$work/model" .routing_profile_id)"
assert_eq '"high"' "$(field "$work/model" .variant)"

# dispatch_sandbox_refused
printf 'leak\n' >"$state/mode"
rc=0; dispatch "$work/refused" --agent screening-reviewer 2>/dev/null || rc=$?
rm -f "$state/mode"
assert_eq 1 "$rc"
assert_eq '"INVALID_ENVIRONMENT"' "$(field "$work/refused" .classification)"
assert_eq '"SANDBOX_REFUSED"' "$(field "$work/refused" .failure_class)"
! kill -0 "$(last_pid serve)" 2>/dev/null || fail "refused server survived"
! grep -rq '127.0.0.1:9' "$work/refused" || fail "the provider fragment reached a refused record"
assert_eq '' "$(ls -A "$parent")"

# dispatch_server_exits_early: the server's own log goes to the terminal, never
# into the record's setup.err.
printf 'die\n' >"$state/mode"
rc=0; dispatch "$work/died" --agent screening-reviewer 2>"$work/died.err" || rc=$?
rm -f "$state/mode"
assert_eq 1 "$rc"
assert_eq '"SANDBOX_REFUSED"' "$(field "$work/died" .failure_class)"
assert_file "$work/died/setup.err"
assert_contains "$(<"$work/died/setup.err")" "exited early"
! grep -q FAKE-SERVER-LOG-MARKER "$work/died/setup.err" || fail "the server log reached setup.err"
assert_contains "$(<"$work/died.err")" FAKE-SERVER-LOG-MARKER
assert_eq '' "$(ls -A "$parent")"

# usage errors
rc=0; dispatch_fixture --outdir "$work/bad" --label x --prompt-file "$work/prompt.txt" \
  --agent a --sandbox-parent "$parent" --credentials "$work/creds.json" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
rc=0; dispatch "$work/bad" --model fakep/m1 --variant high 2>/dev/null || rc=$?
assert_eq 2 "$rc"

# probe_usable_and_wrong
probe_opts=(--sandbox-parent "$parent" --config "$work/config.json" --credentials "$work/creds.json"
  --agent screening-reviewer --ledger "$work/ledger.json" --account candidate_x)
scenario '{"screening-reviewer":{"text":"  CAPABILITY_OK\n"}}'
v2_capability_probe "$work/probe-ok" x "${probe_opts[@]}" || fail "usable probe failed"
assert_eq '{"key":"x","classification":"USABLE"}' "$(jq -c . "$work/probe-ok/probe.json")"
assert_eq '"capability-x"' "$(jq -c .label "$work/probe-ok/dispatch/dispatch.json")"
assert_eq 120 "$(jq -c .timeout_seconds "$work/probe-ok/dispatch/dispatch.json")"
assert_contains "$(grep '^run-argv ' "$state/log" | tail -n 1)" '[Reply with exactly: CAPABILITY_OK]'
scenario '{"screening-reviewer":{"text":"ok"}}'
rc=0; v2_capability_probe "$work/probe-wrong" x "${probe_opts[@]}" || rc=$?
assert_eq 1 "$rc"
assert_eq WRONG_RESPONSE "$(jq -r .classification "$work/probe-wrong/probe.json")"
scenario '{"screening-reviewer":{"exit":1,"error_message":"Model not found: fakep/nope"}}'
rc=0; v2_capability_probe "$work/probe-gone" x "${probe_opts[@]}" || rc=$?
assert_eq 1 "$rc"
assert_eq CAPABILITY_REGRESSION "$(jq -r .classification "$work/probe-gone/probe.json")"

# workspace_out
scenario '{"screening-reviewer":{"text":"done","write_file":{"path":"lib/new.sh","content":"echo new\n"}}}'
dispatch "$work/build" --agent screening-reviewer --workspace-out "$work/ws-out" || fail "build dispatch failed"
assert_eq 'echo new' "$(cat "$work/ws-out/lib/new.sh")"
assert_eq 'echo old' "$(cat "$work/ws-out/lib/old.sh")"
[[ ! -e "$work/ws/lib/new.sh" ]] || fail "the dispatch wrote into the source workspace"
assert_eq '' "$(ls -A "$parent")"

# workspace_out_refuses_non_empty
rc=0; dispatch "$work/build2" --agent screening-reviewer --workspace-out "$work/ws-out" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
[[ ! -e "$work/build2/dispatch.json" ]] || fail "a refused dispatch wrote a record"
assert_eq '' "$(ls -A "$parent")"

# workspace_out_copy_failure_is_recorded
mkdir -p "$work/ws-ro"
chmod 555 "$work/ws-ro"
rc=0; dispatch "$work/build3" --agent screening-reviewer --workspace-out "$work/ws-ro" 2>/dev/null || rc=$?
chmod 755 "$work/ws-ro"
assert_eq 1 "$rc"
assert_eq '"INVALID_ENVIRONMENT"' "$(field "$work/build3" .classification)"
assert_eq '"WORKSPACE_OUT_FAILED"' "$(field "$work/build3" .failure_class)"
assert_eq '' "$(ls -A "$parent")"

printf 'v2-dispatch-test: PASS\n'
