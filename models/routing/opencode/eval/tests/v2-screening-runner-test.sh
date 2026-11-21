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
# Every pid a fake logged, and a runner left running; stopped by pid only.
cleanup() {
  local p
  [[ -z "$runner_pid" ]] || kill -s KILL "$runner_pid" 2>/dev/null || true
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
for p in record:protocol.json record:catalog-snapshot.json \
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
assert_eq marker "$(ls -A "$work/home")"
assert_eq '' "$(ls -A "$work/tmp")"
[[ ! -e "$rec/.work" ]] || fail ".work survived"
while IFS= read -r p; do
  [[ "$p" == "$rec/.work/"* ]] || fail "the fake ran outside the record's .work: $p"
done < <(grep -o '\(home\|cwd\|xdg_config\)=[^ ]*' "$state/log" | cut -d= -f2-)

# no_credential_in_record (a full run)
no_secret_in "$rec"

# dispatch_twice_refused
before=$(find "$rec/runs" -type f -printf '%p %T@\n' | sort)
rc=0
dispatch "$rec" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
assert_eq "$before" "$(find "$rec/runs" -type f -printf '%p %T@\n' | sort)"

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
# The stopped candidate cannot be scored; score says so and goes on.
bash "$runner" score --out "$rec" >/dev/null || fail "score failed"
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
serves=$(log_count serve)
# The runner itself, not a function wrapping it, so that the TERM reaches it.
bash "$runner" dispatch --out "$rec" --providers "$work/fragment.json" --credentials "$work/creds.json" 2>/dev/null &
runner_pid=$!
for _ in $(seq 1 200); do
  (( $(log_count serve) > serves )) && break
  sleep 0.1
done
(( $(log_count serve) > serves )) || fail "the dispatch never started a server"
kill -s TERM "$runner_pid"
rc=0
wait "$runner_pid" || rc=$?
runner_pid=''
(( rc != 0 )) || fail "an interrupted runner exited 0"
while IFS= read -r p; do
  ! kill -0 "$p" 2>/dev/null || fail "process $p survived the interrupt"
done < <(sed -n 's/^\(serve\|run\) pid=\([0-9]*\) .*/\2/p' "$state/log")
[[ ! -e "$rec/.work" ]] || fail ".work survived the interrupt"

# build_role_captures_patch
scenario '{"screening-build":{"text":"done","cost_per_step":0.01,
  "write_file":{"path":"lib/strings.sh","content":"changed\n"},
  "probe":{"text":"CAPABILITY_OK","write_file":null}}}'
rec="$work/v2-build"
prepare "$rec" build 100 a=model:fakep/m1#high || fail "prepare failed"
approve "$rec"
dispatch "$rec" || fail "build dispatch failed"
patch=$(find "$rec/runs" -path '*-gate-r1-a/work-product.patch')
[[ -n "$patch" ]] || fail "no work-product.patch for the gate run"
assert_contains "$(<"$patch")" "lib/strings.sh"
assert_file "$(find "$rec/runs" -maxdepth 1 -name '*-coding-r1-a')/work-product.patch"

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
quiet bash "$runner" prepare --role build --out "$rec" --candidate p=agent:build --runs 1 --budget 100 \
  --providers "$work/fragment.json" --credentials "$work/creds.json" \
  --profile "$work/profile.jsonc" --profile-id prof-7 >"$rec.approval" || fail "agent prepare failed"
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

printf 'PASS: v2-screening-runner\n'
