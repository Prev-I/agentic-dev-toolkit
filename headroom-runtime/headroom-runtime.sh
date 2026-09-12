#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="0.1.2"
readonly HEADROOM_VERSION="0.37.0"
readonly HEADROOM_PYTHON="3.13"
readonly HEADROOM_PROFILE="default"
readonly HEADROOM_PORT="8787"
readonly HEADROOM_PACKAGE="headroom-ai[proxy]==${HEADROOM_VERSION}"
readonly RUNTIME_HOME="${HRT_HOME:-$HOME}"
readonly PROC_ROOT="${HRT_PROC_ROOT:-/proc}"
readonly OPENCODE_CONFIG_DIR="${HRT_OPENCODE_CONFIG_DIR:-$RUNTIME_HOME/.config/opencode}"
readonly SYSTEMD_USER_DIR="${HRT_SYSTEMD_USER_DIR:-$RUNTIME_HOME/.config/systemd/user}"
readonly HEADROOM_DEPLOY_ROOT="${HRT_HEADROOM_DEPLOY_ROOT:-$RUNTIME_HOME/.headroom/deploy}"
readonly MANIFEST_PATH="${HEADROOM_DEPLOY_ROOT}/${HEADROOM_PROFILE}/manifest.json"
readonly RUNNER_PID_PATH="${HRT_RUNNER_PID_PATH:-${HEADROOM_DEPLOY_ROOT}/${HEADROOM_PROFILE}/runner.pid}"

DRY_RUN=0
JSON_MODE=0
UNINSTALL_TOOL=0
COMMAND=""
UPTIME_FILE="${HRT_UPTIME_FILE:-/proc/uptime}"
readonly UPTIME_FILE

usage() {
  printf '%s\n' \
    'Usage: headroom-runtime.sh COMMAND [options]' \
    '' \
    "Headroom ${HEADROOM_VERSION}, Python ${HEADROOM_PYTHON}, profile ${HEADROOM_PROFILE}, port ${HEADROOM_PORT}" \
    "Package: ${HEADROOM_PACKAGE}" \
    '' \
    'Commands:' \
    '  install [--dry-run]' \
    '  audit [--json]' \
    '  remove [--dry-run] [--uninstall-tool]' \
    '' \
    'Options:' \
    '  --help                       Show this help text.' \
    '  --version                    Show the tool version.'
}

die_usage() {
  if [[ "$COMMAND" == audit && "$JSON_MODE" == 1 ]]; then
    if ! render_resolution_error_json "$1"; then
      printf 'ERROR: %s\n' "$1" >&2
      printf '{"schemaVersion":1,"toolVersion":"%s","action":"audit","status":"ERROR","findings":[],"error":"audit command resolution failed"}\n' \
        "$SCRIPT_VERSION"
    fi
  else
    printf 'ERROR: %s\n' "$1" >&2
  fi
  exit 2
}

quote_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  quote_command "$@"
  if (( DRY_RUN == 0 )); then
    "$@"
  fi
}

