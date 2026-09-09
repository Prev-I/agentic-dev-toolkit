#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Bounded startup-readiness probe for a persistent OpenCode server.
#
# READY = the HTTP API answers healthy AND the plugin surface has registered.
# Exits 0 only when both hold, non-zero once the bounded window closes.
#
# Run it from `ExecStartPost=`. Without it `systemctl start` returns as soon as
# the process exists, so the next command in a script races a server that is
# listening but not ready.
#
# WHY BOTH CHECKS. A server can answer HTTP 200 while a plugin failed to load:
# plugins build their tool table after their runtime initialises, and that
# initialisation is what throws when a plugin's own configuration is wrong — a
# missing channel token, for instance. If the server reports the plugin's tool,
# the plugin initialised. The server's *declared* configuration is not usable
# for this: it lists a plugin as configured even when that plugin failed.
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
MARKER="${READY_TOOL_MARKER:-gateway_status}"

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

  while (( SECONDS < deadline )); do
    if (( ! http_ok )) && curl_auth /global/health | grep -q '"healthy":true'; then
      http_ok=1
      printf 'readiness: OpenCode HTTP ready\n'
    fi
    if (( http_ok )) && (( ! tools_ok )) &&
        curl_auth /experimental/tool/ids | grep -q "\"${MARKER}\""; then
      tools_ok=1
      printf "readiness: plugin initialised (tool '%s' registered)\n" "$MARKER"
    fi
    if (( http_ok )) && (( tools_ok )); then
      printf 'readiness: READY\n'
      return 0
    fi
    sleep "$INTERVAL"
  done

  # The window closed. Report which half failed, without disclosing a secret.
  if (( ! http_ok )); then
    printf 'readiness: NOT READY after %ss — no healthy HTTP response on %s\n' \
      "$TIMEOUT" "$BASE" >&2
  else
    printf 'readiness: NOT READY after %ss — HTTP is healthy but the plugin did not register %s\n' \
      "$TIMEOUT" "$MARKER" >&2
    printf 'readiness: server alive, plugin dead. Check the plugin config and any token it needs.\n' >&2
  fi
  return 1
}

main "$@"
