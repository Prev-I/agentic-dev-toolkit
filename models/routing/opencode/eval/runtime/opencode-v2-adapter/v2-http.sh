#!/usr/bin/env bash
# Authenticated, polled access to the OpenCode 2 HTTP API. Source this file.
#
#   v2_load_credentials FILE        set V2_PASSWORD from a dotenv file; 2 when
#                                   absent, empty, or holding " or \
#   v2_api_get URL_BASE PATH        GET, body to stdout; 0 on HTTP 200, 1 on any
#                                   other outcome, 2 when the password or URL is
#                                   unsafe to pass to curl
#   v2_agent_get URL_BASE ROLE DIR  poll until the agent resolves; print .data;
#                                   0 resolved, 1 refused/unreachable/timed out,
#                                   2 unsafe password or URL
#
# The password reaches curl only through a config on stdin (`curl -K -`), never
# in argv, where `ps` would show it. A password or URL containing a double
# quote, a backslash, a CR or a LF would break that config, so it is refused
# (return 2) before curl runs.
#
# Every request sets V2_LAST_STATUS (the HTTP code, or curl:<exit>) and
# V2_LAST_BODY. They are shell variables: a call inside `$(...)` sets them in
# that subshell only, and the caller's copies keep their earlier values. Call
# with output redirected to a file when the caller needs them.
set -Eeuo pipefail

V2_PASSWORD=${V2_PASSWORD:-}
V2_LAST_STATUS=''
V2_LAST_BODY=''

v2_load_credentials() {
  local file=${1:?v2_load_credentials: FILE required} name line value=''
  if [[ ! -f "$file" ]]; then
    printf 'v2_load_credentials: no such file: %s\n' "$file" >&2
    return 2
  fi
  for name in OPENCODE_PASSWORD OPENCODE_SERVER_PASSWORD; do
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$file" | tail -n 1 || true)
    [[ -n "$line" ]] || continue
    value=${line#*=}
    value=${value%"${value##*[![:space:]]}"}
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
      value=${value:1:${#value}-2}
    fi
    [[ -z "$value" ]] || break
  done
  if [[ -z "$value" ]]; then
    printf 'v2_load_credentials: no OPENCODE_PASSWORD or OPENCODE_SERVER_PASSWORD in %s\n' "$file" >&2
    return 2
  fi
  if [[ "$value" == *\"* || "$value" == *\\* ]]; then
    printf 'v2_load_credentials: the password in %s contains " or \\, which cannot be passed to curl safely; choose another\n' "$file" >&2
    return 2
  fi
  V2_PASSWORD=$value
}

# Internal: one GET. Sets V2_LAST_STATUS (HTTP code, or "curl:<exit>") and
# V2_LAST_BODY. Returns 0 on 200, 1 on any other outcome, 2 if the password or
# URL could not be passed to curl safely. Diagnostics go to stderr and never
# include the password.
_v2_request() {
  local base=$1 path=$2 url out rc=0
  V2_LAST_STATUS='' V2_LAST_BODY=''
  url="$base$path"
  if [[ -z "$V2_PASSWORD" || "$V2_PASSWORD" == *[$'"\\\r\n']* ]]; then
    printf 'v2_api_get: V2_PASSWORD is empty or contains a quote, backslash or line break\n' >&2
    return 2
  fi
  if [[ "$url" == *[$'"\\\r\n']* ]]; then
    printf 'v2_api_get: refusing a URL containing a quote, backslash or line break\n' >&2
    return 2
  fi
  out=$(printf 'user = "opencode:%s"\nsilent\nmax-time = 5\nnoproxy = "127.0.0.1,localhost"\nwrite-out = "\\n%%{http_code}"\nurl = "%s"\n' \
    "$V2_PASSWORD" "$url" | curl -q -K - 2>/dev/null) || rc=$?
  if (( rc != 0 )); then
    V2_LAST_STATUS="curl:$rc"
    printf 'v2_api_get: curl failed (exit %s) for %s\n' "$rc" "$path" >&2
    return 1
  fi
  V2_LAST_STATUS=${out##*$'\n'}
  V2_LAST_BODY=${out%$'\n'*}
  if [[ "$V2_LAST_STATUS" != 200 ]]; then
    printf 'v2_api_get: HTTP %s for %s\n' "$V2_LAST_STATUS" "$path" >&2
    return 1
  fi
}

v2_api_get() {
  local rc=0
  _v2_request "${1:?URL_BASE required}" "${2:?PATH required}" || rc=$?
  (( rc == 0 )) || return "$rc"
  printf '%s' "$V2_LAST_BODY"
}

v2_agent_get() {
  local base=${1:?URL_BASE required} role=${2:?ROLE required} dir=${3:?DIR required}
  local timeout=${V2_AGENT_POLL_TIMEOUT:-30}
  local deadline=$(( SECONDS + timeout )) grace=$(( SECONDS + 5 )) rc data encoded
  encoded=$(jq -rn --arg d "$dir" '$d|@uri')
  while :; do
    rc=0
    _v2_request "$base" "/api/agent/$role?directory=$encoded" 2>/dev/null || rc=$?
    case $rc in
      0)
        data=$(jq -c 'select(.data.model != null) | .data' <<<"$V2_LAST_BODY" 2>/dev/null || true)
        if [[ -n "$data" ]]; then
          printf '%s\n' "$data"
          return 0
        fi ;;
      2)
        printf 'v2_agent_get: V2_PASSWORD or the URL cannot be passed to curl safely\n' >&2
        return 2 ;;
    esac
    case $V2_LAST_STATUS in
      401|403)
        printf 'v2_agent_get: server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
        return 1 ;;
      curl:6|curl:7)
        if (( SECONDS >= grace )); then
          printf 'v2_agent_get: connection failure (%s) to %s; the server is not reachable\n' \
            "$V2_LAST_STATUS" "$base" >&2
          return 1
        fi ;;
    esac
    (( SECONDS < deadline )) || break
    sleep 0.25
  done
  printf 'v2_agent_get: agent %s did not resolve for %s within %ss (last status %s)\n' \
    "$role" "$dir" "$timeout" "$V2_LAST_STATUS" >&2
  return 1
}