validate_uptime_file() {
  # Uptime is consumed by Task 3's bounded install readiness loop, not CLI metadata.
  [[ "$UPTIME_FILE" == /* && -r "$UPTIME_FILE" ]] ||
    die_usage "HRT_UPTIME_FILE must be an absolute readable path"
}

validate_uptime_content() {
  local uptime

  if ! IFS=' ' read -r uptime _ < "$UPTIME_FILE" ||
    [[ ! "$uptime" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die_usage "HRT_UPTIME_FILE must contain a monotonic uptime value"
  fi
}

resolve_executable() {
  # The first argument names the caller variable that receives the safe path.
  local output_name="$1"
  local env_name="$2"
  local default_name="$3"
  local candidate="${!env_name:-}"

  if [[ -n "$candidate" ]]; then
    [[ "$candidate" == /* ]] || die_usage "$env_name must be an absolute executable path"
    [[ -x "$candidate" ]] || die_usage "$env_name must name an executable path"
  else
    candidate="$(command -v "$default_name" || true)"
    [[ -n "$candidate" ]] || die_usage "$default_name is required but was not found"
    if ! candidate="$(readlink -f "$candidate")"; then
      die_usage "$default_name could not be resolved to an executable path"
    fi
    [[ -n "$candidate" && -x "$candidate" ]] ||
      die_usage "$default_name resolved to a non-executable path"
  fi

  printf -v "$output_name" '%s' "$candidate"
}

declare -a F_SEVERITY=()
declare -a F_CODE=()
declare -a F_SUBJECT=()
declare -a F_MESSAGE=()

add_finding() {
  F_SEVERITY+=("$1")
  F_CODE+=("$2")
  F_SUBJECT+=("$3")
  F_MESSAGE+=("$4")
}

deduplicate_findings() {
  local index key
  local -A seen=()
  local -a finding_severity=() finding_code=() finding_subject=() finding_message=()

  for index in "${!F_CODE[@]}"; do
    key="${F_SEVERITY[$index]}"$'\034'"${F_CODE[$index]}"$'\034'"${F_SUBJECT[$index]}"$'\034'"${F_MESSAGE[$index]}"
    [[ -z "${seen[$key]:-}" ]] || continue
    seen[$key]=1
    finding_severity+=("${F_SEVERITY[$index]}")
    finding_code+=("${F_CODE[$index]}")
    finding_subject+=("${F_SUBJECT[$index]}")
    finding_message+=("${F_MESSAGE[$index]}")
  done
  F_SEVERITY=("${finding_severity[@]}") F_CODE=("${finding_code[@]}")
  F_SUBJECT=("${finding_subject[@]}") F_MESSAGE=("${finding_message[@]}")
}

check_headroom_version() {
  local output

  if output="$("$HEADROOM_BIN" --version)"; then
    if [[ "$output" != "headroom, version ${HEADROOM_VERSION}" ]]; then
      add_finding FAIL HEADROOM_VERSION_MISMATCH headroom \
        "Headroom CLI is not version ${HEADROOM_VERSION}."
    fi
  else
    add_finding ERROR HEADROOM_VERSION_UNREADABLE headroom \
      "Headroom CLI version could not be inspected."
  fi
}

check_service_state() {
  local enabled active lifecycle_status

  if enabled="$("$SYSTEMCTL_BIN" --user is-enabled headroom-default.service 2>/dev/null)"; then
    [[ "$enabled" == enabled ]] ||
      add_finding FAIL HEADROOM_SERVICE_DISABLED headroom-default.service \
        "Headroom service is not enabled."
  else
    add_finding FAIL HEADROOM_SERVICE_DISABLED headroom-default.service \
      "Headroom service is not enabled."
  fi
  if active="$("$SYSTEMCTL_BIN" --user is-active headroom-default.service 2>/dev/null)"; then
    [[ "$active" == active ]] ||
      add_finding FAIL HEADROOM_SERVICE_INACTIVE headroom-default.service \
        "Headroom service is not active."
  else
    add_finding FAIL HEADROOM_SERVICE_INACTIVE headroom-default.service \
      "Headroom service is not active."
  fi
  if lifecycle_status="$("$SYSTEMCTL_BIN" --user show headroom-default.service --property=ExecMainStatus --value 2>/dev/null)" &&
    [[ "$lifecycle_status" == 241 ]]; then
    add_finding WARN HEADROOM_LIFECYCLE_EXIT_241 headroom-default.service \
      "Headroom recorded the known recoverable lifecycle exit 241."
  fi
}

READINESS_RESULT=""
READINESS_KOMPRESS_DEGRADED=0

probe_readiness() {
  local timeout="$1" body ready version
  local subject="http://127.0.0.1:${HEADROOM_PORT}/readyz"

  READINESS_RESULT=TRANSPORT READINESS_KOMPRESS_DEGRADED=0
  if ! body="$("$CURL_BIN" --silent --show-error --fail --connect-timeout "$timeout" --max-time "$timeout" "$subject")"; then
    return
  fi
  if ! "$JQ_BIN" -e . >/dev/null <<<"$body"; then
    READINESS_RESULT=INVALID_JSON
    return
  fi
  if ! ready="$("$JQ_BIN" -er '.ready' <<<"$body")" || [[ "$ready" != true ]]; then
    READINESS_RESULT=NOT_READY
    return
  fi
  if ! version="$("$JQ_BIN" -er '.version | strings | select(length > 0)' <<<"$body")"; then
    READINESS_RESULT=NO_VERSION
    return
  fi
  if [[ "$version" != "$HEADROOM_VERSION" ]]; then
    READINESS_RESULT=VERSION_MISMATCH
    return
  fi
  if "$JQ_BIN" -e '.checks.kompress.ready == false' >/dev/null <<<"$body"; then
    READINESS_KOMPRESS_DEGRADED=1
  fi
  READINESS_RESULT=READY
}

add_readiness_findings() {
  local subject="http://127.0.0.1:${HEADROOM_PORT}/readyz"

  case "$READINESS_RESULT" in
    TRANSPORT) add_finding FAIL HEADROOM_NOT_READY "$subject" "Headroom readiness endpoint did not succeed." ;;
    NOT_READY) add_finding FAIL HEADROOM_NOT_READY "$subject" "Headroom readiness endpoint did not report ready." ;;
    INVALID_JSON) add_finding ERROR HEADROOM_READINESS_INVALID "$subject" "Headroom readiness response was not valid JSON." ;;
    NO_VERSION) add_finding ERROR HEADROOM_READINESS_INVALID "$subject" "Headroom readiness response has no usable version." ;;
    VERSION_MISMATCH) add_finding FAIL HEADROOM_READINESS_VERSION_MISMATCH "$subject" "Headroom readiness version does not match the pinned runtime." ;;
    READY)
      (( READINESS_KOMPRESS_DEGRADED == 0 )) ||
        add_finding WARN HEADROOM_KOMPRESS_OPTIONAL_DEGRADED "$subject" \
          "Optional Kompress is degraded; the required runtime is ready."
      ;;
  esac
}

check_readiness() {
  probe_readiness 5
  add_readiness_findings
}

runner_cmdline_is_headroom_proxy() {
  local pid="$1" index
  local -a arguments=()

  [[ -r "$PROC_ROOT/$pid/cmdline" ]] || return 1
  if ! mapfile -d '' -t arguments < "$PROC_ROOT/$pid/cmdline"; then
    return 1
  fi
  for index in "${!arguments[@]}"; do
    [[ "${arguments[$index]}" == -m ]] || continue
    [[ "${arguments[$((index + 1))]:-}" == headroom.cli ]] || continue
    [[ "${arguments[$((index + 2))]:-}" == proxy ]] && return 0
  done
  return 1
}

parse_listener() {
  local output row owners owner_pid local_address runner_pid=""
  local listener_found=0 unsafe_bind=0 foreign_owner=0 ambiguous_owner=0 managed_deployment=0
  local managed_owner_seen=0 owner_seen=0
  local -a runner_pid_lines=()

  LISTENER_STATE=AMBIGUOUS
  if [[ -e "$MANIFEST_PATH" || -e "$SYSTEMD_USER_DIR/headroom-default.service" ]]; then
    managed_deployment=1
    if [[ ! -r "$RUNNER_PID_PATH" ]] || ! mapfile -t runner_pid_lines < "$RUNNER_PID_PATH" ||
      [[ ${#runner_pid_lines[@]} -ne 1 || ! "${runner_pid_lines[0]}" =~ ^[1-9][0-9]*$ ]]; then
      add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
        "Headroom listener ownership could not be determined."
      return
    fi
    runner_pid="${runner_pid_lines[0]}"
  fi
  if ! output="$("$SS_BIN" -ltnp "sport = :${HEADROOM_PORT}")"; then
    add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
      "Headroom listener ownership could not be determined."
    return
  fi
  while IFS= read -r row; do
    # ss -ltnp emits either the traditional or Netid-prefixed row shape.
    if [[ "$row" == tcp* || "$row" == udp* ]]; then
      IFS=' ' read -r _ _ _ _ local_address _ <<<"$row"
    else
      IFS=' ' read -r _ _ _ local_address _ <<<"$row"
    fi
    [[ "$local_address" == *":${HEADROOM_PORT}" ]] || continue
    listener_found=1
    [[ "$local_address" == "127.0.0.1:${HEADROOM_PORT}" ]] || unsafe_bind=1
    if [[ "$row" != *'users:(('* ]]; then
      ambiguous_owner=1
      continue
    fi
    owners="${row#*users:}"
    owner_seen=0
    while [[ "$owners" =~ pid=([0-9]+) ]]; do
      owner_pid="${BASH_REMATCH[1]}"
      owner_seen=1
      if (( managed_deployment )); then
        if [[ "$owner_pid" == "$runner_pid" ]]; then
          managed_owner_seen=1
        else
          foreign_owner=1
        fi
      else
        foreign_owner=1
      fi
      owners="${owners#*"${BASH_REMATCH[0]}"}"
    done
    (( owner_seen )) || ambiguous_owner=1
  done <<<"$output"
  if (( listener_found == 0 )); then
    LISTENER_STATE=ABSENT
    return
  fi
  if (( ambiguous_owner )); then
    add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
      "Headroom listener ownership could not be determined."
    LISTENER_STATE=AMBIGUOUS
    return
  fi
  if (( unsafe_bind )); then
    add_finding FAIL HEADROOM_UNSAFE_BIND "port ${HEADROOM_PORT}" \
      "Headroom is not bound only to 127.0.0.1."
  fi
  if (( managed_deployment && managed_owner_seen )) && ! runner_cmdline_is_headroom_proxy "$runner_pid"; then
    add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
      "Headroom listener ownership could not be determined."
    LISTENER_STATE=AMBIGUOUS
    return
  fi
  if (( managed_deployment && managed_owner_seen == 0 )); then
    foreign_owner=1
  fi
  if (( foreign_owner )); then
    add_finding FAIL HEADROOM_FOREIGN_LISTENER "port ${HEADROOM_PORT}" \
      "Headroom port is owned by another process."
  fi
  if (( foreign_owner )); then
    LISTENER_STATE=CONFLICT
  elif (( unsafe_bind )); then
    LISTENER_STATE=HEADROOM_UNSAFE
  else
    LISTENER_STATE=HEADROOM
  fi
}

check_listener() {
  parse_listener
  if [[ "$LISTENER_STATE" == ABSENT ]]; then
    add_finding FAIL HEADROOM_LISTENER_ABSENT "port ${HEADROOM_PORT}" \
      "Headroom has no listener on its configured port."
  fi
}

check_manifest() {
  local manifest profile targets mutations memory telemetry beacon update_check telemetry_env

  if [[ ! -r "$MANIFEST_PATH" ]]; then
    add_finding ERROR HEADROOM_MANIFEST_UNREADABLE "$MANIFEST_PATH" \
      "Headroom manifest is not readable."
    return
  fi
  if ! manifest="$("$JQ_BIN" -er '
    if type == "object" and
      (.profile | type == "string") and
      (.targets | type == "array") and
      (.mutations | type == "array") and
      (.memory_enabled | type == "boolean") and
      (.telemetry_enabled | type == "boolean") and
      (.base_env | type == "object") and
      (.base_env.HEADROOM_BEACON | type == "string") and
      (.base_env.HEADROOM_UPDATE_CHECK | type == "string") and
      (.base_env.HEADROOM_TELEMETRY | type == "string")
    then
      [.profile, (.targets | length), (.mutations | length), .memory_enabled,
       .telemetry_enabled, .base_env.HEADROOM_BEACON,
       .base_env.HEADROOM_UPDATE_CHECK, .base_env.HEADROOM_TELEMETRY] | @tsv
    else error("invalid manifest structure") end
  ' "$MANIFEST_PATH")"; then
    add_finding ERROR HEADROOM_MANIFEST_INVALID "$MANIFEST_PATH" \
      "Headroom manifest is not valid JSON with the required structure."
    return
  fi
  IFS=$'\t' read -r profile targets mutations memory telemetry beacon update_check telemetry_env <<<"$manifest"
  [[ "$profile" == "$HEADROOM_PROFILE" ]] ||
    add_finding FAIL HEADROOM_PROFILE_MISMATCH "$MANIFEST_PATH" "Headroom manifest profile is not default."
  [[ "$targets" == 0 ]] ||
    add_finding FAIL HEADROOM_TARGETS_CONFIGURED "$MANIFEST_PATH" "Headroom targets are configured."
  [[ "$mutations" == 0 ]] ||
    add_finding FAIL HEADROOM_MUTATIONS_PRESENT "$MANIFEST_PATH" "Headroom managed mutations are present."
  [[ "$memory" == false ]] ||
    add_finding FAIL HEADROOM_MEMORY_ENABLED "$MANIFEST_PATH" "Headroom memory is enabled."
  [[ "$telemetry" == false ]] ||
    add_finding FAIL HEADROOM_TELEMETRY_ENABLED "$MANIFEST_PATH" "Headroom telemetry is enabled."
  [[ "$telemetry_env" == off ]] ||
    add_finding FAIL HEADROOM_TELEMETRY_ENV_ENABLED "$MANIFEST_PATH" "Headroom telemetry environment is enabled."
  [[ "$beacon" == off ]] ||
    add_finding FAIL HEADROOM_BEACON_NOT_DISABLED "$MANIFEST_PATH" "Headroom beacon is not disabled."
  [[ "$update_check" == off ]] ||
    add_finding FAIL HEADROOM_UPDATE_CHECK_NOT_DISABLED "$MANIFEST_PATH" \
      "Headroom update checks are not disabled."
}

check_generated_permissions() {
  local mode

  if ! mode="$("$STAT_BIN" -c %a "$MANIFEST_PATH")"; then
    add_finding ERROR HEADROOM_PERMISSIONS_UNREADABLE "$MANIFEST_PATH" \
      "Generated Headroom permissions could not be inspected."
  elif [[ ! "$mode" =~ ^[0-7]{1,4}$ ]]; then
    add_finding ERROR HEADROOM_PERMISSIONS_UNREADABLE "$MANIFEST_PATH" \
      "Generated Headroom permissions are not a valid octal mode."
  # 07177 covers special bits, owner execute, and every group/other permission bit.
  elif (( 8#$mode & 8#7177 )); then
    add_finding WARN HEADROOM_PERMISSIONS_BROAD "$MANIFEST_PATH" \
      "Generated Headroom files have permissions outside owner read/write."
  fi
}

check_opencode_config() {
  local path content
  local -A seen=()
  local -a candidates=("$OPENCODE_CONFIG_DIR/opencode.json" "$OPENCODE_CONFIG_DIR/opencode.jsonc")

  [[ -n "${OPENCODE_CONFIG:-}" ]] && candidates+=("$OPENCODE_CONFIG")
  for path in "${candidates[@]}"; do
    [[ -e "$path" ]] || continue
    [[ -z "${seen[$path]:-}" ]] || continue
    seen[$path]=1
    if [[ ! -f "$path" || ! -r "$path" ]]; then
      add_finding ERROR HEADROOM_OPENCODE_CONFIG_UNREADABLE "$path" \
        "OpenCode global configuration could not be inspected."
    elif ! content="$(<"$path")"; then
      add_finding ERROR HEADROOM_OPENCODE_CONFIG_UNREADABLE "$path" \
        "OpenCode global configuration could not be inspected."
    elif [[ "${content,,}" == *headroom-opencode* ]] || [[ "${content,,}" == *headroom_proxy_url* ]]; then
      add_finding FAIL HEADROOM_OPENCODE_CONFIG_PRESENT "$path" \
        "OpenCode global configuration references Headroom."
    fi
  done
}

check_opencode_package() {
  local package_dir="$OPENCODE_CONFIG_DIR/node_modules/headroom-opencode"
  local manifest="$OPENCODE_CONFIG_DIR/package.json"

  if [[ -e "$package_dir" ]]; then
    add_finding FAIL HEADROOM_OPENCODE_PACKAGE_PRESENT "$package_dir" \
      "The Headroom OpenCode integration package is present."
  fi
  [[ -e "$manifest" ]] || return 0
  if [[ ! -f "$manifest" || ! -r "$manifest" ]] ||
    ! "$JQ_BIN" -e '
      type == "object" and
      ((.dependencies? // {}) | type == "object") and
      ((.devDependencies? // {}) | type == "object") and
      ((.optionalDependencies? // {}) | type == "object") and
      ((.peerDependencies? // {}) | type == "object")
    ' "$manifest" >/dev/null; then
    add_finding ERROR HEADROOM_OPENCODE_PACKAGE_UNREADABLE "$manifest" \
      "OpenCode package manifest could not be inspected."
  elif "$JQ_BIN" -e '
    (.dependencies? // {})["headroom-opencode"] != null or
    (.devDependencies? // {})["headroom-opencode"] != null or
    (.optionalDependencies? // {})["headroom-opencode"] != null or
    (.peerDependencies? // {})["headroom-opencode"] != null
  ' "$manifest" >/dev/null; then
    add_finding FAIL HEADROOM_OPENCODE_PACKAGE_PRESENT "$manifest" \
      "The Headroom OpenCode integration package is present."
  fi
}

check_opencode_environment() {
  local active pid entry name

  if ! active="$("$SYSTEMCTL_BIN" --user is-active opencode.service 2>/dev/null)" || [[ "$active" != active ]]; then
    return
  fi
  if ! pid="$("$SYSTEMCTL_BIN" --user show opencode.service --property=MainPID --value 2>/dev/null)" ||
    [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || [[ ! -r "$PROC_ROOT/$pid/environ" ]]; then
    add_finding ERROR HEADROOM_OPENCODE_ENV_UNREADABLE opencode.service \
      "OpenCode environment could not be inspected."
    return
  fi
  while IFS= read -r -d '' entry; do
    name="${entry%%=*}"
    # Do not retain process-environment values after extracting the variable name.
    entry=""
    if [[ "$name" == HEADROOM_* ]]; then
      add_finding FAIL HEADROOM_OPENCODE_ENV_PRESENT opencode.service \
        "OpenCode environment contains a Headroom integration variable."
      return
    fi
  done < "$PROC_ROOT/$pid/environ"
}

check_unit_independence() {
  local path content dependency unit_name parent

  for path in "$SYSTEMD_USER_DIR/headroom-default.service" "$SYSTEMD_USER_DIR/headroom-default.service.d"/*.conf \
    "$SYSTEMD_USER_DIR/opencode.service" "$SYSTEMD_USER_DIR/opencode.service.d"/*.conf; do
    [[ -f "$path" ]] || continue
    unit_name="${path##*/}"
    parent="${path%/*}"
    parent="${parent##*/}"
    [[ "$unit_name" == *.conf ]] && unit_name="${parent%.d}"
    case "$unit_name" in
      headroom-default.service) dependency=opencode.service ;;
      opencode.service) dependency=headroom-default.service ;;
      *) continue ;;
    esac
    if content="$(<"$path")" && [[ "$content" == *"$dependency"* ]]; then
      add_finding FAIL HEADROOM_OPENCODE_UNIT_COUPLED "$path" \
        "Headroom and OpenCode user units are coupled."
      return
    fi
  done
}

