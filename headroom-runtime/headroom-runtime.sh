#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="0.1.0"
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

check_headroom_version() {
  local output

  if output="$("$HEADROOM_BIN" --version)"; then
    if [[ "$output" != "headroom ${HEADROOM_VERSION}" ]]; then
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

check_readiness() {
  local body ready version kompress
  local subject="http://127.0.0.1:${HEADROOM_PORT}/readyz"

  if ! body="$("$CURL_BIN" --silent --show-error --fail --connect-timeout 5 --max-time 5 "$subject")"; then
    add_finding FAIL HEADROOM_NOT_READY "$subject" "Headroom readiness endpoint did not succeed."
    return
  fi
  if ! "$JQ_BIN" -e . >/dev/null <<<"$body"; then
    add_finding ERROR HEADROOM_READINESS_INVALID "$subject" \
      "Headroom readiness response was not valid JSON."
    return
  fi
  if ready="$("$JQ_BIN" -er '.ready' <<<"$body")" && [[ "$ready" == true ]]; then
    if ! version="$("$JQ_BIN" -er '.version | strings | select(length > 0)' <<<"$body")"; then
      add_finding ERROR HEADROOM_READINESS_INVALID "$subject" \
        "Headroom readiness response has no usable version."
    elif [[ "$version" != "$HEADROOM_VERSION" ]]; then
      add_finding FAIL HEADROOM_READINESS_VERSION_MISMATCH "$subject" \
        "Headroom readiness version does not match the pinned runtime."
    fi
    if kompress="$("$JQ_BIN" -er '.kompress.ready == false' <<<"$body")" && [[ "$kompress" == true ]]; then
      add_finding WARN HEADROOM_KOMPRESS_OPTIONAL_DEGRADED "$subject" \
        "Optional Kompress is degraded; the required runtime is ready."
    fi
  else
    add_finding FAIL HEADROOM_NOT_READY "$subject" "Headroom readiness endpoint did not report ready."
  fi
}

check_listener() {
  local output row owners owner owner_seen local_address
  local listener_found=0 unsafe_bind=0 foreign_owner=0 ambiguous_owner=0

  if ! output="$("$SS_BIN" -ltnp "sport = :${HEADROOM_PORT}")"; then
    add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
      "Headroom listener ownership could not be determined."
    return
  fi
  while IFS= read -r row; do
    # ss prints state, queues, local address, peer address, then process details.
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
    while [[ "$owners" =~ \"([^\"]+)\" ]]; do
      owner="${BASH_REMATCH[1]}"
      owner_seen=1
      [[ "$owner" == headroom ]] || foreign_owner=1
      owners="${owners#*"${BASH_REMATCH[0]}"}"
    done
    (( owner_seen )) || ambiguous_owner=1
  done <<<"$output"
  if (( listener_found == 0 || ambiguous_owner )); then
    add_finding ERROR HEADROOM_LISTENER_OWNER_AMBIGUOUS "port ${HEADROOM_PORT}" \
      "Headroom listener ownership could not be determined."
  fi
  if (( unsafe_bind )); then
    add_finding FAIL HEADROOM_UNSAFE_BIND "port ${HEADROOM_PORT}" \
      "Headroom is not bound only to 127.0.0.1."
  fi
  if (( foreign_owner )); then
    add_finding FAIL HEADROOM_FOREIGN_LISTENER "port ${HEADROOM_PORT}" \
      "Headroom port is owned by another process."
  fi
}

listener_install_state() {
  local output row local_address owner

  if ! output="$("$SS_BIN" -ltnp "sport = :${HEADROOM_PORT}")"; then
    printf '%s\n' AMBIGUOUS
    return
  fi
  while IFS= read -r row; do
    if [[ "$row" == tcp* || "$row" == udp* ]]; then
      IFS=' ' read -r _ _ _ _ local_address _ <<<"$row"
    else
      IFS=' ' read -r _ _ _ local_address _ <<<"$row"
    fi
    [[ "$local_address" == *":${HEADROOM_PORT}" ]] || continue
    if [[ "$row" != *'users:(('* ]]; then
      printf '%s\n' AMBIGUOUS
      return
    fi
    owners="${row#*users:}"
    while [[ "$owners" =~ \"([^\"]+)\" ]]; do
      owner="${BASH_REMATCH[1]}"
      if [[ "$owner" != headroom ]]; then
        printf '%s\n' CONFLICT
        return
      fi
      owners="${owners#*"${BASH_REMATCH[0]}"}"
    done
    printf '%s\n' CONFLICT
    return
  done <<<"$output"
  printf '%s\n' ABSENT
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
  local output

  if ! output="$("$HEADROOM_BIN" plugins list 2>/dev/null)"; then
    add_finding ERROR HEADROOM_OPENCODE_PACKAGE_UNREADABLE headroom-opencode \
      "Headroom OpenCode package state could not be inspected."
  elif [[ "${output,,}" == *headroom-opencode* ]]; then
    add_finding FAIL HEADROOM_OPENCODE_PACKAGE_PRESENT headroom-opencode \
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
  if [[ -n "${HEADROOM_BIN:-}" ]]; then
    check_opencode_package
  fi
  check_opencode_environment
  check_unit_independence
}

audit_runtime() {
  audit_runtime_without_readiness
  check_readiness
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
  resolve_executable HEADROOM_BIN HRT_HEADROOM_BIN headroom
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

headroom_tool_path() {
  local bin_dir candidate

  bin_dir="${UV_TOOL_BIN_DIR:-${XDG_BIN_HOME:-$RUNTIME_HOME/.local/bin}}"
  candidate="$bin_dir/headroom"
  if [[ -x "$candidate" ]]; then
    readlink -f "$candidate"
  fi
}

headroom_package_state() {
  local candidate output

  candidate="${HRT_HEADROOM_BIN:-}"
  if [[ -n "$candidate" ]]; then
    resolve_executable HEADROOM_BIN HRT_HEADROOM_BIN headroom
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
      return
    fi
  fi
  if ! output="$("$HEADROOM_BIN" --version)"; then
    PACKAGE_STATE=UNINSPECTABLE
  elif [[ "$output" == "headroom ${HEADROOM_VERSION}" ]]; then
    PACKAGE_STATE=EXACT
  else
    PACKAGE_STATE=WRONG_VERSION
  fi
}

deployment_state() {
  local output enabled active

  if [[ -e "$MANIFEST_PATH" || -e "$SYSTEMD_USER_DIR/headroom-default.service" ]]; then
    F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
    check_manifest
    case "$(status_for_findings)" in
      ERROR)
        DEPLOYMENT_STATE=AMBIGUOUS
        return
        ;;
      FAIL)
        DEPLOYMENT_STATE=NONCONFORMING
        return
        ;;
      PASS|WARN)
        if ! enabled="$("$SYSTEMCTL_BIN" --user is-enabled headroom-default.service 2>/dev/null)" ||
          ! active="$("$SYSTEMCTL_BIN" --user is-active headroom-default.service 2>/dev/null)" ||
          [[ "$enabled" != enabled || "$active" != active ]]; then
          DEPLOYMENT_STATE=STOPPED
        else
          F_SEVERITY=() F_CODE=() F_SUBJECT=() F_MESSAGE=()
          check_listener
          check_generated_permissions
          check_opencode_config
          if [[ -n "${HEADROOM_BIN:-}" ]]; then
            check_opencode_package
          fi
          check_opencode_environment
          check_unit_independence
          case "$(status_for_findings)" in
            ERROR) DEPLOYMENT_STATE=AMBIGUOUS ;;
            FAIL) DEPLOYMENT_STATE=NONCONFORMING ;;
            PASS|WARN) DEPLOYMENT_STATE=CONFORMING ;;
          esac
        fi
        ;;
    esac
    return
  fi
  DEPLOYMENT_STATE="$(listener_install_state)"
}

