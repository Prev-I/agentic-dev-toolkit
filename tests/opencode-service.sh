#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CONSUMER="$REPOSITORY_ROOT/opencode-service/opencode-gateway-restart.sh"
readonly READY="$REPOSITORY_ROOT/opencode-service/opencode-startup-ready.sh"
readonly TELEGRAM_READY="$REPOSITORY_ROOT/opencode-service/opencode-telegram-ready.sh"

cleanup() {
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT

# The helpers are duplicated from tests/install.sh rather than factored into a
# shared library, for the same reason the policy suite duplicates them: the root
# test directory has no such library, and adding one would mean rewriting the
# other suites.
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$message: '$needle' not found in '$haystack'"
}

# `systemctl`, `journalctl` and `curl` are replaced on PATH, so the suite exercises
# the real decision logic without a systemd user manager or a server. Each stub reports
# what it was asked to do through files the assertions read, because a stub that
# only fakes a return value cannot show that a restart was *not* attempted.
install_stubs() {
  mkdir -p "$TEMP_DIR/bin"

  cat > "$TEMP_DIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
for argument in "$@"; do
  if [[ "$argument" == "restart" ]]; then
    printf 'restart\n' >> "$STUB_DIR/restarts"
    if [[ -n "${STUB_RESTART_OUTPUT:-}" ]]; then
      printf '%s\n' "$STUB_RESTART_OUTPUT" >&2      # systemctl reports on stderr
    fi
    exit "${STUB_RESTART_STATUS:-0}"
  fi
done
printf '%s\n' "${STUB_ACTIVE_STATE:-active}"
STUB

  # The curl stub routes by the URL in the `-K -` option block, like the real
  # scripts send it. A request without a `user =` line is unauthenticated. When
  # the block asks for `write-out`, the stub appends "\n<http code>" as curl
  # would, so the scripts under test can tell a 401 from a 200 from a network
  # failure (STUB_CURL_STATUS, which makes curl exit non-zero instead).
  cat > "$TEMP_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
options="$(cat)"                    # drain and inspect the -K - option block
exit_status="${STUB_CURL_STATUS:-0}"
[[ "$exit_status" == "0" ]] || exit "$exit_status"

url="$(sed -n 's/^url = "\(.*\)"$/\1/p' <<<"$options")"
path="/${url#http://*/}"
authenticated=0
if [[ "$options" == *'user = "'* ]]; then
  authenticated=1
  if [[ "${STUB_REQUIRE_AUTH:-0}" == "1" &&
        "$options" != *'user = "opencode:test-password"'* ]]; then
    authenticated=0
  fi
fi

code=200
body=""
case "$path" in
  /api/info)
    if (( authenticated )); then
      code="${STUB_INFO_CODE:-200}"
      if [[ -n "${STUB_INFO_BODY+x}" ]]; then
        body="$STUB_INFO_BODY"
      else
        body="$(printf '{"version":"%s","pid":%s,"hostname":"h","urls":["http://127.0.0.1:4096"],"paths":{"tmp":"/tmp/opencode"},"capabilities":{"persistentPty":true}}' \
          "${STUB_INFO_VERSION:-2.3.0}" "${STUB_INFO_PID:-1327923}")"
      fi
    else
      code="${STUB_INFO_UNAUTH_CODE:-401}"
    fi
    ;;
  /api/experimental/migration/v1)
    if (( authenticated )); then
      if [[ -n "${STUB_MIGRATION_BODY+x}" ]]; then
        body="$STUB_MIGRATION_BODY"
        code="${STUB_MIGRATION_CODE:-200}"
      elif [[ -n "${STUB_MIGRATION_SEQ:-}" ]]; then
        read -r -a sequence <<<"$STUB_MIGRATION_SEQ"
        index=0
        [[ ! -f "$STUB_DIR/migration-calls" ]] || index="$(<"$STUB_DIR/migration-calls")"
        (( index < ${#sequence[@]} )) || index=$(( ${#sequence[@]} - 1 ))
        printf '%s' "$(( index + 1 ))" > "$STUB_DIR/migration-calls"
        body="{\"status\":\"${sequence[$index]}\"}"
      else
        body='{"status":"completed"}'
      fi
    else
      code=401
    fi
    ;;
  /global/health)
    if [[ -n "${STUB_HEALTH_BODY+x}" ]]; then
      body="$STUB_HEALTH_BODY"
    else
      body='<!doctype html><html><body>web ui</body></html>'
    fi
    ;;
  /session/status)
    code="${STUB_SESSION_CODE:-200}"
    empty_map='{}'
    body="${STUB_SESSION_BODY:-$empty_map}"
    ;;
  *)
    code=404
    body='not found'
    ;;
esac
printf '%s' "$body"
if [[ "$options" == *'write-out'* ]]; then
  printf '\n%s' "$code"
elif [[ "$code" != 200 ]]; then
  exit 22
fi
STUB

  cat > "$TEMP_DIR/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == *"_SYSTEMD_INVOCATION_ID=${STUB_MARKER_INVOCATION:-}"* ]] || exit 1
[[ "$*" == *'--grep=Bot @[^ ]+ started!'* ]] || exit 2
[[ "${STUB_TELEGRAM_STARTED:-0}" == "1" ]] || exit 1
# Real journalctl prints every match even under --quiet, which only silences
# its informational messages.
printf '%s\n' 'Bot @stub_bot started!'
STUB

  chmod 0755 "$TEMP_DIR/bin/systemctl" "$TEMP_DIR/bin/curl" "$TEMP_DIR/bin/journalctl"
}