audit_runtime_without_readiness() {
  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  if [[ -n "${HEADROOM_BIN:-}" ]]; then
    check_headroom_version
  fi
  check_service_state
  check_listener
  check_manifest
  check_generated_permissions
  check_opencode_config
  check_opencode_package
  check_opencode_environment
  check_unit_independence
}

audit_runtime() {
  audit_runtime_without_readiness
  check_readiness
  deduplicate_findings
}

status_for_findings() {
  local severity

  for severity in "${F_SEVERITY[@]}"; do if [[ "$severity" == ERROR ]]; then printf '%s\n' ERROR; return; fi; done
  for severity in "${F_SEVERITY[@]}"; do if [[ "$severity" == FAIL ]]; then printf '%s\n' FAIL; return; fi; done
  for severity in "${F_SEVERITY[@]}"; do if [[ "$severity" == WARN ]]; then printf '%s\n' WARN; return; fi; done
  printf '%s\n' PASS
}

render_human() {
  local status="$1" index

  for index in "${!F_CODE[@]}"; do
    printf '%s: %s (%s): %s\n' "${F_SEVERITY[$index]}" "${F_CODE[$index]}" \
      "${F_SUBJECT[$index]}" "${F_MESSAGE[$index]}"
  done
  printf 'Status: %s\n' "$status"
}

