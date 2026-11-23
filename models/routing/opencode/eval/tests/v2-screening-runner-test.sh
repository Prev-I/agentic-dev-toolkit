#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
runner="$root/runtime/opencode-v2-adapter/run-screening.sh"

# The screening runner: prepare, approval, dispatch and score, through
# fixtures-v2/fake-opencode-screening.sh.

fixtures="$root/tests/fixtures-v2"
work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
runner_pid=''
extra_pids=()
orphan_session=''
# Every pid a fake logged, a runner left running, the test's own stand-ins and
# the session an orphaned call runs in; stopped by pid (or that session's
# process group id) only.
cleanup() {
  local p
  [[ -z "$runner_pid" ]] || kill -s KILL "$runner_pid" 2>/dev/null || true
  [[ -z "$orphan_session" ]] || kill -s KILL -- "-$orphan_session" 2>/dev/null || true
  for p in "${extra_pids[@]}"; do kill -s KILL "$p" 2>/dev/null || true; done
  for p in $(sed -n 's/^\(serve\|run\) pid=\([0-9]*\) .*/\2/p' "$work/state/log" 2>/dev/null || true); do
    kill -s KILL "$p" 2>/dev/null || true
  done
  rm -rf "${work:?}"
}
trap cleanup EXIT

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

cat >"$state/models.json" <<'EOF'
{"data":[
 {"providerID":"fakep","id":"m1","variants":[{"id":"high","settings":{}}],"cost":[{"input":1,"output":2}]},
 {"providerID":"fakep","id":"m2","variants":[{"id":"high","settings":{}}],"cost":[{"input":1,"output":2}]},
 {"providerID":"fakep","id":"m3","variants":[{"id":"high","settings":{}}],"cost":[]}
]}
EOF
printf '{"providers":{"fakep":{"settings":{"baseURL":"http://127.0.0.1:9/v1"}}}}\n' >"$work/fragment.json"
printf '{"fakep":{"type":"api","key":"tok-SECRET-123"}}\n' >"$work/creds.json"

scenario() {
  printf '%s\n' "$1" >"$state/scenario.json"
}

# quiet COMMAND...: COMMAND's stderr is shown only when it fails.
quiet() {
  local rc=0
  "$@" 2>"$work/stderr" || rc=$?
  (( rc == 0 )) || cat "$work/stderr" >&2
  return "$rc"
}

# prepare OUT ROLE BUDGET CANDIDATE...: the printed approval goes to OUT.approval.
prepare() {
  local out=$1 role=$2 budget=$3 c args=()
  shift 3
  for c in "$@"; do args+=(--candidate "$c"); done
  quiet bash "$runner" prepare --role "$role" --out "$out" "${args[@]}" --runs 1 --budget "$budget" \
    --providers "$work/fragment.json" --credentials "$work/creds.json" >"$out.approval"
}

approve() {
  cp "$1.approval" "$1/approval.json"
}

dispatch() {
  quiet bash "$runner" dispatch --out "$1" --providers "$work/fragment.json" --credentials "$work/creds.json"
}

log_count() {
  grep -c "^$1 pid=" "$state/log" 2>/dev/null || true
}

# gone PID: PID (a child of this shell) has exited, within 5 s.
gone() {
  local state
  for _ in $(seq 1 50); do
    state=$(ps -o stat= -p "$1" 2>/dev/null || true)
    [[ -n "$state" && "$state" != Z* ]] || return 0
    sleep 0.1
  done
  return 1
}

no_secret_in() {
  ! grep -rq tok-SECRET-123 "$1" || fail "the credential reached the record $1"
  assert_eq '' "$(find "$1" -name auth.json -o -name '*.db')"
}

# A scratch HOME and TMPDIR; system tools first, since a version manager's shims
# would write into HOME.
isolated() (
  export HOME="$work/home" TMPDIR="$work/tmp" PATH="/usr/bin:/bin:$PATH"
  "$@"
)

reviewer_ok='{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'

# full_two_candidate_reviewer_run, isolation_writes_only_record
scenario "$reviewer_ok"
mkdir -p "$work/home" "$work/tmp"
touch "$work/home/marker"
rec="$work/v2-full"
isolated prepare "$rec" reviewer 100 a=model:fakep/m1#high b=model:fakep/m2#high \
  || fail "prepare failed"