# Resets the control directory and the stub-visible state before each case, so
# cases cannot leak into one another.
new_case() {
  CASE_DIR="$TEMP_DIR/case-$1"
  CONTROL_DIR="$CASE_DIR/control"
  STUB_DIR="$CASE_DIR/stub"
  mkdir -p "$CONTROL_DIR" "$STUB_DIR"
  : > "$STUB_DIR/restarts"

  export OPENCODE_GATEWAY_CONTROL_DIR="$CONTROL_DIR"
  export STUB_DIR
  export RESTART_TARGET_UNIT="opencode-test.service"
  export RESTART_IDLE_TIMEOUT=1
  export RESTART_IDLE_INTERVAL=1
  export STUB_ACTIVE_STATE="active"
  export STUB_SESSION_BODY="{}"
  # A stock 2.x server by default: HTML on /global/health, JSON on /api/info.
  unset STUB_HEALTH_BODY STUB_INFO_BODY STUB_MIGRATION_SEQ STUB_MIGRATION_BODY STUB_MIGRATION_CODE MAINPID
  export STUB_INFO_CODE=200
  export STUB_INFO_VERSION=2.3.0
  export STUB_INFO_PID=1327923
  export STUB_INFO_UNAUTH_CODE=401
  export STUB_SESSION_CODE=200
  export STUB_TELEGRAM_STARTED=1
  export STUB_MARKER_INVOCATION=test-invocation
  export STUB_REQUIRE_AUTH=0
  export STUB_CURL_STATUS=0
  export STUB_RESTART_STATUS=0
  export STUB_RESTART_OUTPUT=""
}

# The restart consumer is 1.x only; its cases run against a server that is not 2.x.
new_v1_case() {
  new_case "$1"
  export STUB_INFO_CODE=404 STUB_INFO_BODY='not found'
}

run_consumer() {
  CONSUMER_OUTPUT="$( PATH="$TEMP_DIR/bin:$PATH" bash "$CONSUMER" 2>&1 )" &&
    CONSUMER_STATUS=0 || CONSUMER_STATUS=$?
}

write_request() {
  printf '{"requestedAtMs": %s, "requestedBy": "gateway_restart"}\n' "$1" \
    > "$CONTROL_DIR/restart-request.json"
}

restart_count() {
  wc -l < "$STUB_DIR/restarts" | tr -d ' '
}

status_field() {
  jq -r "$1" < "$CONTROL_DIR/restart-status.json"
}

# A run with no work must write nothing at all. The consumer is path-activated
# on the very files it writes, so a gratuitous write is an infinite trigger
# loop, which makes this the single most important case in the suite.
test_no_work_writes_nothing() {
  new_v1_case no-work
  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an idle consumer must succeed"
  assert_equal "$(find "$CONTROL_DIR" -type f | wc -l)" "0" \
    "an idle consumer must not create any file"
  assert_equal "$(restart_count)" "0" "an idle consumer must not restart anything"
}

# The steady state on a healthy host is a status file left over from the last
# restart. It must not be rewritten either.
test_settled_status_is_left_untouched() {
  new_v1_case settled
  printf '{\n  "state": "idle"\n}\n' > "$CONTROL_DIR/restart-status.json"
  local before
  before="$(cksum < "$CONTROL_DIR/restart-status.json")"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "a settled status must not fail the consumer"
  assert_equal "$(cksum < "$CONTROL_DIR/restart-status.json")" "$before" \
    "a settled status file must be byte-identical afterwards"
  assert_equal "$(restart_count)" "0" "a settled status must not restart anything"
}

test_request_file_is_consumed_and_the_unit_restarted() {
  new_v1_case request
  write_request 1757000000000

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "a request must be honoured"
  assert_equal "$(restart_count)" "1" "the unit must be restarted exactly once"
  if [[ -f "$CONTROL_DIR/restart-request.json" ]]; then
    fail "the request file must be consumed"
  fi
  assert_equal "$(status_field '.state')" "idle" "a completed restart settles at idle"
  assert_equal "$(status_field '.requestedAtMs')" "1757000000000" \
    "the original request stamp must be preserved"
  assert_equal "$(status_field '.lastError')" "null" "a successful restart records no error"
  if [[ "$(status_field '.completedAtMs')" == "null" ]]; then
    fail "a completed restart must record completedAtMs"
  fi
  assert_contains "$CONSUMER_OUTPUT" "restarted" "the consumer must report the restart"
}

# The interactive path: the tool recorded the intent but no request file exists.
test_pending_status_alone_is_honoured() {
  new_v1_case pending
  jq -n '{state: "pending", requestedAtMs: 1757111111000, completedAtMs: null, lastError: null}' \
    > "$CONTROL_DIR/restart-status.json"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "a pending status alone must be honoured"
  assert_equal "$(restart_count)" "1" "the unit must be restarted"
  assert_equal "$(status_field '.requestedAtMs')" "1757111111000" \
    "the pending stamp must be carried through"
  assert_equal "$(status_field '.state')" "idle" "a completed restart settles at idle"
}

# The promise the plugin's tool makes to the user is that the restart waits for
# current work to finish. A busy server must therefore not be restarted.
test_a_busy_server_is_not_restarted() {
  new_v1_case busy
  write_request 1757222222000
  export STUB_SESSION_BODY='{"ses_abc":{"running":true}}'

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "refusing to restart a busy server is a failure"
  assert_equal "$(restart_count)" "0" "a busy server must not be restarted"
  assert_equal "$(status_field '.state')" "failed" "the refusal must be recorded as failed"
  assert_contains "$(status_field '.lastError')" "not idle" \
    "the recorded error must say why"
  if [[ -f "$CONTROL_DIR/restart-request.json" ]]; then
    fail "a refused request must still be consumed, or it re-triggers for ever"
  fi
}

