#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CLI="$REPOSITORY_ROOT/headroom-runtime/headroom-runtime.sh"
readonly CLI_PATH="headroom-runtime/headroom-runtime.sh"
readonly TEST_PATH="tests/headroom-runtime.sh"

cleanup() {
  if [[ -n "${TEMP_DIR:-}" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

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

install_stubs() {
  local command

  mkdir -p "$CASE_DIR/bin"
  for command in uv headroom systemctl curl ss uname sleep readlink stat; do
    {
      printf '#!%s\n' "$BASH_BIN"
      cat <<'STUB'
if [[ "$0" == */readlink && "$1" == "-f" ]]; then
  printf '%s\n' '---' "$0" "$@" >> "$HRT_COMMAND_LOG"
  printf '%s\n' "${HRT_READLINK_TARGET:-$2}"
  exit 0
fi
printf '%s\n' '---' "$0" "$@" >> "$HRT_COMMAND_LOG"
case "${0##*/}:$*" in
  uv:'tool install '*) printf '%s\n' '---' "$0" "$@" >> "$HRT_MUTATION_LOG" ;;
  headroom:'install apply '*) printf '%s\n' '---' "$0" "$@" >> "$HRT_MUTATION_LOG" ;;
  uname:*) printf '%s\n' Linux ;;
esac
STUB
    } > "$CASE_DIR/bin/$command"
    chmod 0755 "$CASE_DIR/bin/$command"
  done
}

# The helpers are duplicated from the other repository test suites: a shared
# library would expand this focused component change into unrelated suites.
new_case() {
  CASE_DIR="$TEMP_DIR/case-$1"
  mkdir -p "$CASE_DIR/home" "$CASE_DIR/proc" "$CASE_DIR/opencode" \
    "$CASE_DIR/systemd" "$CASE_DIR/deploy"
  : > "$CASE_DIR/uptime"
  : > "$CASE_DIR/commands"
  : > "$CASE_DIR/mutations"

  export HRT_HOME="$CASE_DIR/home"
  export HRT_PROC_ROOT="$CASE_DIR/proc"
  export HRT_OPENCODE_CONFIG_DIR="$CASE_DIR/opencode"
  export HRT_SYSTEMD_USER_DIR="$CASE_DIR/systemd"
  export HRT_HEADROOM_DEPLOY_ROOT="$CASE_DIR/deploy"
  export HRT_UPTIME_FILE="$CASE_DIR/uptime"
  export HRT_COMMAND_LOG="$CASE_DIR/commands"
  export HRT_MUTATION_LOG="$CASE_DIR/mutations"
  unset OPENCODE_CONFIG

  install_stubs
  export HRT_UV_BIN="$CASE_DIR/bin/uv"
  export HRT_HEADROOM_BIN="$CASE_DIR/bin/headroom"
  export HRT_SYSTEMCTL_BIN="$CASE_DIR/bin/systemctl"
  export HRT_CURL_BIN="$CASE_DIR/bin/curl"
  export HRT_JQ_BIN="$JQ_BIN"
  export HRT_SS_BIN="$CASE_DIR/bin/ss"
  export HRT_STAT_BIN="$CASE_DIR/bin/stat"
  export HRT_UNAME_BIN="$CASE_DIR/bin/uname"
  export HRT_SLEEP_BIN="$CASE_DIR/bin/sleep"
}

run_cli() {
  CLI_OUTPUT="$(run_in_fixture_path "$BASH_BIN" "$CLI" "$@" 2>&1)" &&
    CLI_STATUS=0 || CLI_STATUS=$?
}

run_cli_split_streams() {
  local stdout_file="$CASE_DIR/stdout"
  local stderr_file="$CASE_DIR/stderr"

  if run_in_fixture_path "$BASH_BIN" "$CLI" "$@" >"$stdout_file" 2>"$stderr_file"; then
    CLI_STATUS=0
  else
    CLI_STATUS=$?
  fi
  CLI_STDOUT="$(<"$stdout_file")"
  CLI_STDERR="$(<"$stderr_file")"
}

run_cli_from() {
  local directory="$1"
  shift
  CLI_OUTPUT="$(run_in_fixture_path_from "$directory" "$BASH_BIN" "$CLI" "$@" 2>&1)" &&
    CLI_STATUS=0 || CLI_STATUS=$?
}

run_in_fixture_path() {
  PATH="$CASE_DIR/bin" "$@"
}

run_in_fixture_path_from() {
  local directory="$1"
  shift
  (
    cd "$directory"
    PATH="$CASE_DIR/bin" "$@"
  )
}

source_cli_without_main() {
  local source_file="$CASE_DIR/headroom-runtime-functions.sh"
  local line

  while IFS= read -r line; do
    [[ "$line" == 'main "$@"' ]] && break
    printf '%s\n' "$line"
  done < "$CLI" > "$source_file"
  printf '%s\n' "$source_file"
}

run_resolve_in_conditional() {
  local source_file
  source_file="$(source_cli_without_main)"
  # shellcheck disable=SC2030,SC2031 # The local export is the behavior under test.
  CLI_OUTPUT="$(
    (
      export HRT_UV_BIN=relative/uv
      run_in_fixture_path "$BASH_BIN" -s "$source_file" <<'SCRIPT'
source "$1"
if resolve_executable UV_BIN HRT_UV_BIN uv; then
  printf 'unexpected success\n'
fi
printf 'validation was ignored\n'
SCRIPT
    ) 2>&1
  )" && CLI_STATUS=0 || CLI_STATUS=$?
}

read_uptime_file() {
  local source_file
  source_file="$(source_cli_without_main)"
  CLI_OUTPUT="$(run_in_fixture_path "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
printf '%s\n' "$UPTIME_FILE"
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
}

run_validate_uptime_file() {
  local source_file
  source_file="$(source_cli_without_main)"
  CLI_OUTPUT="$(run_in_fixture_path "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
validate_uptime_file
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
}

run_resolve_to_named_variable() {
  local source_file
  source_file="$(source_cli_without_main)"
  CLI_OUTPUT="$(run_in_fixture_path "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
resolve_executable fixture_uv HRT_UV_BIN uv
printf '%s\n' "$fixture_uv"
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
}

run_install_and_print_uv() {
  local source_file
  source_file="$(source_cli_without_main)"
  CLI_OUTPUT="$(run_in_fixture_path "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
resolve_executable UV_BIN HRT_UV_BIN uv
printf '%s\n' "$UV_BIN"
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
}

