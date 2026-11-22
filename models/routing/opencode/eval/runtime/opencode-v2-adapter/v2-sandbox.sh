#!/usr/bin/env bash
# A sandboxed OpenCode 2 server per screening dispatch. Source this file; it
# sources v2-run.sh (v2_stop_pid, _V2_PIDS) and, through it, v2-http.sh.
#
#   v2_sandbox_create PARENT        print a new sandbox directory under PARENT
#                                   holding home config/opencode data/opencode
#                                   state cache work; 2 if PARENT resolves
#                                   inside, or equal to, a `v2config.py
#                                   real-dirs` entry
#   v2_sandbox_populate SANDBOX CONFIG_JSON CREDENTIALS [OPENCODE_DIR]
#                                   install the config (strict JSON), the
#                                   credentials (data/opencode/auth.json, mode
#                                   600) and OPENCODE_DIR's agents/*.md and
#                                   model-routing.md; a config with
#                                   `instructions` gets the single absolute path
#                                   SANDBOX/config/opencode/model-routing.md, as
#                                   activation writes on a real host
#   v2_sandbox_serve SANDBOX        start "$OPENCODE_BIN" serve in the sandbox
#                                   and check its config layers; 0, or 1 with a
#                                   message
#   v2_sandbox_destroy SANDBOX      stop the server and remove SANDBOX;
#                                   idempotent
#   v2_close_extra_fds              close every descriptor above 2 in the
#                                   calling (sub)shell, so that what it starts
#                                   next inherits none of them (a record's lock
#                                   above all: a server that outlives its
#                                   runner must not keep the record locked)
#
# v2_sandbox_serve runs `( cd SANDBOX/work; exec setsid env -i … ) &`, so `$!`
# is the server's pid (a `cd D && env …` subshell would leave `$!` naming the
# subshell, measured on 2.3.0). The environment is only PATH=/usr/bin:/bin, the
# sandbox's HOME and XDG_*, a fresh random password as OPENCODE_PASSWORD and
# OPENCODE_SERVER_PASSWORD (also left in V2_PASSWORD for v2-http.sh; never
# written to disk), and the OPENCODE_DISABLE_* switches below. The pid is
# appended to _V2_PIDS and written to SANDBOX/pid at once, so a destroy after a
# failure still stops it. GET /api/config is polled (V2_CONFIG_POLL_TIMEOUT,
# default 30 s) until it lists the sandbox's config as its `document` layer;
# that answer, and the one for ?directory=SANDBOX/work (whether 2.x honours the
# parameter is unmeasured, so both must pass), are written to SANDBOX/layers.json
# as {"default": [...], "directory": [...]} and checked with
# v2config.check_layers. SANDBOX/version (GET /api/info) and SANDBOX/url follow.
# A server that exits early is reported on stderr, but the last lines of its
# own log go to file descriptor V2_SERVER_LOG_FD (default 2): a caller that
# keeps stderr in a record points it at the terminal, so no server output (it
# may echo provider settings) is kept. The server inherits no descriptor above
# 2 (v2_close_extra_fds).
#
# Call v2_sandbox_serve in the shell that will destroy the sandbox, not inside
# `$(...)`: the server must be that shell's child for _V2_PIDS and wait to work.
# OPENCODE_BIN defaults to `opencode` on PATH; it is resolved to an absolute
# path before `env -i` drops PATH.
set -Eeuo pipefail

v2_sandbox_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-run.sh disable=SC1091 # path built from the script's own directory at run time
source "$v2_sandbox_root/v2-run.sh"

_sb_err() {
  printf '%s: %s\n' "${FUNCNAME[1]}" "$*" >&2
}