# The positive control for the case above. Same code path, same stubs, only the
# response body differs — so a pass here proves the idle check reads the body
# rather than merely passing whenever the probe succeeds.
test_an_empty_session_body_is_idle() {
  new_v1_case empty-body
  write_request 1757333333000
  export STUB_SESSION_BODY='{}'

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an empty session map is idle"
  assert_equal "$(restart_count)" "1" "an idle server must be restarted"
}

# Nothing can be in flight through an API that is not answering, and a restart
# is the right move for a server in that state.
test_an_unanswered_probe_counts_as_idle() {
  new_v1_case no-answer
  write_request 1757444444000
  export STUB_CURL_STATUS=7

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an unreachable server must not block the restart"
  assert_equal "$(restart_count)" "1" "an unreachable server must still be restarted"
}

# Restarting mid-start would cut off the readiness probe of the start already
# running.
test_a_unit_mid_start_is_not_idle() {
  new_v1_case activating
  write_request 1757555555000
  export STUB_ACTIVE_STATE="activating"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "a unit mid-start is not idle"
  assert_equal "$(restart_count)" "0" "a unit mid-start must not be restarted"
  assert_equal "$(status_field '.state')" "failed" "the refusal must be recorded"
}

test_a_failed_restart_is_recorded_with_its_output() {
  new_v1_case restart-fails
  write_request 1757666666000
  export STUB_RESTART_STATUS=1
  export STUB_RESTART_OUTPUT="Job for opencode-test.service failed"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "a failed restart must fail the consumer"
  assert_equal "$(status_field '.state')" "failed" "a failed restart is recorded as failed"
  assert_contains "$(status_field '.lastError')" "Job for opencode-test.service failed" \
    "the recorded error must carry systemctl's own output"
}

# A malformed stamp is still a request. Discarding it would lose a restart the
# user asked for; dating it now keeps the record well-formed.
test_a_request_without_a_usable_stamp_is_still_honoured() {
  new_v1_case bad-stamp
  printf '{"requestedAtMs": "not-a-number", "requestedBy": "gateway_restart"}\n' \
    > "$CONTROL_DIR/restart-request.json"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "a malformed stamp must not lose the request"
  assert_equal "$(restart_count)" "1" "the unit must still be restarted"
  if [[ "$(status_field '.requestedAtMs')" == "null" ]]; then
    fail "a substituted stamp must still be recorded"
  fi
}

# The 1.x endpoint is /session/status. A 404 or an HTML page from it carries no
# information about sessions, so treating it as "no sessions" would restart a
# server in the middle of a turn.
test_a_404_from_session_status_is_not_idle() {
  new_v1_case session-404
  write_request 1757888888000
  export STUB_SESSION_CODE=404 STUB_SESSION_BODY='not found'

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "an unreadable session status is not idle"
  assert_equal "$(restart_count)" "0" "an unreadable session status must not restart"
  assert_contains "$(status_field '.lastError')" "not idle" "the refusal must say why"
}

test_a_non_json_session_status_is_not_idle() {
  new_v1_case session-html
  write_request 1757999999000
  export STUB_SESSION_BODY='<!doctype html><html></html>'

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "a non-JSON session status is not idle"
  assert_equal "$(restart_count)" "0" "a non-JSON session status must not restart"
}

# 1.x only: on a 2.x server /session/status is not the idle signal, so the
# consumer must refuse rather than act on something it cannot read.
test_a_2x_server_is_refused_and_not_restarted() {
  new_case gateway-2x
  write_request 1758000000000

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "a 2.x server must fail the consumer"
  assert_equal "$(restart_count)" "0" "a 2.x server must not be restarted"
  assert_contains "$CONSUMER_OUTPUT" "OpenCode 2.x" "the refusal must name the reason"
  assert_equal "$(status_field '.state')" "failed" "the refusal must be recorded"
  if [[ -f "$CONTROL_DIR/restart-request.json" ]]; then
    fail "a refused request must still be consumed, or it re-triggers for ever"
  fi
}

# Every state the consumer writes is read back by the plugin, which treats
# malformed JSON as an error rather than as an absent file.
test_every_written_status_is_well_formed_json() {
  new_v1_case shape
  write_request 1757777777000

  run_consumer

  local keys
  keys="$(jq -r 'keys_unsorted | join(",")' < "$CONTROL_DIR/restart-status.json")"
  assert_equal "$keys" "state,requestedAtMs,startedAtMs,completedAtMs,lastError" \
    "the status file must carry exactly the fields the contract defines"
}

# Runs the server probe with a short window and the fixture password. Extra
# arguments are environment assignments for the run and override the defaults.
run_ready() {
  READY_OUTPUT="$(
    PATH="$TEMP_DIR/bin:$PATH" env \
      READY_TIMEOUT=0 READY_INTERVAL=0 OPENCODE_PASSWORD=test-password \
      "$@" bash "$READY" 2>&1
  )" && READY_STATUS=0 || READY_STATUS=$?
}

test_server_readiness_accepts_a_stock_2x_server() {
  new_case server-ready
  export STUB_REQUIRE_AUTH=1

  run_ready

  assert_equal "$READY_STATUS" "0" "a stock 2.x server must pass readiness"
  assert_contains "$READY_OUTPUT" "readiness: READY" "readiness must report READY"
  assert_contains "$READY_OUTPUT" "OpenCode 2.3.0" \
    "readiness must report the version the server identified itself as"
}