assert_file "$rec/protocol.json"
assert_file "$rec/catalog-snapshot.json"
assert_file "$rec/freeze-manifest.json"
assert_eq '"AWAITING_APPROVAL"' "$(jq -c .status_at_freeze "$rec/protocol.json")"
assert_eq "\"v2-full-$(date -u +%Y%m%d)\"" "$(jq -c .experiment_id "$rec/protocol.json")"
assert_eq '"APPROVED_FOR_DISPATCH"' "$(jq -c .status "$rec.approval")"
assert_eq "$(sha256sum "$rec/freeze-manifest.json" | cut -d' ' -f1)" "$(jq -r .freeze_manifest_sha256 "$rec.approval")"
assert_eq '["a","b"]' "$(jq -c '[.candidates[].key]' "$rec/protocol.json")"
assert_eq '"screening-reviewer@fakep/m1#high"' "$(jq -c '.candidates[0].expect' "$rec/protocol.json")"
assert_eq '"candidate_b"' "$(jq -c '.candidates[1].account' "$rec/protocol.json")"
assert_eq 50 "$(jq '.budget.per_candidate_cap' "$rec/protocol.json")"
assert_eq "$(sha256sum "$work/creds.json" | cut -d' ' -f1)" "$(jq -r .credentials_sha256 "$rec/protocol.json")"
assert_eq '[{"input":1,"output":2}]' "$(jq -c '.models["fakep/m1"].cost' "$rec/catalog-snapshot.json")"
assert_eq '"models/routing/opencode/v2/.opencode"' "$(jq -c .opencode_dir "$rec/protocol.json")"
assert_eq '["declared","declared"]' "$(jq -c '[.candidates[].pricing]' "$rec/protocol.json")"
assert_eq '[]' "$(jq -c .provider_priced "$rec/protocol.json")"
for p in record:protocol.json record:catalog-snapshot.json \
    models/routing/opencode/v2/.opencode/model-routing.md \
    models/routing/opencode/v2/.opencode/agents/reviewer.md \
    models/routing/opencode/eval/runtime/opencode-v2-adapter/roles/reviewer.json \
    models/routing/opencode/eval/runtime/opencode-v2-adapter/run-screening.sh \
    models/routing/opencode/eval/runtime/opencode-v2-adapter/v2config.py \
    models/routing/opencode/eval/scoring/reviewer-v2.py \
    models/routing/opencode/eval/fixtures/reviewer-seeded-defects-v2/oracle.json; do
  jq -e --arg p "$p" 'any(.files[]; .path == $p)' "$rec/freeze-manifest.json" >/dev/null \
    || fail "the freeze manifest does not cover $p"
done
[[ ! -e "$rec/.work" ]] || fail "prepare left .work behind"
approve "$rec"
rc=0
isolated dispatch "$rec" || rc=$?
assert_eq 0 "$rc"
assert_eq 2 "$(find "$rec/capability" -mindepth 1 -maxdepth 1 -type d | wc -l)"
assert_eq 12 "$(find "$rec/runs" -mindepth 1 -maxdepth 1 -type d | wc -l)"
assert_eq '"COMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_file "$rec/runs/01-clean-r1-a/reported.json"
assert_file "$rec/runs/02-clean-r1-b/reported.json"
# (rep + workload_index) % 2 alternates the order: the second workload starts with b.
assert_dir "$rec/runs/03-R-CONCURRENCY-r1-b"
assert_dir "$rec/runs/04-R-CONCURRENCY-r1-a"
while IFS= read -r d; do
  jq -e '.routing_observed == [.routing_expected]' "$d" >/dev/null || fail "routing differs in $d"
done < <(find "$rec" -name dispatch.json)
assert_eq 14 "$(find "$rec" -name dispatch.json | wc -l)"
isolated bash "$runner" score --out "$rec" >/dev/null || fail "score failed"
assert_file "$rec/scores/a-r1.json"
assert_file "$rec/scores/b-r1.json"
assert_file "$rec/findings-a-r1.json"
assert_contains "$(<"$rec/result.md")" "Operator: not yet adjudicated"
for h in Protocol Candidates Spend Capability Scores Adjudication; do
  grep -q "^## $h" "$rec/result.md" || fail "result.md has no $h heading"
done
[[ ! -e "$rec/adjudication.json" ]] || fail "score wrote adjudication.json"
# result_names_missing_runs: each reviewer candidate-run shows its missing_runs.
assert_contains "$(grep '^| a | 1 |' "$rec/result.md")" "missing_runs=0"
# score_checks_the_approval: a rewritten manifest whose entries still verify.
cp "$rec/freeze-manifest.json" "$work/manifest.keep"
jq -c . "$work/manifest.keep" >"$rec/freeze-manifest.json"
rc=0
bash "$runner" score --out "$rec" >/dev/null 2>"$work/score.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$work/score.err")" "approval.json"
cp "$work/manifest.keep" "$rec/freeze-manifest.json"
assert_eq marker "$(ls -A "$work/home")"
assert_eq '' "$(ls -A "$work/tmp")"
[[ ! -e "$rec/.work" ]] || fail ".work survived"
while IFS= read -r p; do
  [[ "$p" == "$rec/.work/"* ]] || fail "the fake ran outside the record's .work: $p"