new_conforming_case() {
  new_case "$1"
  mkdir -p "$HRT_HEADROOM_DEPLOY_ROOT/default"
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' \
    > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  printf '%s\n' '[Unit]' > "$HRT_SYSTEMD_USER_DIR/headroom-default.service"
  export HRT_FIX_HEADROOM_VERSION=0.37.0
  export HRT_FIX_SERVICE_ENABLED=enabled
  export HRT_FIX_SERVICE_ACTIVE=active
  export HRT_FIX_CURL_BODY='{"ready":true,"version":"0.37.0"}'
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))'
  unset HRT_FIX_HEADROOM_PLUGINS HRT_FIX_CURL_STATUS HRT_FIX_EXEC_MAIN_STATUS \
    HRT_FIX_OPENCODE_ACTIVE HRT_FIX_OPENCODE_PID HRT_FIX_MANIFEST_MODE \
    HRT_FIX_HEADROOM_PLUGINS_STATUS HRT_FIX_STAT_STATUS

  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
if [[ "$1" == "--version" ]]; then printf 'headroom %s\n' "$HRT_FIX_HEADROOM_VERSION"; exit 0; fi
if [[ "$1 $2" == "plugins list" ]]; then printf '%s\n' "${HRT_FIX_HEADROOM_PLUGINS:-}"; exit "${HRT_FIX_HEADROOM_PLUGINS_STATUS:-0}"; fi
exit 0
STUB
  } > "$HRT_HEADROOM_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
case "$*" in
  *'is-enabled headroom-default.service'*) printf '%s\n' "$HRT_FIX_SERVICE_ENABLED" ;;
  *'is-active headroom-default.service'*) printf '%s\n' "$HRT_FIX_SERVICE_ACTIVE" ;;
  *'show headroom-default.service'*'ExecMainStatus'*) printf '%s\n' "${HRT_FIX_EXEC_MAIN_STATUS:-0}" ;;
  *'is-active opencode.service'*) printf '%s\n' "${HRT_FIX_OPENCODE_ACTIVE:-inactive}" ;;
  *'show opencode.service'*'MainPID'*) printf '%s\n' "${HRT_FIX_OPENCODE_PID:-0}" ;;
esac
STUB
  } > "$HRT_SYSTEMCTL_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' "$HRT_FIX_CURL_BODY"
exit "${HRT_FIX_CURL_STATUS:-0}"
STUB
  } > "$HRT_CURL_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' "$HRT_FIX_SS_OUTPUT"
STUB
  } > "$HRT_SS_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' "${HRT_FIX_MANIFEST_MODE:-600}"
exit "${HRT_FIX_STAT_STATUS:-0}"
STUB
  } > "$HRT_STAT_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'exit 99'
  } > "$CASE_DIR/bin/telegram"
  chmod 0755 "$CASE_DIR/bin/telegram"
  chmod 0755 "$HRT_HEADROOM_BIN" "$HRT_SYSTEMCTL_BIN" "$HRT_CURL_BIN" "$HRT_SS_BIN" "$HRT_STAT_BIN"
}

test_conforming_runtime_passes() {
  new_conforming_case conforming
  run_cli audit
  assert_equal "$CLI_STATUS" "0" "a conforming runtime must pass"
  assert_contains "$CLI_OUTPUT" "Status: PASS" "human output must report PASS"
}

test_json_audit_has_stable_shape() {
  new_conforming_case json
  run_cli audit --json
  assert_equal "$CLI_STATUS" "0" "JSON audit must pass"
  assert_equal "$("$JQ_BIN" -r '.schemaVersion' <<<"$CLI_OUTPUT")" "1" \
    "JSON schema version must be one"
  assert_equal "$("$JQ_BIN" -r '.toolVersion' <<<"$CLI_OUTPUT")" "0.1.0" \
    "toolVersion must identify the toolkit component"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" "PASS" \
    "JSON status must match human status"
}

assert_audit_finding() {
  local expected_status="$1"
  local expected_code="$2"

  run_cli audit
  assert_equal "$CLI_STATUS" "$expected_status" "audit must classify $expected_code"
  assert_contains "$CLI_OUTPUT" "$expected_code" "audit must report $expected_code"
}

assert_json_finding_array() {
  local expected_severity="$1"
  local expected_codes="$2"

  assert_equal "$("$JQ_BIN" -r '[.findings[].severity] | join(",")' <<<"$CLI_OUTPUT")" \
    "$expected_severity" "JSON finding severities must be ordered"
  assert_equal "$("$JQ_BIN" -r '[.findings[].code] | join(",")' <<<"$CLI_OUTPUT")" \
    "$expected_codes" "JSON finding codes must be ordered"
}

test_audit_policy_and_error_findings() {
  new_conforming_case version
  export HRT_FIX_HEADROOM_VERSION=0.36.0
  assert_audit_finding 1 HEADROOM_VERSION_MISMATCH

  new_conforming_case suffixed-version
  export HRT_FIX_HEADROOM_VERSION=0.37.0-dev
  assert_audit_finding 1 HEADROOM_VERSION_MISMATCH

  new_conforming_case readiness-version
  export HRT_FIX_CURL_BODY='{"ready":true,"version":"0.36.0"}'
  assert_audit_finding 1 HEADROOM_READINESS_VERSION_MISMATCH

  new_conforming_case readiness-missing-version
  export HRT_FIX_CURL_BODY='{"ready":true}'
  assert_audit_finding 2 HEADROOM_READINESS_INVALID

  new_conforming_case disabled
  export HRT_FIX_SERVICE_ENABLED=disabled
  assert_audit_finding 1 HEADROOM_SERVICE_DISABLED

  new_conforming_case inactive
  export HRT_FIX_SERVICE_ACTIVE=inactive
  assert_audit_finding 1 HEADROOM_SERVICE_INACTIVE

  new_conforming_case not-ready
  export HRT_FIX_CURL_STATUS=22
  assert_audit_finding 1 HEADROOM_NOT_READY

  new_conforming_case invalid-readiness
  export HRT_FIX_CURL_BODY=not-json
  assert_audit_finding 2 HEADROOM_READINESS_INVALID

  new_conforming_case unsafe-bind
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 0.0.0.0:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))'
  assert_audit_finding 1 HEADROOM_UNSAFE_BIND

  new_conforming_case foreign-listener
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("other",pid=42,fd=3))'
  assert_audit_finding 1 HEADROOM_FOREIGN_LISTENER

  new_conforming_case unknown-listener
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:*'
  assert_audit_finding 2 HEADROOM_LISTENER_OWNER_AMBIGUOUS

  new_conforming_case mixed-listeners
  export HRT_FIX_SS_OUTPUT=$'LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))\nLISTEN 0 4096 0.0.0.0:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))'
  assert_audit_finding 1 HEADROOM_UNSAFE_BIND

  new_conforming_case ipv6-listener
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 [::1]:8787 [::]:* users:(("headroom",pid=42,fd=3))'
  assert_audit_finding 1 HEADROOM_UNSAFE_BIND

  new_conforming_case unanchored-owner
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("other-headroom-helper",pid=42,fd=3))'
  assert_audit_finding 1 HEADROOM_FOREIGN_LISTENER

  new_conforming_case shared-listener
  export HRT_FIX_SS_OUTPUT='LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3),("other",pid=43,fd=3))'
  assert_audit_finding 1 HEADROOM_FOREIGN_LISTENER

  new_conforming_case unreadable-manifest
  rm "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 2 HEADROOM_MANIFEST_UNREADABLE

  new_conforming_case invalid-manifest
  printf '%s\n' not-json > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 2 HEADROOM_MANIFEST_INVALID

  new_conforming_case manifest-missing-base-env
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 2 HEADROOM_MANIFEST_INVALID

  new_conforming_case manifest-wrong-array-shape
  printf '%s\n' '{"profile":"default","targets":{},"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 2 HEADROOM_MANIFEST_INVALID

  new_conforming_case profile
  printf '%s\n' '{"profile":"other","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_PROFILE_MISMATCH

  new_conforming_case targets
  printf '%s\n' '{"profile":"default","targets":["opencode"],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_TARGETS_CONFIGURED

  new_conforming_case mutations
  printf '%s\n' '{"profile":"default","targets":[],"mutations":["x"],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_MUTATIONS_PRESENT

  new_conforming_case memory
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":true,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_MEMORY_ENABLED

  new_conforming_case telemetry
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":true,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_TELEMETRY_ENABLED

  new_conforming_case telemetry-environment
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"on"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_TELEMETRY_ENV_ENABLED

  new_conforming_case beacon
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"on","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_BEACON_NOT_DISABLED

  new_conforming_case update-check
  printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"on","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  assert_audit_finding 1 HEADROOM_UPDATE_CHECK_NOT_DISABLED
}

