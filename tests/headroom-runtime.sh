#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CLI="$REPOSITORY_ROOT/headroom-runtime/headroom-runtime.sh"

cleanup() {
  rm -rf "${TEMP_DIR:-}"
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
  for command in uv headroom systemctl curl ss uname sleep; do
    cat > "$CASE_DIR/bin/$command" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$0" "$@" >> "$HRT_COMMAND_LOG"
STUB
    chmod 0755 "$CASE_DIR/bin/$command"
  done
}

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
  CLI_OUTPUT="$(bash "$CLI" "$@" 2>&1)" && CLI_STATUS=0 || CLI_STATUS=$?
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

JQ_BIN="$(command -v jq || true)"
[[ -n "$JQ_BIN" ]] || fail "jq is required for Headroom runtime tests"
JQ_BIN="$(readlink -f "$JQ_BIN")"
readonly JQ_BIN
TEMP_DIR="$(mktemp -d)"

test_version_is_exact
test_help_lists_the_three_commands
test_unknown_command_is_usage_error
test_relative_binary_override_is_rejected

printf 'PASS: Headroom runtime tests\n'