done < <(grep -o '\(home\|cwd\|xdg_config\)=[^ ]*' "$state/log" | cut -d= -f2-)

# no_credential_in_record (a full run)
no_secret_in "$rec"

# stale_work_removed, then dispatch_twice_refused: an abnormal end left .work
# behind; the refused dispatch removes it first, stopping only a recorded pid
# that is a server of that sandbox.
stale="$rec/.work/sandbox.A"
mkdir -p "$stale/data/opencode" "$stale/work" "$rec/.work/sandbox.B"
printf '{"fakep":{"type":"api","key":"tok-SECRET-123"}}\n' >"$stale/data/opencode/auth.json"
(cd "$stale/work" && exec sleep 300) </dev/null >/dev/null 2>&1 &
ours=$!
sleep 300 >/dev/null 2>&1 &
other=$!
extra_pids+=("$ours" "$other")
printf '%s\n' "$ours" >"$stale/pid"
printf '%s\n' "$other" >"$rec/.work/sandbox.B/pid"
before=$(find "$rec/runs" -type f -printf '%p %T@\n' | sort)
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
assert_eq "$before" "$(find "$rec/runs" -type f -printf '%p %T@\n' | sort)"
[[ ! -e "$rec/.work" ]] || fail "a refused dispatch left the stale .work"
gone "$ours" || fail "the stale sandbox's server $ours survived"
kill -0 "$other" 2>/dev/null || fail "a pid that is not a sandbox server ($other) was stopped"
kill -s KILL "$other" 2>/dev/null || true
wait "$ours" "$other" 2>/dev/null || true

# approval_mismatch_refuses, then capability_failure_stops_candidate
scenario '{"screening-reviewer@fakep/m2#high":{"probe":{"exit":1,"error_message":"Model not found"}},
  "screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'
rec="$work/v2-capfail"
prepare "$rec" reviewer 100 a=model:fakep/m1#high b=model:fakep/m2#high || fail "prepare failed"
jq '.approved_ceiling_credits += 1' "$rec.approval" >"$rec/approval.json"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 3 "$rc"
[[ ! -e "$rec/runs" && ! -e "$rec/capability" ]] || fail "a refused dispatch wrote runs"
approve "$rec"
rc=0
dispatch "$rec" || rc=$?
assert_eq 0 "$rc"
assert_eq '' "$(find "$rec/runs" -mindepth 1 -maxdepth 1 -name '*-b')"
assert_eq 6 "$(find "$rec/runs" -mindepth 1 -maxdepth 1 -name '*-a' | wc -l)"
assert_eq '"STOPPED_CAPABILITY"' "$(jq -c .stopped.b "$rec/status.json")"
no_secret_in "$rec"
# The stopped candidate cannot be scored; score says so and goes on. A stale
# .work is removed first.
mkdir -p "$rec/.work/sandbox.C/data/opencode"
bash "$runner" score --out "$rec" >/dev/null 2>"$work/score.err" || fail "score failed: $(<"$work/score.err")"
[[ ! -e "$rec/.work" ]] || fail "score left the stale .work"
assert_contains "$(<"$work/score.err")" "stale scratch area"
assert_contains "$(<"$rec/result.md")" "NOT_SCORABLE"
assert_file "$rec/scores/a-r1.json"

# budget_stop_halts_screening
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.5,"steps":10,"step_sleep":0.2,
  "probe":{"text":"CAPABILITY_OK","cost_per_step":0,"steps":1,"step_sleep":0}}}'
rec="$work/v2-budget"
prepare "$rec" reviewer 30 a=model:fakep/m1#high b=model:fakep/m2#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"INCOMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_eq 01-clean-r1-a "$(ls "$rec/runs")"
assert_eq '"BUDGET_STOP"' "$(jq -c .classification "$rec/runs/01-clean-r1-a/dispatch/dispatch.json")"

# score_refuses_a_frozen_mismatch: a record file changed after dispatch.
printf '\n' >>"$rec/catalog-snapshot.json"
rc=0
bash "$runner" score --out "$rec" >/dev/null 2>"$work/score.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$work/score.err")" "freeze digest mismatch: record:catalog-snapshot.json"
[[ ! -e "$rec/result.md" && ! -e "$rec/scores" ]] || fail "score wrote output for a mismatched record"

# unknown_cost_halts_screening: a step_start with no reported cost.
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":null,
  "probe":{"text":"CAPABILITY_OK","cost_per_step":0}}}'
rec="$work/v2-unknown"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"INCOMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_eq '"UNKNOWN_COST"' "$(jq -c .halted.reason "$rec/status.json")"
assert_eq 01-clean-r1-a "$(ls "$rec/runs")"

