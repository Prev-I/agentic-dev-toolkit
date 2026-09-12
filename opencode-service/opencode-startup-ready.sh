#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Bounded startup-readiness probe for a persistent OpenCode server.
#
# READY = the HTTP API answers healthy AND a required tool has registered.
# Exits 0 only when both hold, non-zero once the bounded window closes.
#
# Run it from `ExecStartPost=`. Without it `systemctl start` returns as soon as
# the process exists, so the next command in a script races a server that is
# listening but not ready.
#
# WHY BOTH CHECKS. A server can answer HTTP 200 before its tool table is usable.
# The built-in `bash` tool is the gateway-neutral default. Set READY_TOOL_MARKER
# to a plugin-owned tool when the service must also prove that plugin initialised.
#
# DELIBERATELY LOCAL ONLY. No external call of any kind. An outage at a message
# channel a plugin talks to is a degraded dependency, not a reason to fail a
# start and have systemd restart the server.
#
# Credentials are read from the inherited environment and handed to curl over
# stdin via `-K -`, never as arguments, so they cannot appear in `ps`,
# /proc/<pid>/cmdline, the unit text or the journal.

HOST="${READY_HOST:-127.0.0.1}"
PORT="${READY_PORT:-4096}"
TIMEOUT="${READY_TIMEOUT:-90}"
INTERVAL="${READY_INTERVAL:-2}"
MARKER="${READY_TOOL_MARKER:-bash}"

readonly BASE="http://${HOST}:${PORT}"
readonly USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
readonly PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"

# curl options over stdin, so the password never enters the argument vector.
curl_auth() { # $1 = path; prints the body, returns curl's status
  printf 'user = "%s:%s"\nsilent\nshow-error\nfail\nmax-time = 5\nurl = "%s%s"\n' \
    "$USERNAME" "$PASSWORD" "$BASE" "$1" | curl -K - 2>/dev/null
}

main() {
  local deadline=$(( SECONDS + TIMEOUT ))
  local http_ok=0 tools_ok=0
  local health_body="" tools_body=""

  while true; do
    if (( ! http_ok )); then
      if health_body="$(curl_auth /global/health)" &&
          grep -q '"healthy":true' <<<"$health_body"; then
        http_ok=1
        printf 'readiness: OpenCode HTTP ready\n'
      fi
    fi
    if (( http_ok )) && (( ! tools_ok )); then
      if tools_body="$(curl_auth /experimental/tool/ids)" &&
          grep -q "\"${MARKER}\"" <<<"$tools_body"; then
        tools_ok=1
        printf "readiness: tool '%s' registered\n" "$MARKER"
      fi
    fi
    if (( http_ok )) && (( tools_ok )); then
      printf 'readiness: READY\n'
      return 0
    fi
    (( SECONDS >= deadline )) && break
    sleep "$INTERVAL"
  done

  # The window closed. Report which half failed, without disclosing a secret.
  if (( ! http_ok )); then
    printf 'readiness: NOT READY after %ss — no healthy HTTP response on %s\n' \
      "$TIMEOUT" "$BASE" >&2
  else
    printf 'readiness: NOT READY after %ss — HTTP is healthy but tool %s is absent\n' \
      "$TIMEOUT" "$MARKER" >&2
    printf 'readiness: server alive, required tool unavailable. Check OpenCode and plugin logs.\n' >&2
  fi
  return 1
}

main "$@"
