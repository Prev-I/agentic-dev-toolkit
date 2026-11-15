#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Readiness probe for a Telegram sidecar that connects to a persistent OpenCode
# server. The polling marker is scoped to this systemd invocation so a previous
# successful start cannot satisfy a new one.
#
# OpenCode must answer as a 2.x server: an authenticated GET /api/info returning
# HTTP 200, a JSON body, and a `version` with major 2. A status code or a
# substring is not enough, because the server's web UI answers 200 text/html on
# paths it does not own. There is no MAINPID comparison: MAINPID in this unit is
# the bot's, not the server's.
#
# Requires `jq`, from a system path: a unit does not inherit a version
# manager's shims.
#
# Like the server probe, it gives up as soon as the MAINPID systemd hands to
# `ExecStartPost=` is gone, so a bot that dies at once fails its start at once
# and the unit's start limit stays reachable.

readonly TIMEOUT="${TELEGRAM_READY_TIMEOUT:-60}"
readonly INTERVAL="${TELEGRAM_READY_INTERVAL:-1}"
readonly OPENCODE_URL="${OPENCODE_API_URL:-http://127.0.0.1:4096}"
# The Basic-auth username is always `opencode`; the password is
# OPENCODE_PASSWORD, else OPENCODE_SERVER_PASSWORD.
readonly USERNAME="opencode"
readonly PASSWORD="${OPENCODE_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"
readonly BOT_PID="${MAINPID:-}"
readonly SCRIPT_VERSION="1.0.0"

# Answered here, at the top level, rather than as the first statement of main
# like the sibling helpers do: the INVOCATION_ID requirement below runs before
# main is ever called, so a guard inside main would let `--version` die on a
# missing systemd invocation id instead of printing the version.
#
# An `if` rather than `[[ ... ]] && { ...; }`, matching the sibling helpers.
# At this top-level position the `&&` form would in fact be safe -- `set -e`
# exempts a command that is part of an `&&` list -- but the `if` is safe in
# EVERY position, including the one where the `&&` form does bite: as a
# function's last statement, where it returns non-zero and fails the caller.
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' "$SCRIPT_VERSION"
  exit 0
fi

: "${INVOCATION_ID:?systemd invocation id is required}"

readonly DEADLINE=$((SECONDS + TIMEOUT))

# True while the bot process exists, or when there is no PID to watch.
bot_alive() {
  [[ "$BOT_PID" =~ ^[1-9][0-9]*$ ]] || return 0
  kill -0 "$BOT_PID" 2>/dev/null
}

# True when an authenticated /api/info is HTTP 200 JSON reporting major 2.
opencode_is_2x() {
  local out code body
  out="$(
    printf 'user = "%s:%s"\nsilent\nshow-error\nmax-time = 5\nwrite-out = "\\n%%{http_code}"\nurl = "%s/api/info"\n' \
      "$USERNAME" "$PASSWORD" "${OPENCODE_URL%/}" |
      curl -K - 2>/dev/null
  )" || return 1
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ "$code" == 200 ]] || return 1
  jq -e '(.version // "") | test("^2\\.")' >/dev/null 2>&1 <<<"$body"
}

main() {
  local polling_ready=0
  local opencode_ready=0

  while true; do
    if ! bot_alive; then
      printf 'telegram-readiness: NOT READY — main process %s exited during startup\n' \
        "$BOT_PID" >&2
      return 1
    fi
    # --quiet silences journalctl's notices, not its matches. Printed, a match
    # lands in this invocation's own journal and matches again on every later
    # poll, so the output must be discarded.
    if (( ! polling_ready )) && journalctl \
        "_SYSTEMD_INVOCATION_ID=$INVOCATION_ID" \
        --grep='Bot @[^ ]+ started!' \
        --quiet \
        --no-pager >/dev/null; then
      polling_ready=1
    fi

    if opencode_is_2x; then
      opencode_ready=1
    fi

    if (( polling_ready && opencode_ready )); then
      printf 'telegram-readiness: READY\n'
      return 0
    fi
    (( SECONDS >= DEADLINE )) && break
    sleep "$INTERVAL"
  done

  if (( ! polling_ready )); then
    printf 'telegram-readiness: polling marker absent for current invocation\n' >&2
  fi
  if (( ! opencode_ready )); then
    printf 'telegram-readiness: OpenCode 2.x API unavailable at %s/api/info\n' \
      "${OPENCODE_URL%/}" >&2
  fi
  printf 'telegram-readiness: NOT READY after %ss\n' "$TIMEOUT" >&2
  return 1
}

main "$@"