classify_install_state() {
  headroom_package_state
  deployment_state
  if [[ "$DEPLOYMENT_STATE" == NONCONFORMING ]]; then
    INSTALL_STATE=NONCONFORMING
  elif [[ "$DEPLOYMENT_STATE" == AMBIGUOUS ]]; then
    INSTALL_STATE=AMBIGUOUS
  elif [[ "$DEPLOYMENT_STATE" == CONFLICT ]]; then
    INSTALL_STATE=CONFLICT
  elif [[ "$PACKAGE_STATE" == UNINSPECTABLE ]]; then
    INSTALL_STATE=AMBIGUOUS
  elif [[ "$PACKAGE_STATE" == WRONG_VERSION ]]; then
    INSTALL_STATE=WRONG_VERSION
  elif [[ "$PACKAGE_STATE" == ABSENT && "$DEPLOYMENT_STATE" != ABSENT ]]; then
    INSTALL_STATE=ORPHANED_DEPLOYMENT
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

readiness_is_ready() {
  local timeout="$1" body
  local subject="http://127.0.0.1:${HEADROOM_PORT}/readyz"

  if ! body="$("$CURL_BIN" --silent --show-error --fail --connect-timeout "$timeout" --max-time "$timeout" "$subject")"; then
    return 1
  fi
  # shellcheck disable=SC2016 # jq variables must remain literal for jq, not Bash.
  "$JQ_BIN" -e --arg version "$HEADROOM_VERSION" \
    '.ready == true and .version == $version' >/dev/null <<<"$body"
}

wait_for_readiness() {
  local started now elapsed remaining timeout

  started="$(uptime_centiseconds)"
  while :; do
    now="$(uptime_centiseconds)"
    elapsed=$((now - started))
    (( elapsed < 3000 )) || return 1
    remaining=$(((3000 - elapsed + 99) / 100))
    timeout=$(( remaining < 5 ? remaining : 5 ))
    if readiness_is_ready "$timeout"; then
      return 0
    fi
    now="$(uptime_centiseconds)"
    (( now - started < 3000 )) || return 1
    "$SLEEP_BIN" 1
  done
}

run_install() {
  local package_state final_status future_headroom
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
  if [[ "$PACKAGE_STATE" != ABSENT && "$PACKAGE_STATE" != UNINSPECTABLE ]]; then
    check_opencode_package
  fi
  final_status="$(status_for_findings)"
  if [[ "$final_status" != PASS ]]; then
    render_human "$final_status"
    [[ "$final_status" == ERROR ]] && return 2
    return 1
  fi
  case "$INSTALL_STATE" in
    CONFORMING)
      printf '%s\n' 'Headroom runtime is already installed and conforming.'
      return 0
      ;;
    STOPPED)
      printf '%s\n' 'ERROR: Headroom deployment is stopped or disabled; use systemctl --user start and enable headroom-default.service.' >&2
      return 1
      ;;
    ORPHANED_DEPLOYMENT)
      printf '%s\n' 'ERROR: Headroom deployment exists without the pinned runtime.' >&2
      return 1
      ;;
    WRONG_VERSION)
      printf '%s\n' 'ERROR: Headroom is not the pinned version; implicit upgrades are refused.' >&2
      return 1
      ;;
    NONCONFORMING|CONFLICT)
      F_SEVERITY=("${state_findings_severity[@]}") F_CODE=("${state_findings_code[@]}")
      F_SUBJECT=("${state_findings_subject[@]}") F_MESSAGE=("${state_findings_message[@]}")
      render_human "$state_findings_status"
      printf '%s\n' "ERROR: Headroom installation is ${INSTALL_STATE,,}; implicit repair is refused." >&2
      return 1
      ;;
    AMBIGUOUS)
      F_SEVERITY=("${state_findings_severity[@]}") F_CODE=("${state_findings_code[@]}")
      F_SUBJECT=("${state_findings_subject[@]}") F_MESSAGE=("${state_findings_message[@]}")
      render_human "$state_findings_status"
      printf '%s\n' 'ERROR: Headroom installation ownership could not be established.' >&2
      return 2
      ;;
  esac
  future_headroom="${UV_TOOL_BIN_DIR:-${XDG_BIN_HOME:-$RUNTIME_HOME/.local/bin}}/headroom"
  if [[ "$INSTALL_STATE" == ABSENT ]]; then
    install_package
    if [[ "$DRY_RUN" -eq 1 ]]; then
      apply_deployment "$future_headroom"
      return 0
    fi
    if [[ -x "$future_headroom" ]]; then
      HEADROOM_BIN="$future_headroom"
      if package_state="$("$HEADROOM_BIN" --version)" && [[ "$package_state" == "headroom ${HEADROOM_VERSION}" ]]; then
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
    printf '%s\n' 'ERROR: Headroom did not become ready within 30 seconds.' >&2
    return 1
  fi
  audit_runtime_without_readiness
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
    remove) : "$UNINSTALL_TOOL" "$UPTIME_FILE" ;;
    *) die_usage "unsupported command: $COMMAND" ;;
  esac
}

main "$@"
