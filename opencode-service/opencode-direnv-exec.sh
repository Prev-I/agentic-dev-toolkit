#!/usr/bin/env bash
# jq programs and the child shell deliberately expand their own variables.
# shellcheck disable=SC2016
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION='0.1.0'
fail() { printf 'opencode-direnv: %s\n' "$*" >&2; exit 1; }

main() {
  if [[ "${1:-}" == --version ]]; then
    printf '%s\n' "$SCRIPT_VERSION"
    return 0
  fi
  (( $# )) || fail 'expected a server command and arguments'
  local root="${OPENCODE_DIRENV_ROOT:-$HOME/code}"
  [[ "$root" == /* && -d "$root" ]] || fail 'scan root must be an existing absolute directory'
  local -a names=() clean_env=()
  local IFS=$' \t\n'
  local allowlist="${OPENCODE_DIRENV_VARS:-}"
  [[ "$allowlist" != *$'\n'* ]] || fail 'allowlist must be a single line'
  read -r -a names <<< "$allowlist"
  (( ${#names[@]} )) || fail 'OPENCODE_DIRENV_VARS must name variables to import'

  local name direnv_bin jq_bin bash_bin timeout_bin
  direnv_bin="$(command -v direnv)" || fail 'direnv is required'
  jq_bin="$(command -v jq)" || fail 'jq is required'
  bash_bin="$(command -v bash)" || fail 'bash is required'
  timeout_bin="$(command -v timeout)" || fail 'timeout is required'
  local -A values=() sources=()
  for name in "${names[@]}"; do
    [[ "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]] || fail 'allowlist names must be uppercase environment identifiers'
    case "$name" in
      PATH|HOME|PWD|OLDPWD|SHELL|SHLVL|_|WORKSPACE_ROOT|SCRIPT_VERSION|BASH*|ENV|IFS|CDPATH|SHELLOPTS|DIRENV_*|MISE_*|OPENCODE_*|XDG_*|LD_*|READY_*|INVOCATION_ID|NOTIFY_SOCKET|LISTEN_*|JOURNAL_STREAM|SYSTEMD_*)
        fail "reserved variable in allowlist: $name" ;;
    esac
    clean_env+=(-u "$name")
    if [[ -v "$name" ]]; then
      values["$name"]="${!name}"
      sources["$name"]='service environment'
    fi
  done
  # No interactive direnv state may cause one workspace to unload another.
  while IFS= read -r name; do
    [[ "$name" == DIRENV_CONFIG ]] && continue
    clean_env+=(-u "$name")
  done < <(compgen -e DIRENV_ || true)

  local workspace data value count=0
  shopt -s nullglob dotglob
  for workspace in "$root"/*; do
    [[ -d "$workspace" && ! -L "$workspace" && -f "$workspace/.envrc" ]] || continue
    # Suppress arbitrary .envrc stdout/stderr; only the extractor writes fd 3.
    # Each workspace starts from the same baseline, never from merged values.
    if ! data="$(
      env "${clean_env[@]}" "$timeout_bin" 20s "$direnv_bin" exec "$workspace" \
        "$bash_bin" --noprofile --norc -c '
          exec "$1" -cn --args '\''env as $e | reduce $ARGS.positional[] as $k ({}; if $e | has($k) then .[$k] = $e[$k] else . end)'\'' "${@:2}" >&3
        ' opencode-direnv "$jq_bin" "${names[@]}" 3>&1 >/dev/null 2>/dev/null
    )"; then
      fail "direnv evaluation failed, blocked or timed out: $workspace (check direnv status locally)"
    fi
    "$jq_bin" -e 'type == "object" and all(.[]; type == "string")' <<< "$data" >/dev/null \
      || fail "invalid direnv output: $workspace"
    for name in "${names[@]}"; do
      "$jq_bin" -e --arg key "$name" 'has($key)' <<< "$data" >/dev/null || continue
      # NUL delimiter retains empty values, whitespace and trailing newlines.
      IFS= read -r -d '' value < <("$jq_bin" -j --arg key "$name" '.[$key], "\u0000"' <<< "$data")
      if [[ -v "sources[$name]" && "${values[$name]}" != "$value" ]]; then
        fail "conflicting $name: ${sources[$name]} and $workspace"
      fi
      values["$name"]="$value"
      sources["$name"]="$workspace"
    done
    (( count += 1 ))
    printf 'opencode-direnv: loaded %s\n' "$workspace" >&2
  done
  for name in "${names[@]}"; do
    [[ -v "sources[$name]" ]] || printf 'opencode-direnv: variable not provided: %s\n' "$name" >&2
  done
  for name in "${!values[@]}"; do
    export "$name=${values[$name]}"
  done
  printf 'opencode-direnv: %s workspace(s), %s variable(s); starting server\n' "$count" "${#values[@]}" >&2
  exec "$@"
}

main "$@"