# The web UI's SPA fallback answers 200 text/html on unknown paths, so a status
# code alone proves nothing and a substring grep over the body is not enough.
test_server_readiness_rejects_a_spa_fallback_on_api_info() {
  new_case ready-spa
  export STUB_INFO_BODY='<!doctype html><html><body>web ui</body></html>'

  run_ready

  assert_equal "$READY_STATUS" "1" "an HTML body on /api/info is not a server"
  assert_contains "$READY_OUTPUT" "NOT READY" "readiness must refuse"
}

test_server_readiness_requires_the_main_pid_to_match_api_info() {
  new_case ready-pid
  local live_pid
  sleep 30 &
  live_pid=$!

  export STUB_INFO_PID=$(( live_pid + 1 ))
  run_ready MAINPID="$live_pid"
  assert_equal "$READY_STATUS" "1" "a pid other than MAINPID is another process"
  assert_contains "$READY_OUTPUT" "does not match MAINPID" \
    "readiness must say which half failed"

  export STUB_INFO_PID="$live_pid"
  run_ready MAINPID="$live_pid"
  kill "$live_pid" 2>/dev/null || true
  assert_equal "$READY_STATUS" "0" "the matching pid must pass"
  assert_contains "$READY_OUTPUT" "readiness: READY" "readiness must report READY"
}

test_server_readiness_requires_major_2() {
  new_case ready-v1-version
  export STUB_INFO_VERSION=1.19.5

  run_ready

  assert_equal "$READY_STATUS" "1" "a 1.x version string is not a 2.x server"
  assert_contains "$READY_OUTPUT" "NOT READY" "readiness must refuse"
}

# A 200 for an anonymous request means the server runs with no password. That is
# fatal, not something to poll: waiting cannot change it.
test_server_readiness_fails_when_the_server_has_no_password() {
  new_case ready-open
  export STUB_INFO_UNAUTH_CODE=200
  local started=$SECONDS

  run_ready READY_TIMEOUT=30 READY_INTERVAL=1

  assert_equal "$READY_STATUS" "1" "an unauthenticated 200 must fail readiness"
  (( SECONDS - started <= 3 )) || fail "an open server must fail at once, not after the window"
  assert_contains "$READY_OUTPUT" "without a password" "readiness must say why"
}

test_server_readiness_waits_for_the_migration() {
  new_case ready-migration
  export STUB_MIGRATION_SEQ="running completed"

  run_ready READY_TIMEOUT=10 READY_INTERVAL=1
  assert_equal "$READY_STATUS" "0" "readiness must pass once the migration completes"
  assert_contains "$READY_OUTPUT" "migration" "readiness must mention the migration wait"

  rm -f "$STUB_DIR/migration-calls"
  export STUB_MIGRATION_SEQ="running"
  run_ready
  assert_equal "$READY_STATUS" "1" "a migration still running is not ready"
  assert_contains "$READY_OUTPUT" "migration" "readiness must name the migration"
}

test_server_readiness_refuses_a_tool_marker() {
  new_case ready-marker

  run_ready READY_TOOL_MARKER=gateway_status

  assert_equal "$READY_STATUS" "2" "READY_TOOL_MARKER must be an error on 2.x"
  assert_contains "$READY_OUTPUT" "READY_TOOL_MARKER" "the error must name the variable"

  run_ready READY_TOOL_MARKER=
  assert_equal "$READY_STATUS" "2" "an empty READY_TOOL_MARKER is still a stale unit setting"
}

# A unit that still starts a 1.x server must trip the start limit rather than
# poll out the window on every cycle.
test_server_readiness_fails_at_once_on_a_1x_server() {
  new_case ready-v1-server
  export STUB_HEALTH_BODY='{"healthy":true,"version":"1.19.5"}'
  export STUB_INFO_CODE=404 STUB_INFO_BODY='not found'
  local started=$SECONDS

  run_ready READY_TIMEOUT=30 READY_INTERVAL=1

  assert_equal "$READY_STATUS" "1" "a 1.x server must fail readiness"
  (( SECONDS - started <= 3 )) || fail "a 1.x server must fail at once"
  assert_contains "$READY_OUTPUT" "1.x" "readiness must say it found a 1.x server"
}

test_server_readiness_needs_a_password_and_prefers_opencode_password() {
  new_case ready-password
  export STUB_REQUIRE_AUTH=1

  run_ready OPENCODE_PASSWORD= OPENCODE_SERVER_PASSWORD=
  assert_equal "$READY_STATUS" "2" "a probe without a password cannot authenticate"
  assert_contains "$READY_OUTPUT" "OPENCODE_PASSWORD" "the error must name the variable"

  run_ready OPENCODE_PASSWORD= OPENCODE_SERVER_PASSWORD=test-password
  assert_equal "$READY_STATUS" "0" "OPENCODE_SERVER_PASSWORD is accepted"

  run_ready OPENCODE_PASSWORD=test-password OPENCODE_SERVER_PASSWORD=wrong
  assert_equal "$READY_STATUS" "0" "OPENCODE_PASSWORD wins when both are set"

  run_ready OPENCODE_SERVER_USERNAME=someone-else
  assert_equal "$READY_STATUS" "0" "the Basic-auth username is always opencode"
}

