#!/usr/bin/env bash
# Authenticated, polled access to the OpenCode 2 HTTP API. Source this file.
#
#   v2_load_credentials FILE        set V2_PASSWORD from a dotenv file
#   v2_api_get URL_BASE PATH        GET, body to stdout; 0 on HTTP 200, else 1
#   v2_agent_get URL_BASE ROLE DIR  poll until the agent resolves; print .data
#
# The password reaches curl only through a config on stdin (`curl -K -`), never
# in argv, where `ps` would show it. A password containing a double quote or a
# backslash would break that config, so such a password is refused.
set -Eeuo pipefail

V2_PASSWORD=${V2_PASSWORD:-}

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
    value=${value%$'\r'}
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

v2_api_get() {
  local base=${1:?URL_BASE required} path=${2:?PATH required} url out code
  url="$base$path"
  if [[ "$url" == *\"* || "$url" == *\\* ]]; then
    printf 'v2_api_get: refusing a URL containing " or \\\n' >&2
    return 1
  fi
  out=$(printf 'user = "opencode:%s"\nsilent\nmax-time = 5\nwrite-out = "\\n%%{http_code}"\nurl = "%s"\n' \
    "$V2_PASSWORD" "$url" | curl -K - 2>/dev/null) || return 1
  code=${out##*$'\n'}
  [[ "$code" == 200 ]] || return 1
  printf '%s' "${out%$'\n'*}"
}

v2_agent_get() {
  local base=${1:?URL_BASE required} role=${2:?ROLE required} dir=${3:?DIR required}
  local deadline=$(( SECONDS + ${V2_AGENT_POLL_TIMEOUT:-30} )) body data
  while :; do
    if body=$(v2_api_get "$base" "/api/agent/$role?directory=$dir"); then
      data=$(jq -c 'select(.data.model != null) | .data' <<<"$body" 2>/dev/null || true)
      if [[ -n "$data" ]]; then
        printf '%s\n' "$data"
        return 0
      fi
    fi
    (( SECONDS < deadline )) || break
    sleep 0.25
  done
  printf 'v2_agent_get: agent %s did not resolve for %s within %ss\n' \
    "$role" "$dir" "${V2_AGENT_POLL_TIMEOUT:-30}" >&2
  return 1
}