# credential_exposed_halts: model text echoing the credential, in a run and in
# a probe, is redacted in place and halts the screening.
for where in run probe; do
  if [[ "$where" == run ]]; then
    scenario '{"screening-reviewer":{"text":"the key is tok-SECRET-123","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'
  else
    scenario '{"screening-reviewer":{"text":"x","cost_per_step":0.01,"probe":{"text":"tok-SECRET-123"}}}'
  fi
  rec="$work/v2-exposed-$where"
  prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
  approve "$rec"
  rc=0
  bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
    2>"$work/exposed.err" || rc=$?
  assert_eq 1 "$rc"
  assert_eq '"INCOMPLETE"' "$(jq -c .state "$rec/status.json")"
  assert_eq '"CREDENTIAL_EXPOSED"' "$(jq -c .halted.reason "$rec/status.json")"
  ! grep -q tok-SECRET-123 "$work/exposed.err" || fail "the scan printed the credential"
  no_secret_in "$rec"
  if [[ "$where" == run ]]; then
    d="$rec/runs/01-clean-r1-a/dispatch"
    assert_eq 01-clean-r1-a "$(ls "$rec/runs")"
  else
    d="$rec/capability/a/dispatch"
    assert_eq '' "$(ls -A "$rec/runs")"
  fi
  assert_eq '"CREDENTIAL_EXPOSED"' "$(jq -c .classification "$d/dispatch.json")"
  grep -q '\[REDACTED\]' "$d/raw.jsonl" || fail "no redaction marker in $d/raw.jsonl"
done

# incomplete_cost_halts: a call cut off mid-step ledgers its finished steps and
# halts the screening; result.md marks the total a lower bound.
scenario '{"screening-reviewer":{"steps":3,"partial":true,"exit":1,"error_message":"socket closed unexpectedly",
  "cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK","steps":1,"partial":false,"exit":0}}}'
rec="$work/v2-partial"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"INCOMPLETE_COST"' "$(jq -c .halted.reason "$rec/status.json")"
assert_eq '"INCOMPLETE_COST"' "$(jq -c .stopped.a "$rec/status.json")"
d="$rec/runs/01-clean-r1-a/dispatch/dispatch.json"
assert_eq 1 "$(jq .unfinished_steps "$d")"
assert_eq false "$(jq .cost_complete "$d")"
assert_eq true "$(jq .cost_complete "$rec/capability/a/dispatch/dispatch.json")"
assert_eq true "$(jq '([.entries[] | select(.label == "01-clean-r1-a") | .credits] | add) == 2' "$rec/ledger.json")"
bash "$runner" score --out "$rec" >/dev/null 2>&1 || true
assert_contains "$(<"$rec/result.md")" "(lower bound)"

# all_candidates_stopped_halts: no live candidate after the probes.
scenario '{"screening-reviewer":{"exit":1,"error_message":"Model not found"}}'
rec="$work/v2-nolive"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"INCOMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_eq '"NO_LIVE_CANDIDATE"' "$(jq -c .halted.reason "$rec/status.json")"
assert_eq '"STOPPED_CAPABILITY"' "$(jq -c .stopped.a "$rec/status.json")"
assert_eq '' "$(ls -A "$rec/runs")"

# probe_invalid_environment_halts
scenario '{"screening-reviewer":{"exit":1,"error_message":"socket closed unexpectedly"}}'
rec="$work/v2-invalid"
prepare "$rec" reviewer 100 a=model:fakep/m1#high b=model:fakep/m2#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"INVALID_ENVIRONMENT"' "$(jq -c .classification "$rec/capability/a/probe.json")"
assert_eq '"INVALID_ENVIRONMENT"' "$(jq -c .halted.reason "$rec/status.json")"
[[ ! -e "$rec/capability/b" ]] || fail "the screening went on after an invalid environment"

# runtime_version_change_refuses: the runtime is not the one prepare measured.
scenario "$reviewer_ok"
rec="$work/v2-version"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
printf '2.4.0-fake\n' >"$state/version"
rc=0
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
  2>"$work/version.err" || rc=$?
rm -f "$state/version"
assert_eq 3 "$rc"
assert_contains "$(<"$work/version.err")" "2.4.0-fake"
[[ ! -e "$rec/runs" && ! -e "$rec/capability" && ! -e "$rec/status.json" && ! -e "$rec/.work" ]] \
  || fail "a refused runtime wrote dispatch output"

# record_path_with_ampersand: placeholders expand literally.
scenario "$reviewer_ok"
rec="$work/a&b/v2-amp"
mkdir -p "$work/a&b"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
dispatch "$rec" || fail "dispatch failed"
bash "$runner" score --out "$rec" >/dev/null 2>"$work/score.err" || fail "score failed: $(<"$work/score.err")"
assert_file "$rec/findings-a-r1.json"
assert_file "$rec/scores/a-r1.json"