render_json() {
  local status="$1" findings='[]' index rendered
  # shellcheck disable=SC2016 # jq variables must remain literal for jq, not Bash.
  local append_finding='$findings + [{severity: $severity, code: $code, subject: $subject, message: $message}]'
  # shellcheck disable=SC2016 # jq variables must remain literal for jq, not Bash.
  local audit_envelope='{schemaVersion: 1, toolVersion: $version, action: "audit", status: $status, findings: $findings}'

  for index in "${!F_CODE[@]}"; do
    if ! findings="$("$JQ_BIN" -cn --argjson findings "$findings" \
      --arg severity "${F_SEVERITY[$index]}" --arg code "${F_CODE[$index]}" \
      --arg subject "${F_SUBJECT[$index]}" --arg message "${F_MESSAGE[$index]}" \
      "$append_finding")"; then
      return 1
    fi
  done
  if rendered="$("$JQ_BIN" -n --arg version "$SCRIPT_VERSION" --arg status "$status" --argjson findings "$findings" \
    "$audit_envelope")" && [[ -n "$rendered" ]]; then
    printf '%s\n' "$rendered"
    return 0
  fi
  return 1
}

render_fixed_error_json() {
  printf '{"schemaVersion":1,"toolVersion":"%s","action":"audit","status":"ERROR","findings":[],"error":"audit command resolution failed"}\n' \
    "$SCRIPT_VERSION"
}