# The 2.3.0 OpenAPI types the migration status as one of four shapes. Only
# `completed` is ready; `running` and `required` wait; `error` and anything
# unrecognised fail at once, because waiting cannot fix them.
test_server_readiness_handles_every_migration_state() {
  new_case ready-migration-states

  export STUB_MIGRATION_BODY='{"status":"completed"}'
  run_ready
  assert_equal "$READY_STATUS" "0" "completed is ready"

  export STUB_MIGRATION_BODY='{"status":"running","progress":{"label":"sessions","numerator":3,"denominator":9}}'
  run_ready
  assert_equal "$READY_STATUS" "1" "running is not ready"
  assert_contains "$READY_OUTPUT" "running" "the wait must name the state"

  export STUB_MIGRATION_BODY='{"status":"required"}'
  run_ready
  assert_equal "$READY_STATUS" "1" "required is not ready"
  assert_contains "$READY_OUTPUT" "required" "the wait must name the state"

  local started=$SECONDS
  export STUB_MIGRATION_BODY='{"status":"error","error":"disk full"}'
  run_ready READY_TIMEOUT=30 READY_INTERVAL=1
  assert_equal "$READY_STATUS" "1" "error is not ready"
  assert_contains "$READY_OUTPUT" "disk full" "the error text must be reported"
  (( SECONDS - started <= 3 )) || fail "a migration error must fail at once"

  started=$SECONDS
  export STUB_MIGRATION_BODY='{"status":"exploded"}'
  run_ready READY_TIMEOUT=30 READY_INTERVAL=1
  assert_equal "$READY_STATUS" "1" "an unknown status is not ready"
  (( SECONDS - started <= 3 )) || fail "an unknown status must fail at once"

  started=$SECONDS
  export STUB_MIGRATION_BODY='<!doctype html><html></html>'
  run_ready READY_TIMEOUT=30 READY_INTERVAL=1
  assert_equal "$READY_STATUS" "1" "a non-JSON 200 is an unknown shape"
  (( SECONDS - started <= 3 )) || fail "an unknown shape must fail at once"

  # An endpoint that does not answer (here 404) says nothing about a migration.
  export STUB_MIGRATION_BODY='not found' STUB_MIGRATION_CODE=404
  run_ready
  assert_equal "$READY_STATUS" "0" "a non-200 migration endpoint is not evidence of a migration"
}

# The unit and the probe read the same EnvironmentFile, so a password that
# stays rejected is misconfiguration. Polling out the window on every start
# would defeat the start limit, so a few 401s fail the start.
test_server_readiness_fails_fast_on_a_rejected_password() {
  new_case ready-wrong-password
  export STUB_REQUIRE_AUTH=1
  local started=$SECONDS

  run_ready OPENCODE_PASSWORD=wrong READY_TIMEOUT=30 READY_INTERVAL=1

  assert_equal "$READY_STATUS" "1" "a rejected password must fail readiness"
  (( SECONDS - started <= 5 )) || fail "a rejected password must not poll out the window"
  assert_contains "$READY_OUTPUT" "401" "readiness must say the credentials were rejected"
}

test_probes_require_jq() {
  local nojq="$TEMP_DIR/nojq-bin" bash_bin output status
  mkdir -p "$nojq"
  bash_bin="$(command -v bash)"
  set +e
  output="$(PATH="$nojq" OPENCODE_PASSWORD=x INVOCATION_ID=i "$bash_bin" "$READY" 2>&1)"
  status=$?
  set -e
  assert_equal "$status" "2" "the server probe must exit 2 without jq"
  assert_contains "$output" "jq is required" "the server probe must say why"
  set +e
  output="$(PATH="$nojq" OPENCODE_PASSWORD=x INVOCATION_ID=i "$bash_bin" "$TELEGRAM_READY" 2>&1)"
  status=$?
  set -e
  assert_equal "$status" "2" "the Telegram probe must exit 2 without jq"
  assert_contains "$output" "jq is required" "the Telegram probe must say why"
}

test_telegram_readiness_accepts_the_legacy_password_name() {
  new_case telegram-legacy-password
  export STUB_REQUIRE_AUTH=1

  local output status=0
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" env -u OPENCODE_PASSWORD \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_SERVER_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )" || status=$?
  assert_equal "$status" "0" "OPENCODE_SERVER_PASSWORD must authenticate the Telegram probe: $output"

  status=0
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password OPENCODE_SERVER_PASSWORD=wrong \
      bash "$TELEGRAM_READY" 2>&1
  )" || status=$?
  assert_equal "$status" "0" "OPENCODE_PASSWORD must win when both are set: $output"
}

# A server that exits at once must fail the start at once. Polling out the window
# instead makes every crash-loop cycle longer than StartLimitIntervalSec, so the
# start limit never trips and the unit restarts for ever.
test_server_readiness_fails_fast_when_the_main_process_is_gone() {
  new_case ready-dead-main
  export STUB_CURL_STATUS=7                 # never healthy: only MAINPID can end it

  local dead_pid
  bash -c 'exit 1' &
  dead_pid=$!
  wait "$dead_pid" || true

  local started=$SECONDS
  run_ready MAINPID="$dead_pid" READY_TIMEOUT=30 READY_INTERVAL=1

  assert_equal "$READY_STATUS" "1" "a dead main process must fail readiness"
  (( SECONDS - started <= 3 )) \
    || fail "readiness must not poll out the window after the main process exits"
  assert_contains "$READY_OUTPUT" "main process $dead_pid exited during startup" \
    "readiness must say why it gave up"
}

