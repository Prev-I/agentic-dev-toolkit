#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=./test-lib.sh disable=SC1091
source "$root/tests/test-lib.sh"
# shellcheck source=../runtime/opencode-v2-adapter/v2-http.sh disable=SC1091
source "$root/runtime/opencode-v2-adapter/v2-http.sh"

# v2-http.sh: authenticated, polled access to the OpenCode 2 HTTP API, tested
# against fake-api.py. The properties pinned here: credentials are validated
# before use, the password never reaches curl's argv, and agent lookups
# tolerate lazy per-location loading but stay bounded.

workdir=$(mktemp -d)
server_pid=''
cleanup() {
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  rm -rf "$workdir"
}
trap cleanup EXIT

fixtures="$workdir/fixtures"
mkdir -p "$fixtures"
printf '%s' '{"location":{"directory":"/w"},"data":{"id":"build","model":{"id":"m","providerID":"p","variant":"v"}}}' \
  >"$fixtures/api_agent_build.json"
printf '%s' '{"location":{"directory":"/w"},"data":{"id":"lazy","model":{"id":"m","providerID":"p"}}}' \
  >"$fixtures/api_agent_lazy.json"
: >"$fixtures/api_agent_lazy.lazy"

server_out="$workdir/server.out"
FAKE_API_LOG="$workdir/requests.log" \
  python3 "$root/tests/fixtures-v2/fake-api.py" 0 "$fixtures" >"$server_out" &
server_pid=$!
for _ in $(seq 1 100); do
  [[ -s "$server_out" ]] && break
  sleep 0.05
done
[[ -s "$server_out" ]] || fail "fake-api.py did not report its port"
IFS=" " read -r port reported_pid <"$server_out"
assert_eq "$server_pid" "$reported_pid"
base="http://127.0.0.1:$port"

# 1. credentials load, with the fallback variable name.
printf 'OPENCODE_PASSWORD=test-only\n' >"$workdir/ok.env"
v2_load_credentials "$workdir/ok.env"
assert_eq test-only "$V2_PASSWORD"
printf 'OTHER=1\nOPENCODE_SERVER_PASSWORD=test-only\n' >"$workdir/fallback.env"
V2_PASSWORD=''
v2_load_credentials "$workdir/fallback.env"
assert_eq test-only "$V2_PASSWORD"

# 2. refusals return 2; the quote case names the file.
printf 'OPENCODE_PASSWORD=bad"pw\n' >"$workdir/quote.env"
rc=0; msg=$(v2_load_credentials "$workdir/quote.env" 2>&1) || rc=$?
assert_eq 2 "$rc"
assert_contains "$msg" "$workdir/quote.env"
printf 'OPENCODE_PASSWORD=bad\\pw\n' >"$workdir/backslash.env"
rc=0; v2_load_credentials "$workdir/backslash.env" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
printf 'OPENCODE_PASSWORD=\n' >"$workdir/empty.env"
rc=0; v2_load_credentials "$workdir/empty.env" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
rc=0; v2_load_credentials "$workdir/missing.env" 2>/dev/null || rc=$?
assert_eq 2 "$rc"

# 3. api_get: 200 with the right password, 1 with the wrong one or a 404.
V2_PASSWORD=test-only
body=$(v2_api_get "$base" "/api/agent/build?directory=/w")
assert_contains "$body" '"providerID":"p"'
V2_PASSWORD=wrong
rc=0; v2_api_get "$base" "/api/agent/build" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
V2_PASSWORD=test-only
rc=0; v2_api_get "$base" "/api/nothing" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"

# 4. agent_get succeeds on the second poll of a lazy fixture.
out=$(v2_agent_get "$base" lazy /w)
assert_contains "$out" '"id":"lazy"'
[[ "$(jq -r '.model.providerID' <<<"$out")" == p ]] || fail "agent_get did not print .data"
assert_eq 2 "$(grep -c '^GET /api/agent/lazy auth=ok ' "$workdir/requests.log")"

# 5. a missing agent is bounded by V2_AGENT_POLL_TIMEOUT.
start=$SECONDS
rc=0; V2_AGENT_POLL_TIMEOUT=1 v2_agent_get "$base" ghost /w >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
(( SECONDS - start <= 3 )) || fail "agent_get exceeded its bound: $((SECONDS - start))s"

# 5b. DIR is percent-encoded; a space and a # survive intact.
: >"$workdir/requests.log"
v2_agent_get "$base" build "/tmp/My Project#x&y" >/dev/null
grep -qxF 'GET /api/agent/build auth=ok query=directory=%2Ftmp%2FMy%20Project%23x%26y' "$workdir/requests.log" \
  || fail "directory was not percent-encoded: $(cat "$workdir/requests.log")"

# 5c. a wrong password fails fast with the status, not after the full bound.
start=$SECONDS
rc=0; msg=$(V2_PASSWORD=wrong V2_AGENT_POLL_TIMEOUT=30 v2_agent_get "$base" build /w 2>&1) || rc=$?
assert_eq 1 "$rc"
assert_contains "$msg" 401
(( SECONDS - start < 3 )) || fail "401 was retried: $((SECONDS - start))s"
V2_PASSWORD=wrong
rc=0; v2_api_get "$base" /api/agent/build >/dev/null 2>"$workdir/err" || rc=$?
msg=$(<"$workdir/err")
V2_PASSWORD=test-only
assert_contains "$msg" "HTTP 401"
assert_eq 401 "$V2_LAST_STATUS"
if [[ "$msg" == *wrong* ]]; then fail "password echoed in a message"; fi

# 5d. injection through V2_PASSWORD or the URL is refused at the point of use.
rc=0; V2_PASSWORD=$'x"\nurl = "http://evil"' v2_api_get "$base" /api/agent/build >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0; V2_PASSWORD=$'x\ny' v2_api_get "$base" /api/agent/build >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0; v2_api_get "$base" $'/api/agent/build\nurl = "http://evil"' >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"

# 5e. dotenv values lose trailing whitespace only.
printf 'OPENCODE_PASSWORD=a b-pw  \t\n' >"$workdir/ws.env"
v2_load_credentials "$workdir/ws.env"
assert_eq 'a b-pw' "$V2_PASSWORD"
V2_PASSWORD=test-only

# 6. the password never reaches curl's argv.
real_curl=$(command -v curl)
stubdir="$workdir/stub"
mkdir -p "$stubdir"
cat >"$stubdir/curl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$workdir/curl-argv"
exec "$real_curl" "\$@"
STUB
chmod +x "$stubdir/curl"
V2_PASSWORD=test-only
PATH="$stubdir:$PATH" v2_api_get "$base" "/api/agent/build" >/dev/null
assert_file "$workdir/curl-argv"
if grep -q 'test-only' "$workdir/curl-argv"; then fail "password appeared in curl argv"; fi
grep -qx -- '-K' "$workdir/curl-argv" || fail "curl was not given -K"

# 7. no server: keeps polling for the 5 s grace, then reports a connection failure.
dead_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
start=$SECONDS
rc=0; msg=$(V2_AGENT_POLL_TIMEOUT=30 v2_agent_get "http://127.0.0.1:$dead_port" build /w 2>&1) || rc=$?
assert_eq 1 "$rc"
assert_contains "$msg" "connection failure"
(( SECONDS - start >= 4 && SECONDS - start <= 10 )) || fail "grace out of range: $((SECONDS - start))s"

printf 'PASS: v2-http-test\n'