test_audit_opencode_isolation_findings() {
  new_conforming_case package
  export HRT_FIX_HEADROOM_PLUGINS=headroom-opencode
  assert_audit_finding 1 HEADROOM_OPENCODE_PACKAGE_PRESENT

  new_conforming_case config
  printf '%s\n' '{"plugin":"headroom-opencode"}' > "$HRT_OPENCODE_CONFIG_DIR/opencode.json"
  assert_audit_finding 1 HEADROOM_OPENCODE_CONFIG_PRESENT

  new_conforming_case explicit-config
  export OPENCODE_CONFIG="$CASE_DIR/explicit.jsonc"
  printf '%s\n' '{"env":{"HEADROOM_PROXY_URL":"http://127.0.0.1:8787"}}' > "$OPENCODE_CONFIG"
  assert_audit_finding 1 HEADROOM_OPENCODE_CONFIG_PRESENT

  new_conforming_case unreadable-config
  mkdir "$HRT_OPENCODE_CONFIG_DIR/opencode.json"
  assert_audit_finding 2 HEADROOM_OPENCODE_CONFIG_UNREADABLE

  new_conforming_case environment
  export HRT_FIX_OPENCODE_ACTIVE=active HRT_FIX_OPENCODE_PID=88
  mkdir -p "$HRT_PROC_ROOT/88"
  printf 'HEADROOM_PROXY_URL=http://127.0.0.1:8787\0SENSITIVE_SENTINEL_DO_NOT_PRINT=keep\0' > "$HRT_PROC_ROOT/88/environ"
  assert_audit_finding 1 HEADROOM_OPENCODE_ENV_PRESENT
  [[ "$CLI_OUTPUT" != *SENSITIVE_SENTINEL_DO_NOT_PRINT* ]] ||
    fail "Headroom environment finding must not expose unrelated environment values"

  new_conforming_case unreadable-environment
  export HRT_FIX_OPENCODE_ACTIVE=active HRT_FIX_OPENCODE_PID=88
  assert_audit_finding 2 HEADROOM_OPENCODE_ENV_UNREADABLE

  new_conforming_case coupled-unit
  printf '%s\n' 'Requires=headroom-default.service' > "$HRT_SYSTEMD_USER_DIR/opencode.service"
  assert_audit_finding 1 HEADROOM_OPENCODE_UNIT_COUPLED

  new_conforming_case coupled-drop-in
  mkdir -p "$HRT_SYSTEMD_USER_DIR/opencode.service.d"
  printf '%s\n' 'After=headroom-default.service' > "$HRT_SYSTEMD_USER_DIR/opencode.service.d/10-headroom.conf"
  assert_audit_finding 1 HEADROOM_OPENCODE_UNIT_COUPLED
}

test_audit_accepts_uncoupled_opencode_global_surfaces() {
  new_conforming_case global-configs
  printf '%s\n' '{"agent":{"default":"build"}}' > "$HRT_OPENCODE_CONFIG_DIR/opencode.json"
  printf '%s\n' '{// reviewed JSONC configuration
"theme":"dark"}' > "$HRT_OPENCODE_CONFIG_DIR/opencode.jsonc"
  mkdir -p "$CASE_DIR/project/.opencode"
  printf '%s\n' '{"plugin":"headroom-opencode"}' > "$CASE_DIR/project/opencode.json"
  export HRT_FIX_OPENCODE_ACTIVE=inactive
  run_cli_from "$CASE_DIR/project" audit
  assert_equal "$CLI_STATUS" 0 "stopped OpenCode with uncoupled global config must pass"
  assert_contains "$CLI_OUTPUT" "Status: PASS" "uncoupled global config must remain accepted"
}

