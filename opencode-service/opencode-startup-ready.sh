#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Bounded startup-readiness probe for a persistent OpenCode 2.x server.
#
# READY requires ALL of the following. Exits 0 only then, and non-zero once the
# bounded window closes:
#   1. an authenticated GET /api/info answers HTTP 200;
#   2. the body parses as JSON;
#   3. its `version` has major 2;
#   4. its `pid` equals MAINPID, when systemd handed one over;
#   5. GET /api/experimental/migration/v1 does not report a status other than
#      `completed` (the first 2.x start migrates a 1.x database in place).
#      `running` and `required` wait; `error` and any unrecognised status or
#      body fail at once, because waiting cannot fix them. An endpoint that does
#      not answer 200 says nothing about a migration and is not a reason to wait;
#   6. an UNauthenticated GET /api/info answers 401.
#
# Run it from `ExecStartPost=`. Without it `systemctl start` returns as soon as
# the process exists, so the next command in a script races a server that is
# listening but not ready.
#
# WHY NOT A STATUS CODE OR A GREP. The server's web UI answers HTTP 200 text/html
# on any path it does not own, /global/health included, and does so without
# credentials. A 200, or a substring in a body, therefore proves nothing: the
# body must parse as the JSON the API returns, and say 2.x.
#
# AN OPEN ANSWER IS A FAILURE, NOT A WAIT. A 2.x server started without a
# password still enforces authentication (it generates one), so an anonymous 200
# is not expected from the server itself. It is checked defensively, against a
# proxy or a future change, and fails at once so a misconfigured unit trips its
# start limit.
#
# A REJECTED PASSWORD IS A FAILURE, NOT A WAIT. The unit and this probe read the
# same EnvironmentFile, so a persistent 401 on the authenticated request is
# misconfiguration. After AUTH_GRACE consecutive 401s the probe fails at once;
# polling the whole window on every start would defeat the start limit.
#
# 2.x ONLY. A detected 1.x server (/global/health answering JSON with
# "healthy":true) fails at once, so a unit that still starts the old binary trips
# the start limit instead of polling out its window on every cycle.
# READY_TOOL_MARKER is an error: 2.x has no endpoint listing tool IDs, so the
# 1.x guarantee that a given tool registered cannot be reproduced.
#
# FAIL FAST ON A DEAD SERVER. systemd hands `ExecStartPost=` the server's PID as
# MAINPID. Once that process is gone the probe exits at once instead of polling
# out the window: a start that fails in 1s must cost ~1s, or each crash-loop
# cycle outlasts StartLimitIntervalSec and the start limit can never trip.
# Without MAINPID (a manual run) the probe only polls and skips the pid check.
#
# DELIBERATELY LOCAL ONLY. No external call of any kind. An outage at a message
# channel a plugin talks to is a degraded dependency, not a reason to fail a
# start and have systemd restart the server.
#
# Credentials are read from the inherited environment and handed to curl over
# stdin via `-K -`, never as arguments, so they cannot appear in `ps`,
# /proc/<pid>/cmdline, the unit text or the journal. The Basic-auth username is
# always `opencode`; the password is OPENCODE_PASSWORD, else
# OPENCODE_SERVER_PASSWORD (OPENCODE_PASSWORD wins, as on the server).
#
# Requires `jq`. Install it from a system path: a unit does not inherit a
# version manager's shims.

HOST="${READY_HOST:-127.0.0.1}"
PORT="${READY_PORT:-4096}"
TIMEOUT="${READY_TIMEOUT:-90}"
INTERVAL="${READY_INTERVAL:-2}"

readonly SCRIPT_VERSION="1.0.0"
readonly AUTH_GRACE=3
readonly BASE="http://${HOST}:${PORT}"
readonly USERNAME="opencode"
readonly PASSWORD="${OPENCODE_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"
readonly SERVER_PID="${MAINPID:-}"

# True while the server process exists, or when there is no PID to watch.
server_alive() {
  [[ "$SERVER_PID" =~ ^[1-9][0-9]*$ ]] || return 0
  kill -0 "$SERVER_PID" 2>/dev/null
}

# One request; sets HTTP_CODE ("000" when curl itself failed) and HTTP_BODY.
# Credentials go over stdin so they never enter the argument vector. With
# `auth` off, no credentials are sent at all.
http_get() { # $1 = path  $2 = auth|anonymous
  local config out
  config="$(printf 'silent\nshow-error\nmax-time = 5\nwrite-out = "\\n%%{http_code}"\nurl = "%s%s"\n' "$BASE" "$1")"
  if [[ "$2" == auth ]]; then
    config="$(printf 'user = "%s:%s"\n' "$USERNAME" "$PASSWORD")"$'\n'"$config"
  fi
  if out="$(printf '%s\n' "$config" | curl -K - 2>/dev/null)"; then
    HTTP_CODE="${out##*$'\n'}"
    HTTP_BODY="${out%$'\n'*}"
  else
    HTTP_CODE="000"
    HTTP_BODY=""
  fi
}

# A 1.x server answers /global/health with JSON; 2.x answers with its web UI.
is_v1_server() {
  http_get /global/health auth
  [[ "$HTTP_CODE" == 200 ]] && jq -e '.healthy == true' >/dev/null 2>&1 <<<"$HTTP_BODY"
}

