#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CLI="$REPOSITORY_ROOT/headroom-runtime/headroom-runtime.sh"

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
  for command in uv headroom systemctl curl ss uname sleep readlink; do
    cat > "$CASE_DIR/bin/$command" <<'STUB'
#!/bin/bash
if [[ "$0" == */readlink && "$1" == "-f" ]]; then
  printf '%s\n' "${HRT_READLINK_TARGET:-$2}"
  exit 0
fi
printf '%s\n' "$0" "$@" >> "$HRT_COMMAND_LOG"
STUB
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

  export HRT_HOME="$CASE_DIR/home"
  export HRT_PROC_ROOT="$CASE_DIR/proc"
  export HRT_OPENCODE_CONFIG_DIR="$CASE_DIR/opencode"
  export HRT_SYSTEMD_USER_DIR="$CASE_DIR/systemd"
  export HRT_HEADROOM_DEPLOY_ROOT="$CASE_DIR/deploy"
  export HRT_UPTIME_FILE="$CASE_DIR/uptime"
  export HRT_COMMAND_LOG="$CASE_DIR/commands"

  install_stubs
  export HRT_UV_BIN="$CASE_DIR/bin/uv"
  export HRT_HEADROOM_BIN="$CASE_DIR/bin/headroom"
  export HRT_SYSTEMCTL_BIN="$CASE_DIR/bin/systemctl"
  export HRT_CURL_BIN="$CASE_DIR/bin/curl"
  export HRT_JQ_BIN="$JQ_BIN"
  export HRT_SS_BIN="$CASE_DIR/bin/ss"
  export HRT_UNAME_BIN="$CASE_DIR/bin/uname"
  export HRT_SLEEP_BIN="$CASE_DIR/bin/sleep"
}

run_cli() {
  CLI_OUTPUT="$(PATH="$CASE_DIR/bin" "$BASH_BIN" "$CLI" "$@" 2>&1)" &&
    CLI_STATUS=0 || CLI_STATUS=$?
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
  CLI_OUTPUT="$(PATH="$CASE_DIR/bin" HRT_UV_BIN=relative/uv "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
if resolve_executable UV_BIN HRT_UV_BIN uv; then
  printf 'unexpected success\n'
fi
printf 'validation was ignored\n'
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
}

read_uptime_file() {
  local source_file
  source_file="$(source_cli_without_main)"
  CLI_OUTPUT="$(PATH="$CASE_DIR/bin" "$BASH_BIN" -s "$source_file" 2>&1 <<'SCRIPT'
source "$1"
printf '%s\n' "$UPTIME_FILE"
SCRIPT
)" && CLI_STATUS=0 || CLI_STATUS=$?
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
  export HRT_UV_BIN=relative/uv
  run_cli install --dry-run
  unset HRT_UV_BIN
  assert_equal "$CLI_STATUS" "2" "executable seams must be absolute"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must be an absolute executable path" \
    "the diagnostic must identify the unsafe seam"
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

test_missing_uv_seam_cannot_fall_back_to_the_host() {
  new_case missing-uv
  rm "$CASE_DIR/bin/uv"
  unset HRT_UV_BIN
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" "2" "an unavailable fixture command must be a usage error"
  assert_contains "$CLI_OUTPUT" "uv is required but was not found" \
    "missing uv must not resolve from the host PATH"
  assert_equal "$(wc -l < "$HRT_COMMAND_LOG")" "0" \
    "an omitted seam must not invoke any command outside the fixture"
}

test_default_uv_resolution_rejects_a_non_executable_canonical_path() {
  new_case default-uv-non-executable
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
  chmod 0644 "$HRT_UV_BIN"
  run_cli install --dry-run
  assert_equal "$CLI_STATUS" "2" "non-executable seams must be rejected"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must name an executable path" \
    "the diagnostic must distinguish an unusable executable seam"
}

test_shipped_file_modes_and_entrypoint_are_preserved() {
  local line
  local last_line=""

  [[ -x "$CLI" ]] || fail "the production CLI must be executable"
  [[ ! -x "$REPOSITORY_ROOT/tests/headroom-runtime.sh" ]] ||
    fail "the test suite must not be executable"
  while IFS= read -r line; do
    last_line="$line"
  done < "$CLI"
  assert_equal "$last_line" 'main "$@"' "main must remain the final production line"
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
test_invalid_override_exits_even_in_a_conditional
test_uptime_file_uses_the_fixture_override
test_uptime_file_defaults_to_proc_uptime
test_missing_uv_seam_cannot_fall_back_to_the_host
test_default_uv_resolution_rejects_a_non_executable_canonical_path
test_non_executable_override_is_rejected
test_shipped_file_modes_and_entrypoint_are_preserved

printf 'PASS: Headroom runtime tests\n'