# freeze_mismatch_refuses
scenario "$reviewer_ok"
rec="$work/v2-freeze"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
printf '\n' >>"$rec/protocol.json"
rc=0
dispatch "$rec" 2>"$work/freeze.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$work/freeze.err")" "freeze digest mismatch: record:protocol.json"
[[ ! -e "$rec/runs" ]] || fail "a freeze mismatch wrote runs"

# prepare_refuses_unpriced_and_unknown
runs_before=$(log_count run)
for spec in model:fakep/m3#high model:fakep/m1#ultra model:fakep/zz#high; do
  rc=0
  prepare "$work/v2-refused" reviewer 100 "a=$spec" 2>/dev/null || rc=$?
  assert_eq 1 "$rc"
  [[ ! -e "$work/v2-refused" ]] || fail "a refused prepare left its record behind ($spec)"
done
assert_eq "$runs_before" "$(log_count run)"

# prepare_still_refuses_other_unpriced: --provider-priced names another
# provider, so the unpriced m3 is still refused, with no model call; a bad
# PROVIDER is a usage error.
runs_before=$(log_count run)
rc=0
quiet bash "$runner" prepare --role reviewer --out "$work/v2-refused" --candidate a=model:fakep/m3#high \
  --provider-priced other --runs 1 --budget 100 --providers "$work/fragment.json" \
  --credentials "$work/creds.json" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
[[ ! -e "$work/v2-refused" ]] || fail "a refused prepare left its record behind (--provider-priced other)"
assert_eq "$runs_before" "$(log_count run)"
for bad in 'fake/p' 'fake#p' '' $'junk\nfakep' 'fake p' $'fake\tp'; do
  rc=0
  bash "$runner" prepare --role reviewer --out "$work/v2-refused" --candidate a=model:fakep/m3#high \
    --provider-priced "$bad" --runs 1 --budget 100 --providers "$work/fragment.json" \
    --credentials "$work/creds.json" >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc"
  [[ ! -e "$work/v2-refused" ]] || fail "a usage error left a record behind ($bad)"
done

# prepare_accepts_provider_priced: an unpriced model whose provider reports
# cost per call is screened with provider_reported pricing.
# pp_prepare OUT CANDIDATE...: prepare with --provider-priced fakep.
pp_prepare() {
  local out=$1 c args=()
  shift
  for c in "$@"; do args+=(--candidate "$c"); done
  quiet bash "$runner" prepare --role reviewer --out "$out" "${args[@]}" --provider-priced fakep \
    --provider-priced fakep --runs 1 --budget 100 --providers "$work/fragment.json" \
    --credentials "$work/creds.json" >"$out.approval"
}
scenario "$reviewer_ok"
rec="$work/v2-pp-prepare"
pp_prepare "$rec" a=model:fakep/m3#high b=model:fakep/m1#high || fail "provider-priced prepare failed"
assert_eq '["provider_reported","declared"]' "$(jq -c '[.candidates[].pricing]' "$rec/protocol.json")"
assert_eq '["fakep"]' "$(jq -c .provider_priced "$rec/protocol.json")"
# The approval-time notice names the provider_reported candidates only.
assert_eq 1 "$(grep -c 'the budget cap acts only on cost these providers report' "$work/stderr")"
assert_contains "$(grep 'the budget cap acts only' "$work/stderr")" "a (fakep/m3)"
[[ "$(grep 'the budget cap acts only' "$work/stderr")" != *"b (fakep/m1)"* ]] \
  || fail "the notice names a declared candidate"

# provider_priced_unknown_cost_first: a provider-priced call that started a
# step and reported no cost at all is UNKNOWN_COST, checked before UNREPORTED_COST.
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":null,
  "probe":{"text":"CAPABILITY_OK","cost_per_step":0.01}}}'
rec="$work/v2-pp-unknown"
pp_prepare "$rec" a=model:fakep/m3#high || fail "provider-priced prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"UNKNOWN_COST"' "$(jq -c .halted.reason "$rec/status.json")"
assert_eq '"UNKNOWN_COST"' "$(jq -c .stopped.a "$rec/status.json")"
assert_eq 01-clean-r1-a "$(ls "$rec/runs")"