test_telegram_readiness_requires_polling_and_opencode() {
  new_case telegram-ready
  export STUB_REQUIRE_AUTH=1

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "0" "Telegram readiness must pass when both dependencies are ready"
  assert_contains "$output" "telegram-readiness: READY" \
    "Telegram readiness must report success"

  export STUB_TELEGRAM_STARTED=0
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "Telegram readiness must fail without a polling marker"
  assert_contains "$output" "polling marker absent" \
    "Telegram readiness must diagnose a missing polling marker"

  export STUB_TELEGRAM_STARTED=1
  export STUB_INFO_BODY='<!doctype html><html></html>'
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "Telegram readiness must fail without a 2.x API"
  assert_contains "$output" "OpenCode 2.x API unavailable" \
    "Telegram readiness must diagnose an unavailable OpenCode dependency"

  unset STUB_INFO_BODY
  export STUB_MARKER_INVOCATION=stale-invocation
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=current-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "a stale invocation marker must not satisfy readiness"
  assert_contains "$output" "polling marker absent" \
    "Telegram readiness must scope the marker to the current invocation"
}

test_telegram_readiness_requires_a_2x_server() {
  new_case telegram-v1-version
  export STUB_INFO_VERSION=1.19.5

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "a 1.x version must not satisfy Telegram readiness"
  assert_contains "$output" "OpenCode 2.x API unavailable" \
    "Telegram readiness must diagnose the version mismatch"
}

test_telegram_readiness_requires_systemd_invocation_id() {
  new_case telegram-no-invocation

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      env -u INVOCATION_ID bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "Telegram readiness must reject non-systemd execution"
  assert_contains "$output" "systemd invocation id is required" \
    "Telegram readiness must explain its systemd-only contract"
}

# The probe's stdout lands in the journal under the same invocation id it greps,
# so an echoed marker matches again on the next poll and the output snowballs:
# one start on a real host logged 22,307 lines. Matching must stay silent.
test_telegram_readiness_does_not_echo_journal_matches() {
  new_case telegram-no-echo
  export STUB_INFO_BODY='<!doctype html><html></html>'   # keep it polling past the marker

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=2 TELEGRAM_READY_INTERVAL=1 \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "an unhealthy OpenCode must still fail Telegram readiness"
  [[ "$output" != *'started!'* ]] \
    || fail "Telegram readiness must not copy journal matches into its own output: '$output'"
}

# The same containment rule as the server probe: a bot that exits at once must
# fail the start at once, not after the whole window.
test_telegram_readiness_fails_fast_when_the_main_process_is_gone() {
  new_case telegram-dead-main
  export STUB_TELEGRAM_STARTED=0            # never ready: only MAINPID can end it

  local dead_pid
  bash -c 'exit 1' &
  dead_pid=$!
  wait "$dead_pid" || true

  local output status started=$SECONDS
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" MAINPID="$dead_pid" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=30 TELEGRAM_READY_INTERVAL=1 \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "a dead main process must fail Telegram readiness"
  (( SECONDS - started <= 3 )) \
    || fail "Telegram readiness must not poll out the window after the main process exits"
  assert_contains "$output" "main process $dead_pid exited during startup" \
    "Telegram readiness must say why it gave up"
}

test_telegram_readiness_passes_while_the_main_process_lives() {
  new_case telegram-live-main

  local live_pid
  sleep 30 &
  live_pid=$!

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" MAINPID="$live_pid" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e
  kill "$live_pid" 2>/dev/null || true

  assert_equal "$status" "0" "a live main process must not block Telegram readiness"
  assert_contains "$output" "telegram-readiness: READY" \
    "Telegram readiness must still report READY"
}

test_shipped_scripts_are_executable_and_syntactically_valid() {
  local script
  for script in "$CONSUMER" "$READY" "$TELEGRAM_READY"; do
    [[ -x "$script" ]] || fail "$script must be executable as shipped"
    bash -n "$script" || fail "$script must be syntactically valid"
  done
}

test_service_helpers_declare_and_print_their_versions() {
  local -A expected=(
    ["$CONSUMER"]="0.2.0"
    ["$READY"]="1.0.0"
    ["$TELEGRAM_READY"]="1.0.0"
  )
  local script
  for script in "$CONSUMER" "$READY" "$TELEGRAM_READY"; do
    grep -qE '^readonly SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$script" \
      || fail "$script must declare a semantic SCRIPT_VERSION"

    local output status
    set +e
    output="$(bash "$script" --version 2>&1)"
    status=$?
    set -e

    assert_equal "$status" "0" "$script --version must exit 0"
    assert_equal "$output" "${expected[$script]}" "$script --version must print the version"
  done
}

test_service_helpers_survive_no_arguments_under_set_u() {
  # The systemd units invoke these with no arguments at all. The --version
  # guard must not dereference an unset $1, and -- the part that matters --
  # its FALSE path must not terminate the script under set -e.
  #
  # Asserting only that the output lacks "unbound variable" and "--version" is
  # weak: an empty output satisfies both. Each script therefore carries a
  # positive marker proving main was actually reached -- the two probes emit a
  # diagnostic, while the restart consumer legitimately writes nothing and
  # exits 0 on its no-work path.
  #
  # What this does NOT prove, despite an earlier claim in this suite: it does
  # not catch a guard rewritten as `[[ ... ]] && { ...; }`. That form was
  # measured against bash 5.2 and is exempt from errexit both at top level and
  # as a function's first statement; it only fails the caller when it is a
  # function's LAST statement, which no guard here is. The markers catch a
  # guard that always fires, and any other early exit before main.
  local entry script marker output status
  for entry in \
    "$CONSUMER|" \
    "$READY|readiness:" \
    "$TELEGRAM_READY|systemd invocation id is required"; do
    script="${entry%%|*}"
    marker="${entry#*|}"

    set +e
    output="$(RESTART_IDLE_TIMEOUT=0 RESTART_IDLE_INTERVAL=0 \
              READY_TIMEOUT=0 READY_INTERVAL=0 \
              TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
              env -u INVOCATION_ID bash "$script" 2>&1)"
    status=$?
    set -e

    [[ "$output" != *"unbound variable"* ]] \
      || fail "$script must not dereference an unset \$1"
    [[ "$output" != *"--version"* ]] \
      || fail "$script must not print version output with no arguments"

    if [[ -n "$marker" ]]; then
      [[ "$output" == *"$marker"* ]] \
        || fail "$script must reach main with no arguments; expected '$marker', got: $output"
    else
      assert_equal "$status" "0" "$script must reach main and complete its no-work path"
    fi
  done
}

