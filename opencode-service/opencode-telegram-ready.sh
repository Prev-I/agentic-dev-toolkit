#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Readiness probe for a Telegram sidecar that connects to a persistent OpenCode
# server. The polling marker is scoped to this systemd invocation so a previous
# successful start cannot satisfy a new one.

readonly TIMEOUT="${TELEGRAM_READY_TIMEOUT:-60}"
readonly INTERVAL="${TELEGRAM_READY_INTERVAL:-1}"
readonly OPENCODE_URL="${OPENCODE_API_URL:-http://127.0.0.1:4096}"
readonly USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
readonly PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"

: "${INVOCATION_ID:?systemd invocation id is required}"

readonly DEADLINE=$((SECONDS + TIMEOUT))

main() {
  local polling_ready=0
  local opencode_ready=0
  local health_body=""

  while true; do
    if journalctl \
        "_SYSTEMD_INVOCATION_ID=$INVOCATION_ID" \
        --grep='Bot @[^ ]+ started!' \
        --quiet \
        --no-pager; then
      polling_ready=1
    fi

    if health_body="$(
      printf 'user = "%s:%s"\nsilent\nshow-error\nfail\nmax-time = 5\nurl = "%s/global/health"\n' \
        "$USERNAME" "$PASSWORD" "${OPENCODE_URL%/}" |
        curl -K - 2>/dev/null
    )" && grep -q '"healthy":true' <<<"$health_body"; then
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
    printf 'telegram-readiness: OpenCode health unavailable at %s/global/health\n' \
      "${OPENCODE_URL%/}" >&2
  fi
  printf 'telegram-readiness: NOT READY after %ss\n' "$TIMEOUT" >&2
  return 1
}

main "$@"