# provider_priced_zero_cost_halts: a provider-priced call that started steps
# and reported no cost halts the screening, in a run and in a probe.
for where in run probe; do
  if [[ "$where" == run ]]; then
    scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0,"steps":2,
      "probe":{"text":"CAPABILITY_OK","cost_per_step":0.01}}}'
  else
    scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,
      "probe":{"text":"CAPABILITY_OK","cost_per_step":0}}}'
  fi
  rec="$work/v2-pp-zero-$where"
  pp_prepare "$rec" a=model:fakep/m3#high || fail "provider-priced prepare failed"
  approve "$rec"
  rc=0
  dispatch "$rec" 2>/dev/null || rc=$?
  assert_eq 1 "$rc"
  assert_eq '"INCOMPLETE"' "$(jq -c .state "$rec/status.json")"
  assert_eq '"UNREPORTED_COST"' "$(jq -c .halted.reason "$rec/status.json")"
  assert_eq '"UNREPORTED_COST"' "$(jq -c .stopped.a "$rec/status.json")"
  if [[ "$where" == run ]]; then
    assert_eq '"01-clean-r1-a"' "$(jq -c .halted.label "$rec/status.json")"
    assert_eq 01-clean-r1-a "$(ls "$rec/runs")"
  else
    assert_eq '"capability-a"' "$(jq -c .halted.label "$rec/status.json")"
    assert_eq '' "$(ls -A "$rec/runs")"
  fi
done

# provider_priced_reported_cost_completes: the provider reports a cost, so the
# screening completes and the ledger holds the provider's figure.
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'
rec="$work/v2-pp-priced"
pp_prepare "$rec" a=model:fakep/m3#high || fail "provider-priced prepare failed"
approve "$rec"
rc=0
dispatch "$rec" || rc=$?
assert_eq 0 "$rc"
assert_eq '"COMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_eq true "$(jq '([.entries[].credits] | add) > 0' "$rec/ledger.json")"
bash "$runner" score --out "$rec" >/dev/null 2>&1 || fail "score failed"
grep -q '^| Key | Spec | Expected use | Pricing | Stopped |' "$rec/result.md" || fail "result.md has no Pricing column"
assert_contains "$(grep '^| a | `model:' "$rec/result.md")" "| provider_reported | no |"
no_secret_in "$rec"

# usage refusals: an existing record, a name without v2-, a duplicate key
rc=0; prepare "$work/v2-full" reviewer 100 a=model:fakep/m1#high 2>/dev/null || rc=$?; assert_eq 2 "$rc"
rc=0; prepare "$work/plain" reviewer 100 a=model:fakep/m1#high 2>/dev/null || rc=$?; assert_eq 2 "$rc"
rc=0; prepare "$work/v2-dup" reviewer 100 a=model:fakep/m1#high a=model:fakep/m2#high 2>/dev/null || rc=$?
assert_eq 2 "$rc"
rc=0; prepare "$work/v2-agent" reviewer 100 a=agent:build 2>/dev/null || rc=$?; assert_eq 2 "$rc"

# interrupt_cleans_up
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"steps":20,"step_sleep":0.5}}'
rec="$work/v2-interrupt"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
runs=$(log_count run)
# The runner itself, not a function wrapping it, so that the TERM reaches it.
# It is stopped during a call: the first server it starts is the runtime check's.
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" 2>/dev/null &
runner_pid=$!
for _ in $(seq 1 200); do
  (( $(log_count run) > runs )) && break
  sleep 0.1
done
(( $(log_count run) > runs )) || fail "the dispatch never started a call"
kill -s TERM "$runner_pid"
rc=0
wait "$runner_pid" || rc=$?
runner_pid=''
(( rc != 0 )) || fail "an interrupted runner exited 0"
while IFS= read -r p; do
  ! kill -0 "$p" 2>/dev/null || fail "process $p survived the interrupt"
done < <(sed -n 's/^\(serve\|run\) pid=\([0-9]*\) .*/\2/p' "$state/log")
[[ ! -e "$rec/.work" ]] || fail ".work survived the interrupt"
assert_eq '"INTERRUPTED"' "$(jq -c .halted.reason "$rec/status.json")"

# record_lock_refuses_a_second_runner: score and a second dispatch on a record
# whose dispatch is running exit 2 and touch nothing; the live run completes.
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"steps":2,"step_sleep":0.4,
  "probe":{"text":"CAPABILITY_OK"}}}'
rec="$work/v2-locked"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
runs=$(log_count run)
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" 2>/dev/null &
runner_pid=$!
for _ in $(seq 1 200); do
  (( $(log_count run) > runs )) && break
  sleep 0.1
done
(( $(log_count run) > runs )) || fail "the dispatch never started a call"
rc=0
bash "$runner" score --out "$rec" >/dev/null 2>"$work/lock.err" || rc=$?
assert_eq 2 "$rc"
assert_contains "$(<"$work/lock.err")" "another runner holds this record"
rc=0
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
  2>"$work/lock.err" || rc=$?
assert_eq 2 "$rc"
assert_contains "$(<"$work/lock.err")" "another runner holds this record"
rc=0
wait "$runner_pid" || rc=$?
runner_pid=''
assert_eq 0 "$rc"
assert_eq '"COMPLETE"' "$(jq -c .state "$rec/status.json")"
assert_eq 6 "$(find "$rec/runs" -mindepth 1 -maxdepth 1 -type d | wc -l)"
assert_eq 600 "$(stat -c %a "$rec/.lock")"

