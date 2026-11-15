#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Makes systemd the executor for a plugin-requested OpenCode server restart.
#
# THE PROBLEM THIS SOLVES
# A plugin that can ask for a restart — so new skills, agents or configuration
# take effect — generally cannot perform one: it lives inside the very process
# that must be replaced. Plugins in that position write a request to a control
# directory and rely on whatever supervises the server to carry it out. When
# that supervisor is the plugin vendor's own launcher, this is handled for you.
# Under `systemd --user` there is no such supervisor, so the request is written
# and nothing ever consumes it, and the plugin's restart tool reports itself
# unavailable — or worse, reports success and restarts nothing.
#
# This script is the missing consumer. Run it path-activated on the control
# directory, and systemd becomes the executor.
#
#   restart-request.json   {requestedAtMs, requestedBy}       written by the plugin
#   restart-status.json    {state, requestedAtMs, startedAtMs,
#                           completedAtMs, lastError}         the shared record
#   state ∈ pending | restarting | idle | failed
#
# TWO WAYS IN, because the plugin has two. The request file is written when a
# queued turn — a message or a scheduled job — finishes, so by the time it
# appears the turn that asked is already over. A bare `pending` status with no
# request file is the interactive case: the tool records the intent immediately
# but defers the file to the next completed queued turn, which for an attached
# terminal session may never arrive. Both are honoured, so the tool behaves the
# same from any session.
#
# IDLE-WAIT. The restart must not land mid-turn, and the request file appearing
# only proves the *asking* turn ended, not that a concurrent one has. So the
# server is polled until it reports no active session, and the unit is never
# restarted while mid-start, which would cut off a readiness probe in flight.
# An unanswered poll counts as idle: nothing can be in flight through an API
# that is not answering, and a restart is the right move for a server in that
# state anyway.
#
# WRITING NOTHING WHEN THERE IS NOTHING TO DO IS LOAD-BEARING. This script is
# path-activated on files it also writes. A run that finds no work must produce
# no write, and that silence is what stops the trigger chain.
#
# Credentials are read from the inherited environment and handed to curl over
# stdin via `-K -`, never as arguments, so they cannot appear in `ps`,
# /proc/<pid>/cmdline, the unit text or the journal.
#
# OPENCODE 1.x ONLY. The idle signal is the 1.x endpoint /session/status, which
# 2.x does not provide. When an authenticated /api/info identifies the server as
# 2.x, the consumer refuses: it consumes the request, records `failed` and
# restarts nothing, because acting on a signal it cannot read is worse than
# declining.
#
# A SESSION STATUS THAT CANNOT BE READ IS NOT IDLE. Only a connection that does
# not answer at all counts as idle. An HTTP error, an HTML page or any non-JSON
# body from /session/status says nothing about running sessions, and restarting
# on it would cut a turn off.
#
# Requires `jq`. Install it from a system path: a unit does not inherit a
# version manager's shims.

CONTROL_DIR="${OPENCODE_GATEWAY_CONTROL_DIR:-$HOME/.config/opencode-gateway/opencode/control}"
UNIT="${RESTART_TARGET_UNIT:-opencode.service}"
TIMEOUT="${RESTART_IDLE_TIMEOUT:-300}"
INTERVAL="${RESTART_IDLE_INTERVAL:-3}"
HOST="${READY_HOST:-127.0.0.1}"
PORT="${READY_PORT:-4096}"

readonly SCRIPT_VERSION="0.2.0"
readonly REQUEST="$CONTROL_DIR/restart-request.json"
readonly STATUS="$CONTROL_DIR/restart-status.json"
readonly BASE="http://${HOST}:${PORT}"
readonly USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
readonly PASSWORD="${OPENCODE_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"

now_ms() { printf '%s000\n' "$(date +%s)"; }

# Atomic, because a partial read is not a harmless race here: the plugin parses
# this file and treats malformed JSON as an error rather than as absent, so a
# torn write surfaces as a broken gateway.
write_status() { # $1 state  $2 requestedAtMs  $3 startedAtMs|null  $4 completedAtMs|null  $5 lastError|""
  local tmp="$STATUS.tmp.$$"
  local err='null'

  # `[[ ... ]] && err=...` would abort the script under `set -e` whenever the
  # message is empty, which is the successful path.
  if [[ -n "${5:-}" ]]; then
    err="$(jq -Rn --arg v "$5" '$v')"
  fi
  jq -n \
    --arg state "$1" \
    --argjson requestedAtMs "$2" \
    --argjson startedAtMs "$3" \
    --argjson completedAtMs "$4" \
    --argjson lastError "$err" \
    '{state: $state, requestedAtMs: $requestedAtMs, startedAtMs: $startedAtMs,
      completedAtMs: $completedAtMs, lastError: $lastError}' > "$tmp"
  mv -f "$tmp" "$STATUS"
}