v2_sandbox_create() {
  local parent=${1:?v2_sandbox_create: PARENT required} resolved dir real sb d
  local dirs
  resolved=$(realpath -m -- "$parent") || { _sb_err "cannot resolve $parent"; return 2; }
  dirs=$(python3 -I -B "$v2_sandbox_root/v2config.py" real-dirs) \
    || { _sb_err "cannot list the real OpenCode directories"; return 2; }
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    real=$(realpath -m -- "$dir") || continue
    if [[ "$resolved" == "$real" || "$resolved" == "$real"/* ]]; then
      _sb_err "refusing $parent: it resolves inside the real OpenCode directory $dir"
      return 2
    fi
  done <<<"$dirs"
  mkdir -p -- "$resolved" || { _sb_err "cannot create $parent"; return 1; }
  sb=$(mktemp -d "$resolved/sandbox.XXXXXX") || { _sb_err "cannot create a sandbox under $parent"; return 1; }
  sb=$(cd "$sb" && pwd -P)
  for d in home config/opencode data/opencode state cache work; do
    mkdir -p "$sb/$d" || { _sb_err "cannot create $sb/$d"; rm -rf "${sb:?}"; return 1; }
  done
  printf '%s\n' "$sb"
}

v2_sandbox_populate() {
  local sb=${1:?v2_sandbox_populate: SANDBOX required} config=${2:?CONFIG_JSON required}
  local creds=${3:?CREDENTIALS required} ocdir=${4:-} f
  [[ -d "$sb/config/opencode" && -d "$sb/data/opencode" ]] || { _sb_err "not a sandbox: $sb"; return 1; }
  [[ -f "$creds" ]] || { _sb_err "no such credentials file: $creds"; return 1; }
  if [[ -n "$ocdir" ]]; then
    [[ -f "$ocdir/model-routing.md" ]] || { _sb_err "no model-routing.md in $ocdir"; return 1; }
    mkdir -p "$sb/config/opencode/agents" || { _sb_err "cannot create $sb/config/opencode/agents"; return 1; }
    for f in "$ocdir"/agents/*.md; do
      [[ -f "$f" ]] || continue
      cp -- "$f" "$sb/config/opencode/agents/" || { _sb_err "cannot copy $f"; return 1; }
    done
    cp -- "$ocdir/model-routing.md" "$sb/config/opencode/model-routing.md" \
      || { _sb_err "cannot copy $ocdir/model-routing.md"; return 1; }
  fi
  # umask first: the credentials are never readable by others, not even briefly.
  if ! (umask 077 && cp -- "$creds" "$sb/data/opencode/auth.json") \
     || ! chmod 600 "$sb/data/opencode/auth.json"; then
    _sb_err "cannot install the credentials in $sb"
    return 1
  fi
  python3 -I -B - "$v2_sandbox_root" "$config" "$sb/config/opencode/opencode.json" \
    "$sb/config/opencode/model-routing.md" <<'PY' || { _sb_err "cannot install the config $config"; return 1; }
import json
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config  # noqa: E402

src, out, routing = sys.argv[2:]
try:
    document = v2config.load(src)
except (OSError, ValueError) as error:
    sys.exit("v2_sandbox_populate: %s: %s" % (src, error))
if not isinstance(document, dict):
    sys.exit("v2_sandbox_populate: %s is not a JSON object" % src)
if "instructions" in document:
    document["instructions"] = [routing]
with open(out, "w") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

v2_sandbox_serve() {
  local sb=${1:?v2_sandbox_serve: SANDBOX required} bin=${OPENCODE_BIN:-opencode}
  local timeout=${V2_CONFIG_POLL_TIMEOUT:-30} port pid url rc deadline cfg encoded problems which
  sb=$(cd "$sb" 2>/dev/null && pwd -P) || { _sb_err "no such sandbox: $1"; return 1; }
  cfg="$sb/config/opencode/opencode.json"
  [[ -f "$cfg" ]] || { _sb_err "the sandbox has no config: $cfg"; return 1; }
  if [[ "$bin" == */* ]]; then
    bin=$(realpath -e -- "$bin" 2>/dev/null) || { _sb_err "no such opencode binary: $OPENCODE_BIN"; return 1; }
  else
    bin=$(command -v -- "$bin") || { _sb_err "opencode binary not found on PATH"; return 1; }
  fi
  [[ -x "$bin" && ! -d "$bin" ]] || { _sb_err "not an executable: $bin"; return 1; }
  V2_PASSWORD=$(python3 -I -B -c 'import secrets, string
a = string.ascii_letters + string.digits
print("".join(secrets.choice(a) for _ in range(32)))') && [[ ${#V2_PASSWORD} == 32 ]] \
    || { _sb_err "cannot generate the server password"; return 1; }
  port=$(python3 -I -B -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()') && [[ -n "$port" ]] || { _sb_err "cannot pick a free loopback port"; return 1; }
  [[ "${V2_SERVER_LOG_FD:-2}" =~ ^[0-9]+$ ]] || { _sb_err "V2_SERVER_LOG_FD is not a file descriptor"; return 1; }
  (
    cd "$sb/work"
    # The server holds no descriptor of its caller's: not the log descriptor,
    # not a record's lock.
    v2_close_extra_fds
    exec setsid env -i PATH=/usr/bin:/bin HOME="$sb/home" \
      XDG_CONFIG_HOME="$sb/config" XDG_DATA_HOME="$sb/data" \
      XDG_STATE_HOME="$sb/state" XDG_CACHE_HOME="$sb/cache" \
      OPENCODE_PASSWORD="$V2_PASSWORD" OPENCODE_SERVER_PASSWORD="$V2_PASSWORD" \
      OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_PROJECT_CONFIG=1 \
      OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
      "$bin" serve --hostname 127.0.0.1 --port "$port"
  ) </dev/null >"$sb/server.log" 2>&1 &
  pid=$!
  _V2_PIDS+=("$pid")
  url="http://127.0.0.1:$port"
  if ! printf '%s\n' "$pid" >"$sb/pid" || ! printf '%s\n' "$url" >"$sb/url"; then
    _sb_err "cannot write $sb/pid or $sb/url"
    return 1
  fi
  deadline=$(( SECONDS + timeout ))
  while :; do
    if ! kill -0 "$pid" 2>/dev/null; then
      _sb_err "the sandboxed server exited early; the last lines of its log are on the terminal"
      tail -n 20 "$sb/server.log" >&"${V2_SERVER_LOG_FD:-2}" || true
      return 1
    fi
    rc=0
    v2_api_get "$url" /api/config >"$sb/layers-default.json" 2>/dev/null || rc=$?
    if (( rc == 2 )); then
      _sb_err "the generated password or URL cannot be passed to curl"
      return 1
    fi
    if v2_auth_refused; then
      _sb_err "the sandboxed server refused the generated password (HTTP $V2_LAST_STATUS)"
      return 1
    fi
    if (( rc == 0 )) && jq -e --arg p "$cfg" \
        'type == "array" and any(.[]; type == "object" and .type == "document" and .path == $p)' \
        "$sb/layers-default.json" >/dev/null 2>&1; then
      break
    fi
    if (( SECONDS >= deadline )); then
      _sb_err "no document layer for the sandbox's config in GET /api/config within ${timeout}s (last status ${V2_LAST_STATUS:-none})"
      return 1
    fi
    sleep 0.25
  done
  encoded=$(jq -rn --arg d "$sb/work" '$d|@uri')
  if ! v2_api_get "$url" "/api/config?directory=$encoded" >"$sb/layers-directory.json"; then
    _sb_err "GET /api/config?directory= failed (status ${V2_LAST_STATUS:-none})"
    return 1
  fi
  if ! jq -n --slurpfile d "$sb/layers-default.json" --slurpfile w "$sb/layers-directory.json" \
      '{default: $d[0], directory: $w[0]}' >"$sb/layers.json" 2>/dev/null; then
    _sb_err "the server's config layers are not JSON"
    return 1
  fi
  rm -f "$sb/layers-default.json" "$sb/layers-directory.json"
  for which in default directory; do
    jq ".$which" "$sb/layers.json" >"$sb/layers-check.json" || { _sb_err "cannot read $sb/layers.json"; return 1; }
    rc=0
    problems=$(python3 -I -B "$v2_sandbox_root/v2config.py" layers "$sb/layers-check.json" "$sb" 2>&1) || rc=$?
    if (( rc != 0 )); then
      rm -f "$sb/layers-check.json"
      _sb_err "refusing the server's config layers ($which answer); it did not load only the sandbox:"
      printf '%s\n' "$problems" >&2
      return 1
    fi
  done
  rm -f "$sb/layers-check.json"
  if v2_api_get "$url" /api/info >"$sb/info.json" 2>/dev/null; then
    jq -r '.version // "unknown"' "$sb/info.json" >"$sb/version" 2>/dev/null \
      || printf 'unknown\n' >"$sb/version"
  else
    printf 'unknown\n' >"$sb/version"
  fi
  rm -f "$sb/info.json"
}

v2_close_extra_fds() {
  local f n
  # The glob is read by this shell itself, so /proc/self is this (sub)shell.
  for f in /proc/self/fd/*; do
    n=${f##*/}
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    (( n > 2 )) || continue
    { exec {n}>&-; } 2>/dev/null || true
  done
}

v2_sandbox_destroy() {
  local sb=${1:?v2_sandbox_destroy: SANDBOX required} pid=''
  [[ -e "$sb" ]] || return 0
  [[ ! -f "$sb/pid" ]] || pid=$(<"$sb/pid")
  if [[ -n "$pid" && ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    _sb_err "refusing a malformed pid in $sb/pid; nothing removed"
    return 1
  fi
  [[ -z "$pid" ]] || v2_stop_pid "$pid"
  rm -rf -- "${sb:?}"
}