test_documented_attach_shortcut() (
  local sandbox="$TEMP_DIR/attach"
  mkdir -p "$sandbox/bin" "$sandbox/home/.config/opencode-runtime" "$sandbox/work space" "$sandbox/other"
  export HOME="$sandbox/home" PATH="$sandbox/bin:$PATH"
  export ATTACH_RECORD="$sandbox/args"
  unset OPENCODE_PASSWORD OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME
  export TELEGRAM_BOT_TOKEN=fixture-only

  cat > "$sandbox/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == '--user is-active --quiet opencode.service' ]] || exit 2
exit "${ATTACH_SERVICE_STATUS:-0}"
STUB
  cat > "$sandbox/bin/opencode" <<'STUB'
#!/usr/bin/env bash
[[ "${OPENCODE_PASSWORD:-}" == fixture-password ||
   "${OPENCODE_SERVER_PASSWORD:-}" == fixture-password ]] || exit 91
[[ -z "${TELEGRAM_BOT_TOKEN+x}" ]] || exit 93
printf '%s\n' "$@" > "$ATTACH_RECORD"
exit "${ATTACH_EXIT_STATUS:-0}"
STUB
  chmod +x "$sandbox/bin/systemctl" "$sandbox/bin/opencode"
  cat > "$HOME/.config/opencode-runtime/secrets.env" <<'ENV'
OPENCODE_PASSWORD=fixture-password
ENV
  # Execute the shipped snippet, rather than a second implementation of it.
  sed -n '/^# >>> opencode-attach-wrapper >>>$/,/^# <<< opencode-attach-wrapper <<<$/{p;}' \
    "$REPOSITORY_ROOT/docs/opencode-service.md" > "$sandbox/wrapper.sh"
  # shellcheck source=/dev/null
  source "$sandbox/wrapper.sh"
  declare -F oca >/dev/null || fail "documented wrapper must define oca"
  [[ "$(type -t opencode)" == file ]] || fail "opencode must remain the original command"

  cd "$sandbox/work space"
  oca --session 'session with spaces'
  local -a arguments
  mapfile -t arguments < "$ATTACH_RECORD"
  assert_equal "${#arguments[@]}" 5 "client arguments must keep their boundaries"
  assert_equal "${arguments[0]}" --server "oca must connect with --server (opencode attach is gone in 2.x)"
  assert_equal "${arguments[1]}" http://127.0.0.1:4096 "oca must use loopback"
  assert_equal "${arguments[2]}" "$sandbox/work space" "directory with spaces must survive as the positional directory"
  assert_equal "${arguments[3]}" --session "client options must be forwarded"
  assert_equal "${arguments[4]}" 'session with spaces' "option values must survive"
  [[ -z "${OPENCODE_PASSWORD+x}" && -z "${OPENCODE_SERVER_PASSWORD+x}" ]] \
    || fail "server credentials must not leak into the caller"
  assert_equal "$TELEGRAM_BOT_TOKEN" fixture-only "caller environment must be preserved"

  cd "$sandbox/other"
  oca
  mapfile -t arguments < "$ATTACH_RECORD"
  assert_equal "${arguments[2]}" "$sandbox/other" "directory must be evaluated at each invocation"
  local status=0
  ATTACH_EXIT_STATUS=17 oca || status=$?
  assert_equal "$status" 17 "client exit status must propagate"

  # The legacy variable name is accepted by the 2.x client as well.
  printf 'OPENCODE_SERVER_PASSWORD=fixture-password\n' > "$HOME/.config/opencode-runtime/secrets.env"
  oca
  printf 'OPENCODE_PASSWORD=fixture-password\n' > "$HOME/.config/opencode-runtime/secrets.env"

  rm "$ATTACH_RECORD"
  status=0
  ATTACH_SERVICE_STATUS=1 oca >/dev/null 2>&1 || status=$?
  [[ "$status" != 0 && ! -e "$ATTACH_RECORD" ]] || fail "inactive service must prevent connecting"
  printf 'OTHER=1\n' > "$HOME/.config/opencode-runtime/secrets.env"
  status=0
  oca >/dev/null 2>&1 || status=$?
  [[ "$status" != 0 && ! -e "$ATTACH_RECORD" ]] || fail "a missing password must prevent connecting"
  rm "$HOME/.config/opencode-runtime/secrets.env"
  status=0
  oca >/dev/null 2>&1 || status=$?
  [[ "$status" != 0 && ! -e "$ATTACH_RECORD" ]] || fail "missing credentials must prevent connecting"
  printf 'return 1\n' > "$HOME/.config/opencode-runtime/secrets.env"
  status=0
  oca >/dev/null 2>&1 || status=$?
  [[ "$status" != 0 && ! -e "$ATTACH_RECORD" ]] || fail "failed credential load must prevent connecting"
)