test_audit_warning_and_non_invocation_boundaries() {
  new_conforming_case kompress
  export HRT_FIX_CURL_BODY='{"ready":true,"version":"0.37.0","kompress":{"ready":false}}'
  run_cli audit --json
  assert_equal "$CLI_STATUS" 0 "optional Kompress degradation must not fail audit"
  assert_contains "$CLI_OUTPUT" HEADROOM_KOMPRESS_OPTIONAL_DEGRADED "Kompress warning must be reported"
  local first_json="$CLI_OUTPUT"
  run_cli audit --json
  assert_equal "$CLI_OUTPUT" "$first_json" "warning JSON must be deterministic"

  new_conforming_case permissions
  export HRT_FIX_MANIFEST_MODE=644
  assert_audit_finding 0 HEADROOM_PERMISSIONS_BROAD

  local mode
  for mode in 0600 0400 0000; do
    new_conforming_case "owner-only-permissions-$mode"
    export HRT_FIX_MANIFEST_MODE="$mode"
    run_cli audit
    assert_equal "$CLI_STATUS" 0 "owner-only mode $mode must not warn"
    [[ "$CLI_OUTPUT" != *HEADROOM_PERMISSIONS_BROAD* ]] ||
      fail "owner-only mode $mode must not report broad permissions"
  done

  for mode in 0040 0044 0007 0440 0644 1600 2600 4600; do
    new_conforming_case "broad-permissions-$mode"
    export HRT_FIX_MANIFEST_MODE="$mode"
    assert_audit_finding 0 HEADROOM_PERMISSIONS_BROAD
  done

  new_conforming_case invalid-permissions
  export HRT_FIX_MANIFEST_MODE=invalid
  assert_audit_finding 2 HEADROOM_PERMISSIONS_UNREADABLE

  new_conforming_case unreadable-permissions
  export HRT_FIX_STAT_STATUS=1
  assert_audit_finding 2 HEADROOM_PERMISSIONS_UNREADABLE

  new_conforming_case lifecycle
  export HRT_FIX_EXEC_MAIN_STATUS=241
  assert_audit_finding 0 HEADROOM_LIFECYCLE_EXIT_241

  new_conforming_case telegram
  run_cli audit
  assert_equal "$CLI_STATUS" 0 "audit must not invoke unrelated Telegram tooling"

  new_conforming_case environment-value-redaction
  export HRT_FIX_OPENCODE_ACTIVE=active HRT_FIX_OPENCODE_PID=89
  mkdir -p "$HRT_PROC_ROOT/89"
  printf 'SENSITIVE_SENTINEL_DO_NOT_PRINT=keep\0' > "$HRT_PROC_ROOT/89/environ"
  run_cli audit
  assert_equal "$CLI_STATUS" 0 "unrelated OpenCode environment values must not affect audit"
  [[ "$CLI_OUTPUT" != *SENSITIVE_SENTINEL_DO_NOT_PRINT* ]] || fail "human audit must not print environment values"
  run_cli audit --json
  [[ "$CLI_OUTPUT" != *SENSITIVE_SENTINEL_DO_NOT_PRINT* ]] || fail "JSON audit must not print environment values"

  new_conforming_case status-agreement-warn
  export HRT_FIX_EXEC_MAIN_STATUS=241
  run_cli audit
  local human_warn="$CLI_OUTPUT"
  run_cli audit --json
  assert_contains "$human_warn" "Status: WARN" "human warning status must be rendered"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" WARN \
    "JSON warning status must match human output"

  new_conforming_case status-agreement-fail
  export HRT_FIX_SERVICE_ENABLED=disabled
  run_cli audit
  local human_fail="$CLI_OUTPUT"
  run_cli audit --json
  assert_contains "$human_fail" "Status: FAIL" "human failure status must be rendered"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" FAIL \
    "JSON failure status must match human output"

  new_conforming_case ordered-findings
  export HRT_FIX_SERVICE_ENABLED=disabled HRT_FIX_SERVICE_ACTIVE=inactive
  run_cli audit --json
  assert_equal "$CLI_STATUS" 1 "multiple policy violations must fail audit"
  assert_json_finding_array 'FAIL,FAIL' 'HEADROOM_SERVICE_DISABLED,HEADROOM_SERVICE_INACTIVE'
}

test_normal_json_renderer_failure_is_atomic() {
  new_conforming_case partial-normal-jq-renderer
  export HRT_FIX_CURL_BODY='{"ready":true,"version":"0.37.0","kompress":{"ready":false}}'
  export HRT_REAL_JQ_BIN="$JQ_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
if [[ "$1" == -n ]]; then
  printf '%s\n' '{"partial":true}'
  exit 1
fi
exec "$HRT_REAL_JQ_BIN" "$@"
STUB
  } > "$CASE_DIR/bin/jq-partial"
  chmod 0755 "$CASE_DIR/bin/jq-partial"
  export HRT_JQ_BIN="$CASE_DIR/bin/jq-partial"
  run_cli_split_streams audit --json
  assert_equal "$CLI_STATUS" 2 "a normal JSON renderer failure must fail audit"
  assert_equal "$CLI_STDOUT" \
    '{"schemaVersion":1,"toolVersion":"0.1.0","action":"audit","status":"ERROR","findings":[],"error":"audit command resolution failed"}' \
    "a normal JSON renderer failure must emit only the fixed JSON error envelope"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_STDOUT")" ERROR \
    "a normal JSON renderer failure must leave stdout valid JSON"
}

