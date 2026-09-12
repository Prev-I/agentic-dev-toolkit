#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="0.1.0"
readonly HEADROOM_VERSION="0.37.0"
readonly HEADROOM_PYTHON="3.13"
readonly HEADROOM_PROFILE="default"
readonly HEADROOM_PORT="8787"
readonly HEADROOM_PACKAGE="headroom-ai[proxy]==${HEADROOM_VERSION}"

DRY_RUN=0
JSON_MODE=0
UNINSTALL_TOOL=0
COMMAND=""
UV_BIN=""
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
  printf 'ERROR: %s\n' "$1" >&2
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

resolve_executable() {
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
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json) JSON_MODE=1 ;;
          *) die_usage "unknown audit option: $1" ;;
        esac
        shift
      done
      COMMAND="audit"
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
      resolve_executable UV_BIN HRT_UV_BIN uv
      [[ -n "$UV_BIN" ]] || die_usage "uv is required but was not found"
      ;;
    audit) : "$JSON_MODE" "$UPTIME_FILE" ;;
    remove) : "$UNINSTALL_TOOL" "$UPTIME_FILE" ;;
    *) die_usage "unsupported command: $COMMAND" ;;
  esac
}

main "$@"