render_resolution_error_json() {
  local message="$1" jq_candidate="${JQ_BIN:-${HRT_JQ_BIN:-}}" rendered
  # shellcheck disable=SC2016 # jq variables must remain literal for jq, not Bash.
  local resolution_envelope='{schemaVersion: 1, toolVersion: $version, action: "audit", status: "ERROR", findings: [], error: $error}'

  if [[ -z "$jq_candidate" ]]; then
    # This PATH jq only serializes a usage error, so it is a best-effort safe serializer, not normal audit resolution.
    jq_candidate="$(command -v jq || true)"
  fi
  if [[ "$jq_candidate" == /* && -x "$jq_candidate" ]]; then
    if rendered="$("$jq_candidate" -n --arg version "$SCRIPT_VERSION" --arg error "$message" \
      "$resolution_envelope")" && [[ -n "$rendered" ]]; then
      printf '%s\n' "$rendered"
      return 0
    fi
  fi
  return 1
}

run_audit() {
  local status

  resolve_executable JQ_BIN HRT_JQ_BIN jq
  if [[ -n "${HRT_HEADROOM_BIN:-}" ]]; then
    resolve_executable HEADROOM_BIN HRT_HEADROOM_BIN headroom
  else
    resolve_headroom_tool_bin_dir
    if ! HEADROOM_BIN="$(headroom_tool_path)"; then
      resolve_executable HEADROOM_BIN HRT_HEADROOM_BIN headroom
    fi
  fi
  resolve_executable SYSTEMCTL_BIN HRT_SYSTEMCTL_BIN systemctl
  resolve_executable CURL_BIN HRT_CURL_BIN curl
  resolve_executable SS_BIN HRT_SS_BIN ss
  resolve_executable STAT_BIN HRT_STAT_BIN stat
  audit_runtime
  status="$(status_for_findings)"
  if (( JSON_MODE )); then
    if ! render_json "$status"; then
      printf 'ERROR: audit JSON rendering failed\n' >&2
      render_fixed_error_json
      return 2
    fi
  else
    render_human "$status"
  fi
  case "$status" in PASS|WARN) return 0 ;; FAIL) return 1 ;; ERROR) return 2 ;; esac
}

PACKAGE_STATE=""
DEPLOYMENT_STATE=""
INSTALL_STATE=""
LISTENER_STATE=""
HEADROOM_TOOL_BIN_DIR=""

resolve_headroom_tool_bin_dir() {
  local bin_dir data_parent

  if [[ -n "${UV_TOOL_BIN_DIR:-}" ]]; then
    bin_dir="$UV_TOOL_BIN_DIR"
  elif [[ -n "${XDG_BIN_HOME:-}" ]]; then
    bin_dir="$XDG_BIN_HOME"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    data_parent="${XDG_DATA_HOME%/*}"
    bin_dir="$data_parent/bin"
  else
    bin_dir="$RUNTIME_HOME/.local/bin"
  fi
  [[ "$bin_dir" == /* ]] || die_usage "Headroom tool bin directory must be absolute"
  if ! bin_dir="$(readlink -m "$bin_dir")" || [[ "$bin_dir" != /* ]]; then
    die_usage "Headroom tool bin directory could not be canonicalized"
  fi
  HEADROOM_TOOL_BIN_DIR="$bin_dir"
}

headroom_tool_path() {
  local candidate

  # Task 4 must call resolve_headroom_tool_bin_dir before this lazy lookup.
  [[ -n "$HEADROOM_TOOL_BIN_DIR" ]] || return 1
  candidate="$HEADROOM_TOOL_BIN_DIR/headroom"
  if [[ -x "$candidate" ]]; then
    candidate="$(readlink -f "$candidate")" || return 1
    [[ "$candidate" == /* && -x "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

headroom_package_state() {
  local candidate output

  candidate="${HRT_HEADROOM_BIN:-}"
  if [[ -n "$candidate" ]]; then
    resolve_executable HEADROOM_BIN HRT_HEADROOM_BIN headroom
    if ! HEADROOM_BIN="$(readlink -f "$HEADROOM_BIN")" || [[ "$HEADROOM_BIN" != /* || ! -x "$HEADROOM_BIN" ]]; then
      PACKAGE_STATE=UNINSPECTABLE
      add_finding ERROR HEADROOM_VERSION_UNREADABLE headroom \
        "Headroom CLI version could not be inspected."
      return
    fi
  else
    candidate="$(headroom_tool_path || true)"
    if [[ -z "$candidate" ]]; then
      candidate="$(command -v headroom || true)"
    fi
    if [[ -z "$candidate" ]]; then
      PACKAGE_STATE=ABSENT
      return
    fi
    if ! HEADROOM_BIN="$(readlink -f "$candidate")" || [[ ! -x "$HEADROOM_BIN" ]]; then
      PACKAGE_STATE=UNINSPECTABLE
      add_finding ERROR HEADROOM_VERSION_UNREADABLE headroom \
        "Headroom CLI version could not be inspected."
      return
    fi
  fi
  if ! output="$("$HEADROOM_BIN" --version)"; then
    PACKAGE_STATE=UNINSPECTABLE
    add_finding ERROR HEADROOM_VERSION_UNREADABLE headroom \
      "Headroom CLI version could not be inspected."
  elif [[ "$output" == "headroom, version ${HEADROOM_VERSION}" ]]; then
    PACKAGE_STATE=EXACT
  else
    PACKAGE_STATE=WRONG_VERSION
  fi
}

deployment_state() {
  local code

  if [[ -e "$MANIFEST_PATH" || -e "$SYSTEMD_USER_DIR/headroom-default.service" ]]; then
    F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
    check_manifest
    case "$(status_for_findings)" in
      ERROR)
        DEPLOYMENT_STATE=AMBIGUOUS
        return
        ;;
      FAIL)
        for code in "${F_CODE[@]}"; do
          if [[ "$code" == HEADROOM_PROFILE_MISMATCH ]]; then
            DEPLOYMENT_STATE=CONFLICT
            return
          fi
        done
        DEPLOYMENT_STATE=NONCONFORMING
        return
        ;;
      PASS|WARN)
        check_service_state
        if [[ "$(status_for_findings)" == FAIL ]]; then
          DEPLOYMENT_STATE=STOPPED
        else
          check_listener
          check_generated_permissions
          check_opencode_config
          check_opencode_package
          check_opencode_environment
          check_unit_independence
          case "$(status_for_findings)" in
            ERROR) DEPLOYMENT_STATE=AMBIGUOUS ;;
            FAIL) DEPLOYMENT_STATE=NONCONFORMING ;;
            PASS|WARN) DEPLOYMENT_STATE=CONFORMING ;;
            *)
              add_finding ERROR HEADROOM_STATE_INDETERMINATE headroom-default.service \
                "Headroom deployment state could not be determined."
              DEPLOYMENT_STATE=AMBIGUOUS
              ;;
          esac
        fi
        ;;
    esac
    return
  fi
  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  parse_listener
  case "$LISTENER_STATE" in
    ABSENT) DEPLOYMENT_STATE=ABSENT ;;
    CONFLICT) DEPLOYMENT_STATE=CONFLICT ;;
    AMBIGUOUS) DEPLOYMENT_STATE=AMBIGUOUS ;;
    HEADROOM|HEADROOM_UNSAFE)
      add_finding ERROR HEADROOM_UNMANAGED_LISTENER "port ${HEADROOM_PORT}" \
        "A Headroom-owned listener exists without a managed deployment."
      DEPLOYMENT_STATE=AMBIGUOUS
      ;;
    *)
      add_finding ERROR HEADROOM_STATE_INDETERMINATE headroom \
        "Headroom deployment state could not be determined."
      DEPLOYMENT_STATE=AMBIGUOUS
      ;;
  esac
}

classify_install_state() {
  local -a package_severity=() package_code=() package_subject=() package_message=()
  local -a deployment_severity=() deployment_code=() deployment_subject=() deployment_message=()

  headroom_package_state
  package_severity=("${F_SEVERITY[@]}")
  package_code=("${F_CODE[@]}")
  package_subject=("${F_SUBJECT[@]}")
  package_message=("${F_MESSAGE[@]}")
  deployment_state
  deployment_severity=("${F_SEVERITY[@]}")
  deployment_code=("${F_CODE[@]}")
  deployment_subject=("${F_SUBJECT[@]}")
  deployment_message=("${F_MESSAGE[@]}")
  F_SEVERITY=("${package_severity[@]}" "${deployment_severity[@]}")
  F_CODE=("${package_code[@]}" "${deployment_code[@]}")
  F_SUBJECT=("${package_subject[@]}" "${deployment_subject[@]}")
  F_MESSAGE=("${package_message[@]}" "${deployment_message[@]}")
  if [[ "$(status_for_findings)" == ERROR ]]; then
    INSTALL_STATE=AMBIGUOUS
  elif [[ "$DEPLOYMENT_STATE" == AMBIGUOUS ]]; then
    INSTALL_STATE=AMBIGUOUS
  elif [[ "$DEPLOYMENT_STATE" == CONFLICT ]]; then
    INSTALL_STATE=CONFLICT
  elif [[ "$PACKAGE_STATE" == UNINSPECTABLE ]]; then
    INSTALL_STATE=AMBIGUOUS
  elif [[ "$PACKAGE_STATE" == ABSENT && "$DEPLOYMENT_STATE" != ABSENT ]]; then
    INSTALL_STATE=ORPHANED_DEPLOYMENT
  elif [[ "$PACKAGE_STATE" == WRONG_VERSION ]]; then
    INSTALL_STATE=WRONG_VERSION
  elif [[ "$DEPLOYMENT_STATE" == NONCONFORMING ]]; then
    INSTALL_STATE=NONCONFORMING
  elif [[ "$PACKAGE_STATE" == EXACT && "$DEPLOYMENT_STATE" == STOPPED ]]; then
    INSTALL_STATE=STOPPED
  elif [[ "$PACKAGE_STATE" == EXACT && "$DEPLOYMENT_STATE" == CONFORMING ]]; then
    INSTALL_STATE=CONFORMING
  elif [[ "$PACKAGE_STATE" == EXACT ]]; then
    INSTALL_STATE=PACKAGE_ONLY
  else
    INSTALL_STATE=ABSENT
  fi
}

classify_removal_deployment() {
  local code

  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  if [[ -e "$HEADROOM_DEPLOY_ROOT/$HEADROOM_PROFILE" || -e "$SYSTEMD_USER_DIR/headroom-default.service" ]]; then
    check_manifest
    case "$(status_for_findings)" in
      ERROR) DEPLOYMENT_STATE=AMBIGUOUS ;;
      FAIL)
        for code in "${F_CODE[@]}"; do
          if [[ "$code" == HEADROOM_PROFILE_MISMATCH ]]; then
            DEPLOYMENT_STATE=CONFLICT
            return
          fi
        done
        DEPLOYMENT_STATE=RECOGNIZED
        ;;
      PASS|WARN) DEPLOYMENT_STATE=RECOGNIZED ;;
    esac
    return
  fi
  parse_listener
  case "$LISTENER_STATE" in
    ABSENT) DEPLOYMENT_STATE=ABSENT ;;
    CONFLICT) DEPLOYMENT_STATE=CONFLICT ;;
    AMBIGUOUS) DEPLOYMENT_STATE=AMBIGUOUS ;;
    HEADROOM|HEADROOM_UNSAFE)
      add_finding ERROR HEADROOM_UNMANAGED_LISTENER "port ${HEADROOM_PORT}" \
        "A Headroom-owned listener exists without a managed deployment."
      DEPLOYMENT_STATE=AMBIGUOUS
      ;;
    *)
      add_finding ERROR HEADROOM_STATE_INDETERMINATE headroom \
        "Headroom deployment state could not be determined."
      DEPLOYMENT_STATE=AMBIGUOUS
      ;;
  esac
}

demote_opencode_findings() {
  local index

  for index in "${!F_CODE[@]}"; do
    [[ "${F_SEVERITY[$index]}" == FAIL ]] || continue
    case "${F_CODE[$index]}" in
      HEADROOM_OPENCODE_CONFIG_PRESENT|HEADROOM_OPENCODE_PACKAGE_PRESENT|HEADROOM_OPENCODE_ENV_PRESENT|HEADROOM_OPENCODE_UNIT_COUPLED)
        F_SEVERITY[index]=WARN
        ;;
    esac
  done
}

report_removal_warnings() {
  local code index mutation_risk=0 status

  for code in "${F_CODE[@]}"; do
    case "$code" in
      HEADROOM_TARGETS_CONFIGURED|HEADROOM_MUTATIONS_PRESENT) mutation_risk=1 ;;
    esac
  done
  demote_opencode_findings
  for index in "${!F_SEVERITY[@]}"; do
    [[ "${F_SEVERITY[$index]}" == FAIL ]] && F_SEVERITY[index]=WARN
  done
  if (( mutation_risk )); then
    add_finding WARN HEADROOM_REMOVAL_MAY_REVERT_MUTATIONS "$MANIFEST_PATH" \
      "Upstream removal may revert recorded Headroom mutations."
  fi
  check_opencode_config
  check_opencode_environment
  check_unit_independence
  check_opencode_package
  demote_opencode_findings
  deduplicate_findings
  status="$(status_for_findings)"
  [[ ${#F_CODE[@]} -eq 0 ]] || render_human "$status"
  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  case "$status" in PASS|WARN) return 0 ;; FAIL) return 1 ;; ERROR) return 2 ;; esac
}

verify_removed() {
  local status

  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  [[ ! -e "$SYSTEMD_USER_DIR/headroom-default.service" ]] ||
    add_finding FAIL HEADROOM_SERVICE_REMAINS headroom-default.service \
      "Headroom service remains after removal."
  [[ ! -e "$HEADROOM_DEPLOY_ROOT/$HEADROOM_PROFILE" ]] ||
    add_finding FAIL HEADROOM_PROFILE_REMAINS "$HEADROOM_DEPLOY_ROOT/$HEADROOM_PROFILE" \
      "Headroom profile remains after removal."
  parse_listener
  case "$LISTENER_STATE" in
    HEADROOM|HEADROOM_UNSAFE)
      add_finding FAIL HEADROOM_LISTENER_REMAINS "port ${HEADROOM_PORT}" \
        "Headroom port remains occupied after removal."
      ;;
  esac
  status="$(status_for_findings)"
  [[ "$status" == PASS ]] || render_human "$status"
  case "$status" in PASS|WARN) return 0 ;; FAIL) return 1 ;; ERROR) return 2 ;; esac
}

run_remove() {
  local status warning_status

  resolve_executable JQ_BIN HRT_JQ_BIN jq
  resolve_executable SYSTEMCTL_BIN HRT_SYSTEMCTL_BIN systemctl
  resolve_executable SS_BIN HRT_SS_BIN ss
  # Resolve the uv destination before headroom_tool_path can classify its ownership.
  resolve_headroom_tool_bin_dir
  (( UNINSTALL_TOOL == 0 )) || resolve_executable UV_BIN HRT_UV_BIN uv
  classify_removal_deployment
  status="$(status_for_findings)"
  case "$DEPLOYMENT_STATE" in
    AMBIGUOUS)
      render_human "$status"
      printf '%s\n' 'ERROR: automated removal is unsafe; see docs/headroom-runtime.md#rollback for the manual fallback.' >&2
      return 2
      ;;
    CONFLICT)
      render_human "$status"
      return 1
      ;;
    ABSENT)
      if (( UNINSTALL_TOOL == 0 )); then
        return 0
      fi
      headroom_package_state
      case "$PACKAGE_STATE" in
        ABSENT) return 0 ;;
        EXACT)
          run "$UV_BIN" tool uninstall headroom-ai
          return 0
          ;;
        UNINSPECTABLE)
          render_human "$(status_for_findings)"
          return 2
          ;;
        WRONG_VERSION)
          printf '%s\n' 'ERROR: Headroom tool is not the pinned version; automatic uninstall is refused.' >&2
          return 1
          ;;
      esac
      ;;
  esac

  headroom_package_state
  case "$PACKAGE_STATE" in
    EXACT) ;;
    UNINSPECTABLE)
      render_human "$(status_for_findings)"
      return 2
      ;;
    ABSENT)
      printf '%s\n' 'ERROR: Headroom deployment exists without the pinned runtime.' >&2
      return 1
      ;;
    WRONG_VERSION)
      printf '%s\n' 'ERROR: Headroom tool is not the pinned version; automatic removal is refused.' >&2
      return 1
      ;;
  esac
  if report_removal_warnings; then
    :
  else
    warning_status=$?
    return "$warning_status"
  fi
  run "$HEADROOM_BIN" install remove --profile "$HEADROOM_PROFILE"
  if (( UNINSTALL_TOOL )); then
    run "$UV_BIN" tool uninstall headroom-ai
  fi
  (( DRY_RUN )) && return 0
  verify_removed
}

install_package() {
  run "$UV_BIN" tool install --python "$HEADROOM_PYTHON" "$HEADROOM_PACKAGE"
}

apply_deployment() {
  local apply_bin="$1"

  run "$apply_bin" install apply --preset persistent-service --runtime python \
    --scope provider --providers manual --profile "$HEADROOM_PROFILE" --port "$HEADROOM_PORT" \
    --mode cache --no-telemetry --env HEADROOM_BEACON=off --env HEADROOM_UPDATE_CHECK=off
}

uptime_centiseconds() {
  local uptime fraction

  if ! IFS=' ' read -r uptime _ < "$UPTIME_FILE" || [[ ! "$uptime" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die_usage "HRT_UPTIME_FILE must contain a monotonic uptime value"
  fi
  fraction="${uptime#*.}"
  [[ "$uptime" == *.* ]] || fraction=""
  fraction="${fraction}00"
  printf '%d\n' "$((10#${uptime%%.*} * 100 + 10#${fraction:0:2}))"
}

wait_for_readiness() {
  local started now elapsed remaining timeout_seconds timeout_fraction

  started="$(uptime_centiseconds)"
  while :; do
    now="$(uptime_centiseconds)"
    elapsed=$((now - started))
    (( elapsed < 3000 )) || return 1
    remaining=$((3000 - elapsed))
    if (( remaining > 500 )); then
      timeout_seconds=5
      timeout_fraction=00
    else
      timeout_seconds=$((remaining / 100))
      timeout_fraction=$(printf '%02d' "$((remaining % 100))")
    fi
    probe_readiness "${timeout_seconds}.${timeout_fraction}"
    if [[ "$READINESS_RESULT" == READY ]]; then
      return 0
    fi
    case "$READINESS_RESULT" in
      TRANSPORT|NOT_READY) ;;
      *) return 1 ;;
    esac
    now="$(uptime_centiseconds)"
    (( now - started < 3000 )) || return 1
    "$SLEEP_BIN" 1
  done
}

run_install() {
  local package_state final_status future_headroom readiness_indeterminate=0 state_findings_status
  local -a state_findings_severity=() state_findings_code=() state_findings_subject=() state_findings_message=()

  resolve_executable UNAME_BIN HRT_UNAME_BIN uname
  [[ "$("$UNAME_BIN" -s)" == Linux ]] || die_usage "Headroom runtime installation requires Linux"
  validate_uptime_file
  validate_uptime_content
  resolve_executable UV_BIN HRT_UV_BIN uv
  resolve_executable SLEEP_BIN HRT_SLEEP_BIN sleep
  resolve_executable SYSTEMCTL_BIN HRT_SYSTEMCTL_BIN systemctl
  if ! "$SYSTEMCTL_BIN" --user show-environment >/dev/null 2>&1; then
    die_usage "usable user systemd is required"
  fi
  resolve_executable JQ_BIN HRT_JQ_BIN jq
  resolve_executable SS_BIN HRT_SS_BIN ss
  resolve_executable CURL_BIN HRT_CURL_BIN curl
  resolve_executable STAT_BIN HRT_STAT_BIN stat
  resolve_headroom_tool_bin_dir
  classify_install_state
  state_findings_status="$(status_for_findings)"
  state_findings_severity=("${F_SEVERITY[@]}")
  state_findings_code=("${F_CODE[@]}")
  state_findings_subject=("${F_SUBJECT[@]}")
  state_findings_message=("${F_MESSAGE[@]}")
  F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
  check_opencode_config
  check_opencode_environment
  check_unit_independence
  check_opencode_package
  F_SEVERITY=("${state_findings_severity[@]}" "${F_SEVERITY[@]}")
  F_CODE=("${state_findings_code[@]}" "${F_CODE[@]}")
  F_SUBJECT=("${state_findings_subject[@]}" "${F_SUBJECT[@]}")
  F_MESSAGE=("${state_findings_message[@]}" "${F_MESSAGE[@]}")
  deduplicate_findings
  final_status="$(status_for_findings)"
  if [[ "$final_status" == ERROR ]]; then
    render_human "$final_status"
    return 2
  fi
  case "$INSTALL_STATE" in
    CONFORMING)
      case "$final_status" in
        FAIL) render_human "$final_status"; return 1 ;;
        ERROR) render_human "$final_status"; return 2 ;;
      esac
      if [[ "$state_findings_status" == WARN ]]; then
        F_SEVERITY=("${state_findings_severity[@]}") F_CODE=("${state_findings_code[@]}")
        F_SUBJECT=("${state_findings_subject[@]}") F_MESSAGE=("${state_findings_message[@]}")
        render_human "$state_findings_status"
      fi
      printf '%s\n' 'Headroom runtime is already installed and conforming.'
      return 0
      ;;
    STOPPED)
      render_human "$final_status"
      printf '%s\n' 'ERROR: Headroom deployment is stopped or disabled; use systemctl --user start and enable headroom-default.service.' >&2
      return 1
      ;;
    ORPHANED_DEPLOYMENT)
      render_human "$final_status"
      printf '%s\n' 'ERROR: Headroom deployment exists without the pinned runtime.' >&2
      return 1
      ;;
    WRONG_VERSION)
      render_human "$final_status"
      printf '%s\n' 'ERROR: Headroom is not the pinned version; implicit upgrades are refused.' >&2
      return 1
      ;;
    NONCONFORMING|CONFLICT)
      render_human "$final_status"
      printf '%s\n' "ERROR: Headroom installation is ${INSTALL_STATE,,}; implicit repair is refused." >&2
      return 1
      ;;
    AMBIGUOUS)
      render_human "$final_status"
      printf '%s\n' 'ERROR: Headroom installation ownership could not be established.' >&2
      return 2
      ;;
  esac
  case "$final_status" in
    PASS|WARN) ;;
    FAIL)
      render_human "$final_status"
      return 1
      ;;
    ERROR)
      render_human "$final_status"
      return 2
      ;;
  esac
  if ! future_headroom="$(headroom_tool_path)"; then
    future_headroom="$HEADROOM_TOOL_BIN_DIR/headroom"
  fi
  if [[ "$INSTALL_STATE" == ABSENT ]]; then
    install_package
    if [[ "$DRY_RUN" -eq 1 ]]; then
      apply_deployment "$future_headroom"
      return 0
    fi
    if HEADROOM_BIN="$(headroom_tool_path)"; then
      if package_state="$("$HEADROOM_BIN" --version)" && [[ "$package_state" == "headroom, version ${HEADROOM_VERSION}" ]]; then
        PACKAGE_STATE=EXACT
      else
        PACKAGE_STATE=UNINSPECTABLE
      fi
    else
      headroom_package_state
    fi
    [[ "$PACKAGE_STATE" == EXACT ]] || {
      printf '%s\n' 'ERROR: uv did not install the expected pinned Headroom CLI.' >&2
      return 1
    }
  fi
  [[ -n "${HEADROOM_BIN:-}" ]] || die_usage "Headroom executable was not available after installation"
  apply_deployment "$HEADROOM_BIN"
  if [[ "$DRY_RUN" -eq 1 ]]; then return 0; fi
  if ! wait_for_readiness; then
    case "$READINESS_RESULT" in
      TRANSPORT|NOT_READY|INVALID_JSON|NO_VERSION|VERSION_MISMATCH) ;;
      *)
        readiness_indeterminate=1
        ;;
    esac
  fi
  audit_runtime_without_readiness
  if (( readiness_indeterminate )); then
    add_finding ERROR HEADROOM_STATE_INDETERMINATE headroom-default.service \
      "Headroom readiness result could not be determined."
  fi
  add_readiness_findings
  deduplicate_findings
  final_status="$(status_for_findings)"
  render_human "$final_status"
  case "$final_status" in
    PASS|WARN) return 0 ;;
    FAIL) return 1 ;;
    ERROR) return 2 ;;
  esac
  return 0
}

parse_args() {
  local command="${1:-}"
  [[ $# -gt 0 ]] || die_usage "a command is required"
  shift

  case "$command" in
    --help)
      [[ $# -eq 0 ]] || die_usage "--help does not accept arguments"
      COMMAND="help"
      ;;
    --version)
      [[ $# -eq 0 ]] || die_usage "--version does not accept arguments"
      COMMAND="version"
      ;;
    install)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dry-run) DRY_RUN=1 ;;
          *) die_usage "unknown install option: $1" ;;
        esac
        shift
      done
      COMMAND="install"
      ;;
    audit)
      COMMAND="audit"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json) JSON_MODE=1 ;;
          *) die_usage "unknown audit option: $1" ;;
        esac
        shift
      done
      ;;
    remove)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dry-run) DRY_RUN=1 ;;
          --uninstall-tool) UNINSTALL_TOOL=1 ;;
          *) die_usage "unknown remove option: $1" ;;
        esac
        shift
      done
      COMMAND="remove"
      ;;
    *) die_usage "unknown command: $command" ;;
  esac
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    help) usage ;;
    version) printf '%s\n' "$SCRIPT_VERSION" ;;
    install)
      run_install
      ;;
    audit) run_audit ;;
    remove) run_remove ;;
    *) die_usage "unsupported command: $COMMAND" ;;
  esac
}

main "$@"