test_audit_command_and_flag_validation() {
  new_conforming_case missing-curl
  rm "$HRT_CURL_BIN"
  unset HRT_CURL_BIN
  run_cli audit
  assert_equal "$CLI_STATUS" 2 "missing required audit command must fail"
  assert_contains "$CLI_OUTPUT" "curl is required but was not found" "missing command diagnostic must identify curl"

  new_conforming_case missing-headroom-json
  rm "$HRT_HEADROOM_BIN"
  unset HRT_HEADROOM_BIN
  run_cli audit --json
  assert_equal "$CLI_STATUS" 2 "missing Headroom command must error in JSON mode"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" ERROR \
    "JSON command failure must retain the audit envelope"
  assert_contains "$CLI_OUTPUT" "headroom is required but was not found" \
    "JSON command failure must retain the command-specific diagnostic"
  assert_equal "$("$JQ_BIN" -r '[.findings[].code] | join(",")' <<<"$CLI_OUTPUT")" '' \
    "command resolution must not invent an audit finding code"

  new_conforming_case non-executable-headroom-json
  chmod 0644 "$HRT_HEADROOM_BIN"
  run_cli audit --json
  assert_equal "$CLI_STATUS" 2 "a non-executable Headroom seam must error in JSON mode"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" ERROR \
    "non-executable command resolution must retain the audit envelope"
  assert_contains "$CLI_OUTPUT" "HRT_HEADROOM_BIN must name an executable path" \
    "non-executable command diagnostic must identify the seam"

  new_conforming_case unavailable-headroom-command
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'exit 127'
  } > "$HRT_HEADROOM_BIN"
  chmod 0755 "$HRT_HEADROOM_BIN"
  run_cli audit
  assert_equal "$CLI_STATUS" 2 "a resolved Headroom CLI that cannot report its version must error"
  assert_contains "$CLI_OUTPUT" HEADROOM_VERSION_UNREADABLE \
    "unreadable Headroom version must have its own finding code"

  new_conforming_case package-list-error
  export HRT_FIX_HEADROOM_PLUGINS_STATUS=1
  run_cli audit
  assert_equal "$CLI_STATUS" 2 "package-list inspection failures must be errors"
  assert_contains "$CLI_OUTPUT" HEADROOM_OPENCODE_PACKAGE_UNREADABLE \
    "package-list inspection failures must report their finding code"
  [[ "$CLI_OUTPUT" != *HEADROOM_OPENCODE_PACKAGE_PRESENT* ]] ||
    fail "package-list inspection failures must not claim the package is present"

  new_conforming_case invalid-flags
  run_cli audit --dry-run
  assert_equal "$CLI_STATUS" 2 "audit dry-run must be rejected"
  run_cli install --json
  assert_equal "$CLI_STATUS" 2 "install JSON must be rejected"
  run_cli remove --json
  assert_equal "$CLI_STATUS" 2 "remove JSON must be rejected"

  new_conforming_case invalid-json-audit-option
  run_cli audit --json $'--invalid\n\001'
  assert_equal "$CLI_STATUS" 2 "invalid audit JSON option must be a usage error"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_OUTPUT")" ERROR \
    "invalid audit JSON option must emit a valid error envelope"

  new_conforming_case fixture-path-jq-resolution
  ln -s "$JQ_BIN" "$CASE_DIR/bin/jq"
  unset HRT_JQ_BIN
  run_cli_split_streams audit --json $'--invalid\n\001'
  assert_equal "$CLI_STATUS" 2 "fixture-path jq must preserve audit usage status"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_STDOUT")" ERROR \
    "fixture-path jq must render a valid error envelope"
  assert_contains "$("$JQ_BIN" -r '.error' <<<"$CLI_STDOUT")" 'unknown audit option' \
    "fixture-path jq error envelope must retain the diagnostic"
  assert_equal "$CLI_STDERR" '' "fixture-path jq must not emit a fallback diagnostic"

  new_conforming_case missing-jq-fallback
  unset HRT_JQ_BIN
  run_cli_split_streams audit --json $'--invalid\n\001'
  assert_equal "$CLI_STATUS" 2 "missing jq fallback must preserve audit usage status"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_STDOUT")" ERROR \
    "missing jq fallback must keep stdout valid JSON"
  assert_equal "$("$JQ_BIN" -r '.error' <<<"$CLI_STDOUT")" 'audit command resolution failed' \
    "missing jq fallback must use a fixed JSON diagnostic"
  assert_contains "$CLI_STDERR" 'unknown audit option' \
    "missing jq fallback must preserve unsafe detail on stderr"

  new_conforming_case failing-jq-renderer
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'exit 1'
  } > "$CASE_DIR/bin/jq-failing"
  chmod 0755 "$CASE_DIR/bin/jq-failing"
  export HRT_JQ_BIN="$CASE_DIR/bin/jq-failing"
  run_cli_split_streams audit --json --invalid
  assert_equal "$CLI_STATUS" 2 "a failed jq renderer must not change the usage exit code"

  new_conforming_case partial-jq-renderer
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'printf "%s\\n" '\''{"partial":true}'\'''
    printf '%s\n' 'exit 1'
  } > "$CASE_DIR/bin/jq-partial"
  chmod 0755 "$CASE_DIR/bin/jq-partial"
  export HRT_JQ_BIN="$CASE_DIR/bin/jq-partial"
  run_cli_split_streams audit --json --invalid
  assert_equal "$CLI_STATUS" 2 "a partial jq renderer failure must preserve the usage exit code"
  assert_equal "$CLI_STDOUT" \
    '{"schemaVersion":1,"toolVersion":"0.1.0","action":"audit","status":"ERROR","findings":[],"error":"audit command resolution failed"}' \
    "a failed jq renderer must emit only the fixed JSON error envelope"
  assert_equal "$("$JQ_BIN" -r '.status' <<<"$CLI_STDOUT")" ERROR \
    "a partial jq renderer failure must leave stdout valid JSON"
  assert_contains "$CLI_STDERR" 'unknown audit option' \
    "a partial jq renderer failure must preserve detail on stderr"

  new_conforming_case empty-jq-resolution-renderer
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'exit 0'
  } > "$CASE_DIR/bin/jq-empty"
  chmod 0755 "$CASE_DIR/bin/jq-empty"
  export HRT_JQ_BIN="$CASE_DIR/bin/jq-empty"
  run_cli_split_streams audit --json --invalid
  assert_equal "$CLI_STATUS" 2 "an empty jq resolution renderer must preserve the usage exit code"
  assert_equal "$CLI_STDOUT" \
    '{"schemaVersion":1,"toolVersion":"0.1.0","action":"audit","status":"ERROR","findings":[],"error":"audit command resolution failed"}' \
    "an empty jq resolution renderer must emit the fixed JSON error envelope"
  assert_contains "$CLI_STDERR" 'unknown audit option' \
    "an empty jq resolution renderer must preserve detail on stderr"
}

test_version_is_exact() {
  new_case version
  run_cli --version
  assert_equal "$CLI_STATUS" "0" "--version must succeed"
  assert_equal "$CLI_OUTPUT" "0.1.0" "--version must print only the tool version"
}

test_help_lists_the_three_commands() {
  new_case help
  run_cli --help
  assert_equal "$CLI_STATUS" "0" "--help must succeed"
  assert_contains "$CLI_OUTPUT" "install [--dry-run]" "help must document install"
  assert_contains "$CLI_OUTPUT" "audit [--json]" "help must document audit"
  assert_contains "$CLI_OUTPUT" "remove [--dry-run] [--uninstall-tool]" \
    "help must document remove"
}

test_unknown_command_is_usage_error() {
  new_case unknown
  run_cli unknown
  assert_equal "$CLI_STATUS" "2" "unknown commands must exit 2"
}

test_relative_binary_override_is_rejected() {
  new_case relative-override
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  # shellcheck disable=SC2031 # run_cli intentionally executes the exported fixture seam in a child.
  export HRT_UV_BIN=relative/uv
  run_cli install --dry-run
  unset HRT_UV_BIN
  assert_equal "$CLI_STATUS" "2" "executable seams must be absolute"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must be an absolute executable path" \
    "the diagnostic must identify the unsafe seam"
}

test_install_resolves_the_fixture_uv_path() {
  new_case install-resolves-uv
  run_install_and_print_uv
  assert_equal "$CLI_STATUS" "0" "install dry-run must resolve a valid fixture uv"
  assert_equal "$CLI_OUTPUT" "$HRT_UV_BIN" \
    "install must retain the absolute fixture uv path in UV_BIN"
}

test_resolver_assigns_a_caller_named_output_variable() {
  new_case resolver-indirection
  run_resolve_to_named_variable
  assert_equal "$CLI_STATUS" "0" "a named resolver output variable must be supported"
  assert_equal "$CLI_OUTPUT" "$HRT_UV_BIN" \
    "the resolver must assign its validated path to the requested variable"
}

test_invalid_override_exits_even_in_a_conditional() {
  new_case conditional-override
  run_resolve_in_conditional
  assert_equal "$CLI_STATUS" "2" "unsafe overrides must exit from the current shell"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must be an absolute executable path" \
    "conditional resolution must retain the unsafe seam diagnostic"
  [[ "$CLI_OUTPUT" != *"validation was ignored"* ]] ||
    fail "unsafe seam validation must not be ignored by a conditional"
}

test_uptime_file_uses_the_fixture_override() {
  new_case uptime-file
  read_uptime_file
  assert_equal "$CLI_STATUS" "0" "loading the CLI constants must succeed"
  assert_equal "$CLI_OUTPUT" "$CASE_DIR/uptime" \
    "UPTIME_FILE must use the controlled fixture seam"
}

test_uptime_file_defaults_to_proc_uptime() {
  new_case uptime-default
  unset HRT_UPTIME_FILE
  read_uptime_file
  assert_equal "$CLI_STATUS" "0" "loading the CLI constants must succeed"
  assert_equal "$CLI_OUTPUT" "/proc/uptime" \
    "UPTIME_FILE must default to the system uptime source"
}