# The runbook is the deliverable for the unit text, so assert the 2.x facts that
# a copy-paste of it depends on, rather than trusting that it was edited.
test_runbook_documents_the_2x_service() {
  local runbook="$REPOSITORY_ROOT/docs/opencode-service.md"
  local text unit
  text="$(<"$runbook")"
  unit="$(sed -n '/^\[Unit\]$/,/^\[Install\]$/p' "$runbook" | sed -n '1,/^\[Install\]$/p')"

  assert_contains "$unit" "ExecStart=%h/.opencode/bin/opencode serve --hostname 127.0.0.1 --port 4096" \
    "the unit must run opencode serve on loopback"
  assert_contains "$unit" "Environment=OPENCODE_DISABLE_AUTOUPDATE=1" \
    "the unit must stop the server upgrading itself"
  assert_contains "$unit" "SuccessExitStatus=143" \
    "the unit must treat opencode serve's SIGTERM exit (143) as a clean stop"
  [[ "$text" != *"opencode web --"* ]] || fail "opencode web does not exist in 2.x"
  [[ "$text" != *"opencode attach http"* ]] || fail "opencode attach does not exist in 2.x"
  [[ "$text" != *'Environment="READY_TOOL_MARKER'* ]] || fail "READY_TOOL_MARKER is gone"
  [[ "$text" != *"/global/health | head"* && "$text" != *"/global/health   # 401"* ]] \
    || fail "/global/health is not an authentication check in 2.x"
  assert_contains "$text" "opencode service set disabled true" \
    "the runbook must disable the shared background service"
  assert_contains "$text" "Moving an existing 1.x installation to 2.x" \
    "the migration section must exist"
  assert_contains "$text" "Never set \`remote\`" "the runbook must forbid the public tunnel"
  assert_contains "$text" "systemctl --user cat opencode.service" "the cutover must prove the unit no longer loads"
  # shellcheck disable=SC2016 # literal runbook text, not an expansion
  assert_contains "$text" '! pgrep -x opencode ||' "the process check must be fatal"
  local rollback="${text#*\*\*11. Rollback.\*\*}"
  local hold cat_check verify restore
  hold="${rollback%%2x-systemd*}"; cat_check="${rollback%%systemctl --user cat opencode.service*}"
  verify="${rollback%%sha256sum --check*}"; restore="${rollback%%mv \"\$data\"*}"
  [[ "$rollback" == *2x-systemd* && "$rollback" == *"systemctl --user cat opencode.service"* ]] \
    || fail "rollback must hold the 2.x units and prove they no longer load"
  (( ${#hold} < ${#cat_check} && ${#cat_check} < ${#verify} && ${#verify} < ${#restore} )) \
    || fail "rollback must take the units away before it verifies the backup and restores data"
  assert_contains "$rollback" "set -euo pipefail" "the rollback block must stop at its first failure"
  # shellcheck disable=SC2016 # literal runbook text, not an expansion
  assert_contains "$rollback" '${backup:?' "the rollback block must require \$backup"
  assert_contains "$text" "sha256sum --check" "rollback must verify the backup first"
  # shellcheck disable=SC2016 # literal runbook text, not an expansion
  assert_contains "$text" 'rm -f "$data"/opencode*.db-wal' "rollback must remove stale WAL files"
}

TEMP_DIR="$(mktemp -d)"
test_documented_attach_shortcut
test_runbook_documents_the_2x_service
install_stubs
test_no_work_writes_nothing
test_settled_status_is_left_untouched
test_request_file_is_consumed_and_the_unit_restarted
test_pending_status_alone_is_honoured
test_a_busy_server_is_not_restarted
test_an_empty_session_body_is_idle
test_an_unanswered_probe_counts_as_idle
test_a_unit_mid_start_is_not_idle
test_a_failed_restart_is_recorded_with_its_output
test_a_request_without_a_usable_stamp_is_still_honoured
test_every_written_status_is_well_formed_json
test_a_404_from_session_status_is_not_idle
test_a_non_json_session_status_is_not_idle
test_a_2x_server_is_refused_and_not_restarted
test_server_readiness_accepts_a_stock_2x_server
test_server_readiness_rejects_a_spa_fallback_on_api_info
test_server_readiness_requires_the_main_pid_to_match_api_info
test_server_readiness_requires_major_2
test_server_readiness_fails_when_the_server_has_no_password
test_server_readiness_waits_for_the_migration
test_server_readiness_refuses_a_tool_marker
test_server_readiness_fails_at_once_on_a_1x_server
test_server_readiness_needs_a_password_and_prefers_opencode_password
test_server_readiness_handles_every_migration_state
test_server_readiness_fails_fast_on_a_rejected_password
test_probes_require_jq
test_telegram_readiness_accepts_the_legacy_password_name
test_server_readiness_fails_fast_when_the_main_process_is_gone
test_telegram_readiness_requires_polling_and_opencode
test_telegram_readiness_requires_a_2x_server
test_telegram_readiness_requires_systemd_invocation_id
test_telegram_readiness_does_not_echo_journal_matches
test_telegram_readiness_fails_fast_when_the_main_process_is_gone
test_telegram_readiness_passes_while_the_main_process_lives
test_shipped_scripts_are_executable_and_syntactically_valid
test_service_helpers_declare_and_print_their_versions
test_service_helpers_survive_no_arguments_under_set_u

printf 'PASS: opencode service tests\n'
bash "$REPOSITORY_ROOT/tests/opencode-direnv.sh"
