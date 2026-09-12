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

usage() {
  cat <<EOF_USAGE
Usage: headroom-runtime.sh COMMAND [options]

Commands:
  install [--dry-run]
  audit [--json]
  remove [--dry-run] [--uninstall-tool]

Options:
  --help                       Show this help text.
  --version                    Show the tool version.
EOF_USAGE
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
  local env_name="$1"
  local default_name="$2"
  local candidate="${!env_name:-}"

  if [[ -n "$candidate" ]]; then
    [[ "$candidate" == /* ]] || die_usage "$env_name must be an absolute executable path"
    [[ -x "$candidate" ]] || die_usage "$env_name must be an absolute executable path"
  else
    candidate="$(command -v "$default_name" || true)"
    [[ -n "$candidate" ]] || die_usage "$default_name is required but was not found"
    candidate="$(readlink -f "$candidate")"
  fi

  printf '%s\n' "$candidate"
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
    install) UV_BIN="$(resolve_executable HRT_UV_BIN uv)" ;;
    audit|remove) return 0 ;;
  esac
}

main "$@"