# orphan_after_sigkill: a runner killed with SIGKILL mid-call leaves its call's
# session, server and .work behind, but not the lock; score takes it, stops the
# orphaned server by its recorded pid and removes .work.
scenario '{"screening-reviewer":{"text":"{\"findings\":[]}","cost_per_step":0.01,"steps":40,"step_sleep":0.5}}'
rec="$work/v2-orphan"
prepare "$rec" reviewer 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
runs=$(log_count run)
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" 2>/dev/null &
runner_pid=$!
for _ in $(seq 1 200); do
  (( $(log_count run) > runs )) && break
  sleep 0.1
done
(( $(log_count run) > runs )) || fail "the dispatch never started a call"
server=$(sed -n 's/^serve pid=\([0-9]*\) .*/\1/p' "$state/log" | tail -n 1)
client=$(sed -n 's/^run pid=\([0-9]*\) .*/\1/p' "$state/log" | tail -n 1)
orphan_session=$(ps -o sid= -p "$client" | tr -d ' ')
[[ "$orphan_session" =~ ^[1-9][0-9]*$ ]] || fail "no session for the call's client"
kill -s KILL "$runner_pid"
wait "$runner_pid" 2>/dev/null || true
runner_pid=''
kill -0 "$server" 2>/dev/null || fail "the orphaned server is already gone; the test proves nothing"
flock -n "$rec/.lock" true || fail "a survivor of the SIGKILL still holds the record's lock"
rc=0
bash "$runner" score --out "$rec" >/dev/null 2>"$work/orphan.err" || rc=$?
assert_eq 2 "$rc"
assert_contains "$(<"$work/orphan.err")" "stale scratch area"
[[ "$(<"$work/orphan.err")" != *"another runner"* ]] || fail "an orphan kept the record locked"
[[ ! -e "$rec/.work" ]] || fail ".work survived the orphan cleanup"
gone "$server" || fail "the orphaned server $server survived"
kill -s KILL -- "-$orphan_session" 2>/dev/null || true
orphan_session=''

# build_binary_credential_never_encoded: a binary file holding the credential
# is redacted before the patch is taken, so not even the decoded patch has it.
scenario '{"screening-build":{"text":"done","cost_per_step":0.01,
  "write_binary":{"path":"data.bin","text":"tok-SECRET-123"},
  "probe":{"text":"CAPABILITY_OK","write_binary":null}}}'
rec="$work/v2-binary"
prepare "$rec" build 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 1 "$rc"
assert_eq '"CREDENTIAL_EXPOSED"' "$(jq -c .halted.reason "$rec/status.json")"
no_secret_in "$rec"
patch=$(find "$rec/runs" -name work-product.patch)
[[ -n "$patch" ]] || fail "no work-product.patch for the exposed run"
assert_contains "$(<"$patch")" "GIT binary patch"
mkdir -p "$work/applied"
cp -a "$root/records/astra-build-followup/base-snapshot/." "$work/applied/"
(cd "$work/applied" && git apply "$patch") || fail "the work-product patch does not apply"
grep -q 'REDACTED' "$work/applied/data.bin" || fail "the patch does not carry the redacted file"
! grep -rqa tok-SECRET-123 "$work/applied" || fail "the decoded patch holds the credential"

# build_role_captures_patch
scenario '{"screening-build":{"text":"done","cost_per_step":0.01,
  "write_file":{"path":"lib/strings.sh","content":"changed\n"},
  "probe":{"text":"CAPABILITY_OK","write_file":null}}}'
rec="$work/v2-build"
prepare "$rec" build 100 a=model:fakep/m1#high || fail "prepare failed"
for p in models/routing/opencode/eval/records/astra-build-followup/oracle.sh \
    models/routing/opencode/eval/records/sol-build/empty-path-check.sh; do
  jq -e --arg p "$p" 'any(.files[]; .path == $p)' "$rec/freeze-manifest.json" >/dev/null \
    || fail "the build freeze manifest does not cover $p"
done
approve "$rec"
dispatch "$rec" || fail "build dispatch failed"
patch=$(find "$rec/runs" -path '*-gate-r1-a/work-product.patch')
[[ -n "$patch" ]] || fail "no work-product.patch for the gate run"
assert_contains "$(<"$patch")" "lib/strings.sh"
assert_file "$(find "$rec/runs" -maxdepth 1 -name '*-coding-r1-a')/work-product.patch"
# record_scorer_failure_surfaces: the build scorer refuses an existing output.
mkdir "$rec/post-run-diagnostic"
rc=0
bash "$runner" score --out "$rec" >/dev/null 2>"$work/score.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$work/score.err")" "SCORE_FAILED"
assert_contains "$(<"$rec/result.md")" "SCORE_FAILED"
assert_contains "$(<"$rec/result.md")" "scores/build-quality.json"
[[ "$(<"$rec/result.md")" != *"no per-run score file"* ]] || fail "result.md misnames the build score"