test_relative_uptime_override_is_rejected() {
  new_case relative-uptime
  export HRT_UPTIME_FILE=relative/uptime
  run_validate_uptime_file
  unset HRT_UPTIME_FILE
  assert_equal "$CLI_STATUS" "2" "an unsafe uptime seam must be rejected"
  assert_contains "$CLI_OUTPUT" "HRT_UPTIME_FILE must be an absolute readable path" \
    "the uptime seam diagnostic must identify the unsafe path"
}

test_version_does_not_require_an_uptime_file() {
  new_case version-with-unsafe-uptime
  export HRT_UPTIME_FILE=relative/uptime
  run_cli --version
  unset HRT_UPTIME_FILE
  assert_equal "$CLI_STATUS" "0" "--version must not inspect uptime state"
  assert_equal "$CLI_OUTPUT" "0.1.0" "--version must remain independent of uptime"
}

test_missing_uv_seam_cannot_fall_back_to_the_host() {
  new_case missing-uv
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  rm "$CASE_DIR/bin/uv"
  unset HRT_UV_BIN
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" "2" "an unavailable fixture command must be a usage error"
  assert_contains "$CLI_OUTPUT" "uv is required but was not found" \
    "missing uv must not resolve from the host PATH"
  assert_contains "$CLI_OUTPUT" "uv is required but was not found" \
    "an omitted seam must not invoke a host uv command"
}

test_default_uv_resolution_rejects_a_non_executable_canonical_path() {
  new_case default-uv-non-executable
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  unset HRT_UV_BIN
  export HRT_READLINK_TARGET="$CASE_DIR/not-executable"
  run_cli install --dry-run
  unset HRT_READLINK_TARGET
  assert_equal "$CLI_STATUS" "2" "a default must resolve to an executable path"
  assert_contains "$CLI_OUTPUT" "uv resolved to a non-executable path" \
    "a broken canonical default must identify the command"
}

test_non_executable_override_is_rejected() {
  new_case non-executable-override
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  chmod 0644 "$HRT_UV_BIN"
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" "2" "non-executable seams must be rejected"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must name an executable path" \
    "the diagnostic must distinguish an unusable executable seam"
}

test_shipped_file_modes_and_entrypoint_are_preserved() {
  local line
  local last_line=""
  local cli_mode
  local test_mode

  [[ -x "$CLI" ]] || fail "the production CLI must be executable"
  [[ ! -x "$REPOSITORY_ROOT/tests/headroom-runtime.sh" ]] ||
    fail "the test suite must not be executable"
  while IFS= read -r line; do
    last_line="$line"
  done < "$CLI"
  assert_equal "$last_line" 'main "$@"' "main must remain the final production line"
  local cli_record
  local test_record

  cli_record="$(git -C "$REPOSITORY_ROOT" ls-files -s -- "$CLI_PATH")"
  test_record="$(git -C "$REPOSITORY_ROOT" ls-files -s -- "$TEST_PATH")"
  [[ -n "$cli_record" ]] || fail "the production CLI must have a tracked Git entry"
  [[ -n "$test_record" ]] || fail "the test suite must have a tracked Git entry"
  IFS=' ' read -r cli_mode _ <<<"$cli_record"
  IFS=' ' read -r test_mode _ <<<"$test_record"
  assert_equal "$cli_mode" "100755" "the production CLI must be tracked executable"
  assert_equal "$test_mode" "100644" "the test suite must be tracked non-executable"
}

new_installable_absent_case() {
  new_case "$1"
  unset HRT_FIX_HEADROOM_VERSION HRT_FIX_HEADROOM_PLUGINS HRT_FIX_EXEC_MAIN_STATUS \
    HRT_FIX_OPENCODE_ACTIVE HRT_FIX_OPENCODE_PID HRT_FIX_SS_OUTPUT
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  local headroom_template="$HRT_HEADROOM_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' '---' "$0" "$@" >> "$HRT_COMMAND_LOG"
if [[ "$1 $2" == 'tool install' ]]; then
  printf '%s\n' '---' "$0" "$@" >> "$HRT_MUTATION_LOG"
  : > "$HRT_HOME/package-installed"
  /bin/mkdir -p "$HRT_HOME/.local/bin"
  /bin/cp "$HRT_HEADROOM_TEMPLATE" "$HRT_HOME/.local/bin/headroom"
  /bin/chmod 0755 "$HRT_HOME/.local/bin/headroom"
  : > "$HRT_HOME/service-applied"
fi
STUB
  } > "$HRT_UV_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' "printf 'Linux\\n'"
  } > "$HRT_UNAME_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
case "$*" in
  *'is-enabled headroom-default.service'*) [[ -f "$HRT_SYSTEMD_USER_DIR/headroom-default.service" ]] && printf 'enabled\n' || printf 'disabled\n' ;;
  *'is-active headroom-default.service'*) [[ -f "$HRT_SYSTEMD_USER_DIR/headroom-default.service" ]] && printf 'active\n' || printf 'inactive\n' ;;
  *'show headroom-default.service'*'ExecMainStatus'*) printf '0\n' ;;
  *'is-active opencode.service'*) printf '%s\n' "${HRT_FIX_OPENCODE_ACTIVE:-inactive}" ;;
  *'show opencode.service'*'MainPID'*) printf '%s\n' "${HRT_FIX_OPENCODE_PID:-0}" ;;
esac
STUB
  } > "$HRT_SYSTEMCTL_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
case "$1 $2" in
  '--version ')
    [[ -f "$HRT_HOME/package-installed" ]] || exit 1
    printf 'headroom %s\n' "${HRT_FIX_HEADROOM_VERSION:-0.37.0}"
    ;;
  'plugins list') printf '%s\n' "${HRT_FIX_HEADROOM_PLUGINS:-}" ;;
  'install apply')
    printf '%s\n' '---' "$0" "$@" >> "$HRT_MUTATION_LOG"
    /bin/mkdir -p "$HRT_HEADROOM_DEPLOY_ROOT/default"
    printf '%s\n' '{"profile":"default","targets":[],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
    printf '%s\n' '[Unit]' > "$HRT_SYSTEMD_USER_DIR/headroom-default.service"
    : > "$HRT_HOME/service-applied"
    ;;
esac
STUB
  } > "$headroom_template"
  export HRT_HEADROOM_TEMPLATE="$headroom_template"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' '---' "$0" "$@" >> "$HRT_COMMAND_LOG"
printf '%s\n' 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process'
if [[ -n "${HRT_FIX_SS_OUTPUT:-}" ]]; then
  printf '%s\n' "$HRT_FIX_SS_OUTPUT"
elif [[ -f "$HRT_HOME/service-applied" ]]; then
  printf '%s\n' 'tcp LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))'
