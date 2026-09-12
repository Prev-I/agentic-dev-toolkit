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

  cat > "$TEMP_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
options="$(cat)"                    # drain and inspect the -K - option block
if [[ "${STUB_REQUIRE_AUTH:-0}" == "1" ]]; then
  [[ "$options" == *'user = "test-user:test-password"'* ]] || exit 2
fi
exit_status="${STUB_CURL_STATUS:-0}"
[[ "$exit_status" == "0" ]] || exit "$exit_status"
case "$options" in
  *'/global/health'*) printf '%s' "${STUB_HEALTH_BODY:-\{\}}" ;;
  *'/experimental/tool/ids'*) printf '%s' "${STUB_TOOLS_BODY:-\[\]}" ;;
  *) printf '%s' "${STUB_SESSION_BODY:-\{\}}" ;;
esac
STUB

  cat > "$TEMP_DIR/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == *"_SYSTEMD_INVOCATION_ID=${STUB_MARKER_INVOCATION:-}"* ]] || exit 1
[[ "$*" == *'--grep=Bot @[^ ]+ started!'* ]] || exit 2
[[ "${STUB_TELEGRAM_STARTED:-0}" == "1" ]]
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
  export STUB_HEALTH_BODY='{"healthy":true}'
  export STUB_TOOLS_BODY='["bash"]'
  export STUB_TELEGRAM_STARTED=1
  export STUB_MARKER_INVOCATION=test-invocation
  export STUB_REQUIRE_AUTH=0
  export STUB_CURL_STATUS=0
  export STUB_RESTART_STATUS=0
  export STUB_RESTART_OUTPUT=""
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
  new_case no-work
  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an idle consumer must succeed"
  assert_equal "$(find "$CONTROL_DIR" -type f | wc -l)" "0" \
    "an idle consumer must not create any file"
  assert_equal "$(restart_count)" "0" "an idle consumer must not restart anything"
}

# The steady state on a healthy host is a status file left over from the last
# restart. It must not be rewritten either.
test_settled_status_is_left_untouched() {
  new_case settled
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
  new_case request
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
  new_case pending
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
  new_case busy
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
  new_case empty-body
  write_request 1757333333000
  export STUB_SESSION_BODY='{}'

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an empty session map is idle"
  assert_equal "$(restart_count)" "1" "an idle server must be restarted"
}

# Nothing can be in flight through an API that is not answering, and a restart
# is the right move for a server in that state.
test_an_unanswered_probe_counts_as_idle() {
  new_case no-answer
  write_request 1757444444000
  export STUB_CURL_STATUS=7

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "an unreachable server must not block the restart"
  assert_equal "$(restart_count)" "1" "an unreachable server must still be restarted"
}

# Restarting mid-start would cut off the readiness probe of the start already
# running.
test_a_unit_mid_start_is_not_idle() {
  new_case activating
  write_request 1757555555000
  export STUB_ACTIVE_STATE="activating"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "1" "a unit mid-start is not idle"
  assert_equal "$(restart_count)" "0" "a unit mid-start must not be restarted"
  assert_equal "$(status_field '.state')" "failed" "the refusal must be recorded"
}

test_a_failed_restart_is_recorded_with_its_output() {
  new_case restart-fails
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
  new_case bad-stamp
  printf '{"requestedAtMs": "not-a-number", "requestedBy": "gateway_restart"}\n' \
    > "$CONTROL_DIR/restart-request.json"

  run_consumer

  assert_equal "$CONSUMER_STATUS" "0" "a malformed stamp must not lose the request"
  assert_equal "$(restart_count)" "1" "the unit must still be restarted"
  if [[ "$(status_field '.requestedAtMs')" == "null" ]]; then
    fail "a substituted stamp must still be recorded"
  fi
}

# Every state the consumer writes is read back by the plugin, which treats
# malformed JSON as an error rather than as an absent file.
test_every_written_status_is_well_formed_json() {
  new_case shape
  write_request 1757777777000

  run_consumer

  local keys
  keys="$(jq -r 'keys_unsorted | join(",")' < "$CONTROL_DIR/restart-status.json")"
  assert_equal "$keys" "state,requestedAtMs,startedAtMs,completedAtMs,lastError" \
    "the status file must carry exactly the fields the contract defines"
}

test_server_readiness_defaults_to_a_builtin_tool() {
  new_case server-ready

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      READY_TIMEOUT=0 READY_INTERVAL=0 \
      env -u READY_TOOL_MARKER bash "$READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "0" "a stock OpenCode server must pass readiness"
  assert_contains "$output" "tool 'bash' registered" \
    "the default marker must be a built-in OpenCode tool"
}

test_server_readiness_accepts_an_explicit_plugin_marker() {
  new_case plugin-ready
  export STUB_TOOLS_BODY='["gateway_status"]'

  local output status
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      READY_TIMEOUT=0 READY_INTERVAL=0 READY_TOOL_MARKER=gateway_status \
      bash "$READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "0" "an explicit plugin marker must remain supported"
  assert_contains "$output" "tool 'gateway_status' registered" \
    "readiness must report the configured marker"
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
      OPENCODE_SERVER_USERNAME=test-user \
      OPENCODE_SERVER_PASSWORD=test-password \
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
      OPENCODE_SERVER_USERNAME=test-user \
      OPENCODE_SERVER_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "Telegram readiness must fail without a polling marker"
  assert_contains "$output" "polling marker absent" \
    "Telegram readiness must diagnose a missing polling marker"

  export STUB_TELEGRAM_STARTED=1
  export STUB_HEALTH_BODY='{"healthy":false}'
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=test-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_SERVER_USERNAME=test-user \
      OPENCODE_SERVER_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "Telegram readiness must fail without OpenCode health"
  assert_contains "$output" "OpenCode health unavailable" \
    "Telegram readiness must diagnose an unhealthy OpenCode dependency"

  export STUB_HEALTH_BODY='{"healthy":true}'
  export STUB_MARKER_INVOCATION=stale-invocation
  set +e
  output="$(
    PATH="$TEMP_DIR/bin:$PATH" \
      INVOCATION_ID=current-invocation \
      TELEGRAM_READY_TIMEOUT=0 TELEGRAM_READY_INTERVAL=0 \
      OPENCODE_SERVER_USERNAME=test-user \
      OPENCODE_SERVER_PASSWORD=test-password \
      bash "$TELEGRAM_READY" 2>&1
  )"
  status=$?
  set -e

  assert_equal "$status" "1" "a stale invocation marker must not satisfy readiness"
  assert_contains "$output" "polling marker absent" \
    "Telegram readiness must scope the marker to the current invocation"
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

test_shipped_scripts_are_executable_and_syntactically_valid() {
  local script
  for script in "$CONSUMER" "$READY" "$TELEGRAM_READY"; do
    [[ -x "$script" ]] || fail "$script must be executable as shipped"
    bash -n "$script" || fail "$script must be syntactically valid"
  done
}

TEMP_DIR="$(mktemp -d)"
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
test_server_readiness_defaults_to_a_builtin_tool
test_server_readiness_accepts_an_explicit_plugin_marker
test_telegram_readiness_requires_polling_and_opencode
test_telegram_readiness_requires_systemd_invocation_id
test_shipped_scripts_are_executable_and_syntactically_valid

printf 'PASS: opencode service tests\n'