# agent_candidate_uses_profile
cat >"$work/profile.jsonc" <<'EOF'
{
  // a profile under test
  "$schema": "https://opencode.ai/config.json",
  "agents": {"build": {"mode": "primary", "model": {"providerID": "fakep", "model": "m2", "variant": "high"}}}
}
EOF
scenario '{"build":{"text":"done","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'
rec="$work/v2-agent"
cp -r "$root/../v2/.opencode" "$work/ocdir"
quiet bash "$runner" prepare --role build --out "$rec" --candidate p=agent:build --runs 1 --budget 100 \
  --providers "$work/fragment.json" --credentials "$work/creds.json" --opencode-dir "$work/ocdir" \
  --profile "$work/profile.jsonc" --profile-id prof-7 >"$rec.approval" || fail "agent prepare failed"
# An --opencode-dir outside the toolkit is frozen as the record's own copy.
assert_eq "\"$work/ocdir\"" "$(jq -c .opencode_dir "$rec/protocol.json")"
jq -e 'any(.files[]; .path == "record:opencode-dir/model-routing.md")' "$rec/freeze-manifest.json" >/dev/null \
  || fail "the outside --opencode-dir is not frozen"
assert_eq '"build@fakep/m2#high"' "$(jq -c '.candidates[0].expect' "$rec/protocol.json")"
assert_eq "$(sha256sum "$work/profile.jsonc" | cut -d' ' -f1)" "$(jq -r .profile_digest "$rec/protocol.json")"
approve "$rec"
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 3 "$rc"
quiet bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile.jsonc" || fail "agent dispatch failed"
d=$(find "$rec/runs" -path '*-gate-r1-p/dispatch/dispatch.json')
assert_eq '"prof-7"' "$(jq -c .routing_profile_id "$d")"
assert_eq '["build@fakep/m2#high"]' "$(jq -c .routing_observed "$d")"
no_secret_in "$rec"

# agent_candidate_expect_frozen: dispatch checks the routing prepare resolved,
# not what the agent resolves to at dispatch time.
rec="$work/v2-agent2"
quiet bash "$runner" prepare --role build --out "$rec" --candidate p=agent:build --runs 1 --budget 100 \
  --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile.jsonc" --profile-id prof-7 >"$rec.approval" || fail "agent prepare failed"
approve "$rec"
printf '{"id":"m1","providerID":"fakep","variant":"high"}\n' >"$state/agent-model.json"
rc=0
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile.jsonc" 2>/dev/null || rc=$?
rm -f "$state/agent-model.json"
assert_eq 1 "$rc"
d="$rec/capability/p/dispatch/dispatch.json"
assert_eq '"build@fakep/m2#high"' "$(jq -c .routing_expected "$d")"
assert_eq '"ROUTING_MISMATCH"' "$(jq -c .classification "$d")"

# every_sandbox_switches_off_title_generation: each serve of a full dispatch
# (runtime check, probes, runs; a model and an agent candidate) logged
# agents.title.disabled true, and a profile's own title row keeps its other keys.
cat >"$work/profile-title.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "agents": {
    "build": {"mode": "primary", "model": {"providerID": "fakep", "model": "m2", "variant": "high"}},
    "title": {"mode": "subagent", "disabled": false}
  }
}
EOF
scenario '{"build":{"text":"done","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}},
  "screening-build":{"text":"done","cost_per_step":0.01,"probe":{"text":"CAPABILITY_OK"}}}'
rec="$work/v2-title"
: >"$state/log"
quiet bash "$runner" prepare --role build --out "$rec" --candidate p=agent:build --candidate q=model:fakep/m1#high \
  --runs 1 --budget 100 --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile-title.jsonc" --profile-id prof-t >"$rec.approval" || fail "title prepare failed"
# prepare's catalog server, built from the profile.
assert_eq 1 "$(grep -c '^serve pid=' "$state/log" || true)"
assert_eq 1 "$(grep -c '^serve-title disabled=true keys=disabled,mode$' "$state/log" || true)"
approve "$rec"
: >"$state/log"
quiet bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile-title.jsonc" || fail "title dispatch failed"
# Two workloads. Runtime check + the agent's probe and two runs carry the
# profile's title row; the model candidate's probe and two runs only the flag.
assert_eq 7 "$(grep -c '^serve pid=' "$state/log" || true)"
assert_eq 4 "$(grep -c '^serve-title disabled=true keys=disabled,mode$' "$state/log" || true)"
assert_eq 3 "$(grep -c '^serve-title disabled=true keys=disabled$' "$state/log" || true)"

printf 'PASS: v2-screening-runner\n'