fi
STUB
  } > "$HRT_SS_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' "printf '%s\\n' '{\"ready\":true,\"version\":\"0.37.0\"}'"
  } > "$HRT_CURL_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' "printf '600\\n'"
  } > "$HRT_STAT_BIN"
  {
    printf '#!%s\n' "$BASH_BIN"
    cat <<'STUB'
printf '%s\n' '---' "$0" "$@" >> "$HRT_COMMAND_LOG"
printf '%s\n' '31.00 0.00' > "$HRT_UPTIME_FILE"
STUB
  } > "$HRT_SLEEP_BIN"
  chmod 0755 "$HRT_UNAME_BIN" "$HRT_SYSTEMCTL_BIN" "$headroom_template" \
    "$HRT_SS_BIN" "$HRT_CURL_BIN" "$HRT_STAT_BIN" "$HRT_SLEEP_BIN"
  /bin/cp "$headroom_template" "$HRT_HOME/headroom-template"
  export HRT_HEADROOM_TEMPLATE="$HRT_HOME/headroom-template"
  rm "$headroom_template"
  unset HRT_HEADROOM_BIN
}

test_install_absent_uses_the_exact_approved_commands() {
  new_installable_absent_case install-absent
  export HRT_FIX_SS_OUTPUT=''
  run_cli install
  assert_equal "$CLI_STATUS" 0 "an absent runtime must install"
  assert_equal "$(<"$HRT_MUTATION_LOG")" "---
$HRT_UV_BIN
tool
install
--python
3.13
headroom-ai[proxy]==0.37.0
---
$HRT_HOME/.local/bin/headroom
install
apply
--preset
persistent-service
--runtime
python
--scope
provider
--providers
manual
--profile
default
--port
8787
--mode
cache
--no-telemetry
--env
HEADROOM_BEACON=off
--env
HEADROOM_UPDATE_CHECK=off" "install must use the approved package and no-target apply arguments"
  [[ "$(<"$HRT_MUTATION_LOG")" != *'--target'* && "$(<"$HRT_MUTATION_LOG")" != *'user'* &&
    "$(<"$HRT_MUTATION_LOG")" != *'auto'* && "$(<"$HRT_MUTATION_LOG")" != *'deploy'* &&
    "$(<"$HRT_MUTATION_LOG")" != *'wrap'* && "$(<"$HRT_MUTATION_LOG")" != *'[all]'* &&
    "$(<"$HRT_MUTATION_LOG")" != *'[ml]'* ]] || fail "apply must retain its service-only boundary"
}

test_install_dry_run_prints_but_does_not_mutate() {
  new_installable_absent_case install-dry-run
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "an absent runtime dry-run must succeed"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "dry-run must not invoke mutation stubs"
  assert_contains "$CLI_OUTPUT" 'headroom-ai\[proxy\]==0.37.0' "dry-run must print package installation"
  assert_contains "$CLI_OUTPUT" '--providers manual' "dry-run must print the service-only apply command"
}

test_install_rejects_an_invalid_uptime_source_before_mutation() {
  new_installable_absent_case install-invalid-uptime
  export HRT_UPTIME_FILE=relative/uptime
  run_cli install
  unset HRT_UPTIME_FILE
  assert_equal "$CLI_STATUS" 2 "install must validate its readiness uptime source"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "invalid install uptime must block mutations"
}

test_absent_headroom_without_a_seam_dry_runs_with_future_path() {
  new_installable_absent_case absent-headroom-without-seam
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "a fresh dry-run must not require a Headroom binary"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "a fresh dry-run must not mutate"
  assert_contains "$CLI_OUTPUT" "$HRT_HOME/.local/bin/headroom install apply" \
    "a fresh dry-run must display the future uv tool executable"
  assert_contains "$(<"$HRT_COMMAND_LOG")" "$HRT_SS_BIN" \
    "a fresh dry-run must perform read-only preflight probes"
}

test_install_refuses_opencode_coupling_before_mutation() {
  local case_name

  for case_name in config package environment drop-in; do
    new_installable_absent_case "coupling-$case_name"
    case "$case_name" in
      config) printf '%s\n' '{"plugin":"headroom-opencode"}' > "$HRT_OPENCODE_CONFIG_DIR/opencode.json" ;;
      package)
        /bin/mkdir -p "$HRT_HOME/.local/bin"
        /bin/cp "$HRT_HEADROOM_TEMPLATE" "$HRT_HOME/.local/bin/headroom"
        /bin/chmod 0755 "$HRT_HOME/.local/bin/headroom"
        export HRT_HEADROOM_BIN="$HRT_HOME/.local/bin/headroom"
        : > "$HRT_HOME/package-installed"
        export HRT_FIX_HEADROOM_PLUGINS=headroom-opencode
        ;;
      environment)
        export HRT_FIX_OPENCODE_ACTIVE=active HRT_FIX_OPENCODE_PID=88
        mkdir -p "$HRT_PROC_ROOT/88"
        printf 'HEADROOM_PROXY_URL=x\0' > "$HRT_PROC_ROOT/88/environ"
        ;;
      drop-in)
        mkdir -p "$HRT_SYSTEMD_USER_DIR/opencode.service.d"
        printf '%s\n' 'After=headroom-default.service' > "$HRT_SYSTEMD_USER_DIR/opencode.service.d/10-headroom.conf"
        ;;
    esac
    run_cli install
    assert_equal "$CLI_STATUS" 1 "$case_name coupling must refuse installation"
    assert_equal "$(<"$HRT_MUTATION_LOG")" '' "$case_name coupling must block every mutation"
    unset HRT_FIX_HEADROOM_PLUGINS HRT_FIX_OPENCODE_ACTIVE HRT_FIX_OPENCODE_PID
  done
}

test_install_state_matrix_core_refusals() {
  new_conforming_case install-stopped
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  export HRT_FIX_SERVICE_ACTIVE=inactive
  run_cli install
  assert_equal "$CLI_STATUS" 1 "a valid stopped deployment must be refused"
  assert_contains "$CLI_OUTPUT" 'systemctl --user start and enable' \
    "a stopped deployment must name the explicit operator action"

  new_conforming_case install-orphaned
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  rm "$HRT_HEADROOM_BIN"
  unset HRT_HEADROOM_BIN
  export HRT_FIX_SS_OUTPUT='tcp LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("headroom",pid=42,fd=3))'
  run_cli install
  assert_equal "$CLI_STATUS" 1 "a deployment without a runtime must be orphaned"
  assert_contains "$CLI_OUTPUT" 'deployment exists without the pinned runtime' \
    "an orphaned deployment must have a specific diagnostic"
  unset HRT_FIX_SS_OUTPUT

  new_conforming_case install-nonconforming
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  printf '%s\n' '{"profile":"default","targets":["x"],"mutations":[],"memory_enabled":false,"telemetry_enabled":false,"base_env":{"HEADROOM_BEACON":"off","HEADROOM_UPDATE_CHECK":"off","HEADROOM_TELEMETRY":"off"}}' > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  run_cli install
  assert_equal "$CLI_STATUS" 1 "a nonconforming deployment must be refused"
  assert_contains "$CLI_OUTPUT" HEADROOM_TARGETS_CONFIGURED \
    "a nonconforming deployment must retain its precise finding"
}