read_field() { # $1 file  $2 jq filter; prints the value, or fails
  [[ -f "$1" ]] || return 1
  jq -er "$2" < "$1" 2>/dev/null
}

# One authenticated request. Sets HTTP_CODE ("000" when curl could not connect)
# and HTTP_BODY. A 2.x server always uses the username `opencode`.
http_get() { # $1 = path  $2 = username
  local out
  if out="$(printf 'user = "%s:%s"\nsilent\nshow-error\nmax-time = 5\nwrite-out = "\\n%%{http_code}"\nurl = "%s%s"\n' \
      "$2" "$PASSWORD" "$BASE" "$1" | curl -K - 2>/dev/null)"; then
    HTTP_CODE="${out##*$'\n'}"
    HTTP_BODY="${out%$'\n'*}"
  else
    HTTP_CODE="000"
    HTTP_BODY=""
  fi
}

# True when an authenticated /api/info is JSON reporting major 2.
is_v2_server() {
  http_get /api/info opencode
  [[ "$HTTP_CODE" == 200 ]] || return 1
  jq -e '(.version // "") | test("^2\\.")' >/dev/null 2>&1 <<< "$HTTP_BODY"
}

is_idle() {
  local state

  state="$(systemctl --user show -p ActiveState --value "$UNIT" 2>/dev/null || true)"
  case "$state" in
    activating | deactivating | reloading) return 1 ;;
  esac

  http_get /session/status "$USERNAME"
  # Nothing is in flight through an API that is not answering.
  [[ "$HTTP_CODE" == "000" ]] && return 0
  # Anything else that is not the session map is not evidence of idleness.
  [[ "$HTTP_CODE" == 200 ]] || return 1
  jq -e 'type == "object" and length == 0' >/dev/null 2>&1 <<< "$HTTP_BODY"
}

# Prints the requested-at stamp when there is work, and fails when there is not.
find_work() {
  local requested

  if requested="$(read_field "$REQUEST" '.requestedAtMs')"; then
    :
  elif [[ "$(read_field "$STATUS" '.state' || true)" == "pending" ]]; then
    requested="$(read_field "$STATUS" '.requestedAtMs' || true)"
  else
    return 1
  fi

  # A request carrying no usable stamp is still a request; date it now rather
  # than discarding it.
  case "$requested" in
    '' | *[!0-9]*) requested="$(now_ms)" ;;
  esac
  printf '%s\n' "$requested"
}

wait_until_idle() {
  local deadline=$(( SECONDS + TIMEOUT ))

  while (( SECONDS < deadline )); do
    if is_idle; then
      return 0
    fi
    sleep "$INTERVAL"
  done
  return 1
}

main() {
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "$SCRIPT_VERSION"
    exit 0
  fi

  local requested started message

  requested="$(find_work)" || return 0

  if is_v2_server; then
    # Consume the request, or the path unit re-triggers this script for ever.
    rm -f "$REQUEST"
    message="the server is OpenCode 2.x; this consumer supports 1.x only (its idle signal, /session/status, does not exist on 2.x); restart not performed"
    printf 'gateway-restart: %s\n' "$message" >&2
    write_status failed "$requested" "$(now_ms)" "$(now_ms)" "$message"
    return 1
  fi

  started="$(now_ms)"
  printf 'gateway-restart: request accepted (requestedAtMs=%s), waiting for %s to go idle\n' \
    "$requested" "$UNIT"
  write_status restarting "$requested" "$started" null ''

  if ! wait_until_idle; then
    # Consume the request rather than leaving it to re-trigger this unit for
    # ever. The failure is visible in the status file, and re-asking is one
    # tool call.
    rm -f "$REQUEST"
    message="not idle after ${TIMEOUT}s; restart not performed"
    printf 'gateway-restart: %s\n' "$message" >&2
    write_status failed "$requested" "$started" "$(now_ms)" "$message"
    return 1
  fi

  # Consume before restarting: a PathExists trigger fires again while the file
  # is still there.
  rm -f "$REQUEST"

  local output
  if output="$(systemctl --user restart "$UNIT" 2>&1)"; then
    printf 'gateway-restart: %s restarted\n' "$UNIT"
    write_status idle "$requested" "$started" "$(now_ms)" ''
    return 0
  fi

  message="systemctl --user restart ${UNIT} failed: ${output}"
  printf 'gateway-restart: %s\n' "$message" >&2
  write_status failed "$requested" "$started" "$(now_ms)" "$message"
  return 1
}

main "$@"