# Why the last /api/info answer was not enough; empty when it was.
NOT_READY_REASON=""
INFO_VERSION=""
AUTH_REJECTIONS=0

check_api_info() {
  local version pid
  http_get /api/info auth
  if [[ "$HTTP_CODE" == 401 ]]; then
    AUTH_REJECTIONS=$(( AUTH_REJECTIONS + 1 ))
    NOT_READY_REASON="/api/info answered HTTP 401: the password was rejected"
    (( AUTH_REJECTIONS < AUTH_GRACE )) || return 2
    return 1
  fi
  AUTH_REJECTIONS=0
  if [[ "$HTTP_CODE" != 200 ]]; then
    NOT_READY_REASON="/api/info answered HTTP $HTTP_CODE"
    return 1
  fi
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$HTTP_BODY"; then
    NOT_READY_REASON="/api/info did not return JSON (a web UI fallback, not the API)"
    return 1
  fi
  version="$(jq -r '.version // empty' <<<"$HTTP_BODY")"
  if [[ ! "$version" =~ ^2\. ]]; then
    NOT_READY_REASON="/api/info reports version '${version:-none}', not 2.x"
    return 1
  fi
  INFO_VERSION="$version"
  if [[ "$SERVER_PID" =~ ^[1-9][0-9]*$ ]]; then
    pid="$(jq -r '.pid // empty' <<<"$HTTP_BODY")"
    if [[ "$pid" != "$SERVER_PID" ]]; then
      NOT_READY_REASON="/api/info pid '${pid:-none}' does not match MAINPID $SERVER_PID"
      return 1
    fi
  fi
  return 0
}

# Returns 0 when ready to go on, 1 to keep waiting, 2 to fail at once.
check_migration() {
  local status
  http_get /api/experimental/migration/v1 auth
  [[ "$HTTP_CODE" == 200 ]] || return 0
  status="$(jq -r 'if type == "object" then (.status // "") else "" end' 2>/dev/null <<<"$HTTP_BODY" || true)"
  case "$status" in
    completed) return 0 ;;
    running | required)
      NOT_READY_REASON="data migration is $status"
      return 1
      ;;
    error)
      NOT_READY_REASON="data migration failed: $(jq -r '.error // "no detail"' <<<"$HTTP_BODY")"
      return 2
      ;;
    *)
      NOT_READY_REASON="data migration reports an unrecognised state"
      return 2
      ;;
  esac
}

main() {
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "$SCRIPT_VERSION"
    exit 0
  fi

  if [[ -n "${READY_TOOL_MARKER+x}" ]]; then
    printf 'readiness: READY_TOOL_MARKER is not supported on OpenCode 2.x: it has no endpoint that lists tool IDs, so the tool guarantee cannot be checked. Unset it.\n' >&2
    return 2
  fi
  if [[ -z "$PASSWORD" ]]; then
    printf 'readiness: OPENCODE_PASSWORD (or OPENCODE_SERVER_PASSWORD) is not set; a password is mandatory and the probe cannot authenticate without it\n' >&2
    return 2
  fi
  command -v jq >/dev/null 2>&1 || {
    printf 'readiness: jq is required\n' >&2
    return 2
  }

  local deadline=$(( SECONDS + TIMEOUT ))
  local reported=""

  while true; do
    if ! server_alive; then
      printf 'readiness: NOT READY — main process %s exited during startup\n' \
        "$SERVER_PID" >&2
      return 1
    fi

    if is_v1_server; then
      printf 'readiness: NOT READY — this is an OpenCode 1.x server (/global/health reports healthy); this probe and its unit are for 2.x. Swap the unit and probe as a pair.\n' >&2
      return 1
    fi

    NOT_READY_REASON=""
    local info_status=0 migration_status=0
    check_api_info || info_status=$?
    if (( info_status == 0 )); then
      check_migration || migration_status=$?
    fi
    if (( info_status == 2 || migration_status == 2 )); then
      printf 'readiness: NOT READY — %s\n' "$NOT_READY_REASON" >&2
      return 1
    fi
    if (( info_status == 0 && migration_status == 0 )); then
      http_get /api/info anonymous
      case "$HTTP_CODE" in
        401)
          printf 'readiness: OpenCode %s, authentication enforced\n' "$INFO_VERSION"
          printf 'readiness: READY\n'
          return 0
          ;;
        200)
          printf 'readiness: NOT READY — an unauthenticated /api/info answered 200: the server runs without a password\n' >&2
          return 1
          ;;
        *)
          NOT_READY_REASON="an unauthenticated /api/info answered HTTP $HTTP_CODE, expected 401"
          ;;
      esac
    fi

    if [[ "$NOT_READY_REASON" == "data migration"* && "$reported" != "$NOT_READY_REASON" ]]; then
      printf 'readiness: waiting, %s\n' "$NOT_READY_REASON"
      reported="$NOT_READY_REASON"
    fi
    (( SECONDS >= deadline )) && break
    sleep "$INTERVAL"
  done

  # The window closed. Say why, without disclosing a secret.
  printf 'readiness: NOT READY after %ss on %s — %s\n' \
    "$TIMEOUT" "$BASE" "${NOT_READY_REASON:-no response}" >&2
  return 1
}

main "$@"