test_install_manifest_and_listener_precedence() {
  new_case install-malformed-overlap
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  mkdir -p "$HRT_HEADROOM_DEPLOY_ROOT/default"
  printf '%s\n' not-json > "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  rm "$HRT_HEADROOM_BIN"
  unset HRT_HEADROOM_BIN
  run_cli install
  assert_equal "$CLI_STATUS" 2 "a malformed manifest must override an absent package"
  assert_contains "$CLI_OUTPUT" HEADROOM_MANIFEST_INVALID "manifest ownership failure must be rendered"

  new_conforming_case install-unreadable-overlap
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  rm "$HRT_HEADROOM_DEPLOY_ROOT/default/manifest.json"
  export HRT_FIX_HEADROOM_VERSION=0.36.0
  run_cli install
  assert_equal "$CLI_STATUS" 2 "an unreadable manifest must override a wrong package"
  assert_contains "$CLI_OUTPUT" HEADROOM_MANIFEST_UNREADABLE "unreadable ownership must be rendered"

  new_installable_absent_case install-foreign-listener
  export HRT_FIX_SS_OUTPUT='tcp LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:* users:(("other",pid=1,fd=3))'
  run_cli install
  assert_equal "$CLI_STATUS" 1 "an attributed foreign listener must be a conflict"

  new_installable_absent_case install-ambiguous-listener
  export HRT_FIX_SS_OUTPUT='tcp LISTEN 0 4096 127.0.0.1:8787 0.0.0.0:*'
  run_cli install
  assert_equal "$CLI_STATUS" 2 "an unattributed listener must be ambiguous"
  unset HRT_FIX_SS_OUTPUT
}

test_install_core_matrix_completion() {
  new_installable_absent_case install-package-only
  /bin/mkdir -p "$HRT_HOME/.local/bin"
  /bin/cp "$HRT_HEADROOM_TEMPLATE" "$HRT_HOME/.local/bin/headroom"
  /bin/chmod 0755 "$HRT_HOME/.local/bin/headroom"
  : > "$HRT_HOME/package-installed"
  export HRT_HEADROOM_BIN="$HRT_HOME/.local/bin/headroom"
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "an exact package without deployment must dry-run apply"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "package-only dry-run must not mutate"
  assert_contains "$CLI_OUTPUT" 'install apply' "package-only dry-run must print apply"
  assert_contains "$(<"$HRT_COMMAND_LOG")" "$HRT_SS_BIN" "package-only dry-run must run read-only probes"

  new_conforming_case install-pass-noop
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "a PASS deployment must be idempotent"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "a PASS deployment must not mutate"

  new_conforming_case install-warn-noop
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  export HRT_FIX_EXEC_MAIN_STATUS=241
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "a WARN deployment must be idempotent"
  assert_equal "$(<"$HRT_MUTATION_LOG")" '' "a WARN deployment must not mutate"

  new_conforming_case install-wrong-version
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  export HRT_FIX_HEADROOM_VERSION=0.36.0
  run_cli install
  assert_equal "$CLI_STATUS" 1 "a wrong package version must be refused"
  assert_contains "$CLI_OUTPUT" 'implicit upgrades are refused' "wrong version must be explicit"

  new_conforming_case install-unreadable-config
  printf '%s\n' '0.00 0.00' > "$HRT_UPTIME_FILE"
  mkdir "$HRT_OPENCODE_CONFIG_DIR/opencode.json"
  run_cli install
  assert_equal "$CLI_STATUS" 2 "an unreadable OpenCode config must be an inspection error"
  assert_contains "$CLI_OUTPUT" HEADROOM_OPENCODE_CONFIG_UNREADABLE "preflight error must retain its code"

  new_installable_absent_case install-non-linux
  printf '%s\n' "printf 'Darwin\\n'" > "$HRT_UNAME_BIN"
  run_cli install
  assert_equal "$CLI_STATUS" 2 "a non-Linux platform must be rejected"

  new_installable_absent_case install-no-systemd
  {
    printf '#!%s\n' "$BASH_BIN"
    printf '%s\n' 'exit 1'
  } > "$HRT_SYSTEMCTL_BIN"
  chmod 0755 "$HRT_SYSTEMCTL_BIN"
  run_cli install
  assert_equal "$CLI_STATUS" 2 "an unusable user systemd must be rejected"

  new_installable_absent_case install-uv-tool-bin
  export UV_TOOL_BIN_DIR="$HRT_HOME/custom-bin"
  /bin/mkdir -p "$UV_TOOL_BIN_DIR"
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" 0 "a UV tool-bin seam must be supported"
  assert_contains "$CLI_OUTPUT" "$UV_TOOL_BIN_DIR/headroom install apply" \
    "dry-run must use the configured uv tool-bin path"
  unset UV_TOOL_BIN_DIR
}

JQ_BIN="$(command -v jq || true)"
[[ -n "$JQ_BIN" ]] || fail "jq is required for Headroom runtime tests"
JQ_BIN="$(readlink -f "$JQ_BIN")"
readonly JQ_BIN
BASH_BIN="$(readlink -f "${BASH:-$(command -v bash)}")"
readonly BASH_BIN
TEMP_DIR="$(mktemp -d)"

test_version_is_exact
test_help_lists_the_three_commands
test_unknown_command_is_usage_error
test_relative_binary_override_is_rejected
test_install_resolves_the_fixture_uv_path
test_resolver_assigns_a_caller_named_output_variable
test_invalid_override_exits_even_in_a_conditional
test_uptime_file_uses_the_fixture_override
test_uptime_file_defaults_to_proc_uptime
test_relative_uptime_override_is_rejected
test_version_does_not_require_an_uptime_file
test_missing_uv_seam_cannot_fall_back_to_the_host
test_default_uv_resolution_rejects_a_non_executable_canonical_path
test_non_executable_override_is_rejected
test_shipped_file_modes_and_entrypoint_are_preserved
test_install_absent_uses_the_exact_approved_commands
test_install_dry_run_prints_but_does_not_mutate
test_install_rejects_an_invalid_uptime_source_before_mutation
test_absent_headroom_without_a_seam_dry_runs_with_future_path
test_install_refuses_opencode_coupling_before_mutation
test_install_state_matrix_core_refusals
test_install_manifest_and_listener_precedence
test_install_core_matrix_completion
test_conforming_runtime_passes
test_json_audit_has_stable_shape
test_audit_policy_and_error_findings
test_audit_opencode_isolation_findings
test_audit_accepts_uncoupled_opencode_global_surfaces
test_audit_warning_and_non_invocation_boundaries
test_normal_json_renderer_failure_is_atomic
test_audit_command_and_flag_validation

printf 'PASS: Headroom runtime tests\n'
