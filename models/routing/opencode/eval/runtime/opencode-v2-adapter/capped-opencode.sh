#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2:
#
#   EVAL_REAL_OPENCODE=BIN EVAL_CALL_STOP_CREDITS=N [EVAL_SERVER_PID=P] capped-opencode.sh ARGS...
#
# runs BIN ARGS... in its own process group and watches its JSONL stream. When
# the summed step_finish cost * 100 reaches N credits it stops the client's
# group and then P's group (the per-call server, which would otherwise keep
# the session's model call running), prints the stream, prints
# `EVAL_BUDGET_STOP: completed-step cost reached N credits` to stderr and exits
# 143. On TERM or INT it stops both groups too, prints the stream and exits
# 143. `--version` is passed straight to BIN. The EVAL_* variables are removed
# from the client's environment. Processes are stopped only by recorded pid.
set -Eeuo pipefail
IFS=$'\n\t'

bin=${EVAL_REAL_OPENCODE:-opencode}
stop_credits=${EVAL_CALL_STOP_CREDITS:?EVAL_CALL_STOP_CREDITS is required}
server_pid=${EVAL_SERVER_PID:-}
if [[ -n "$server_pid" && ! "$server_pid" =~ ^[1-9][0-9]*$ ]]; then
  printf 'capped-opencode: EVAL_SERVER_PID is not a pid: %s\n' "$server_pid" >&2
  exit 2
fi

if [[ "${1:-}" == --version ]]; then exec "$bin" "$@"; fi

stream=$(mktemp)
pid=''
signalled=false

stop_group() {
  local leader=$1
  [[ -n "$leader" ]] || return 0
  kill -TERM -- "-$leader" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 -- "-$leader" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -KILL -- "-$leader" 2>/dev/null || true
}

stop_all() {
  stop_group "$pid"
  stop_group "$server_pid"
}

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
  [[ -z "$pid" ]] || stop_all
  rm -f "$stream"
}
trap cleanup EXIT
# shellcheck disable=SC2329 # invoked by the TERM and INT traps
on_signal() {
  signalled=true
  stop_all
}
trap on_signal TERM INT

setsid env -u EVAL_REAL_OPENCODE -u EVAL_CALL_STOP_CREDITS -u EVAL_SERVER_PID "$bin" "$@" >"$stream" 2>&1 &
pid=$!
stopped=false
while kill -0 "$pid" 2>/dev/null && [[ "$signalled" == false ]]; do
  if python3 -I -B - "$stream" "$stop_credits" <<'PY'
import json
import sys

path, threshold = sys.argv[1], float(sys.argv[2])
cost = 0.0
for line in open(path, encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(event, dict) and event.get("type") == "step_finish":
        part = event.get("part")
        value = part.get("cost") if isinstance(part, dict) else None
        if isinstance(value, (int, float)):
            cost += float(value)
raise SystemExit(0 if cost * 100 >= threshold else 1)
PY
  then
    stopped=true
    stop_all
    break
  fi
  sleep 0.5
done

# A trapped signal interrupts wait; wait again until the client is reaped.
while :; do
  status=0
  wait "$pid" || status=$?
  kill -0 "$pid" 2>/dev/null || break
done
[[ "$signalled" == false ]] || stop_all
pid=''
cat "$stream"
if [[ "$stopped" == true ]]; then
  printf '\nEVAL_BUDGET_STOP: completed-step cost reached %s credits\n' "$stop_credits" >&2
  exit 143
fi
[[ "$signalled" == false ]] || exit 143
exit "$status"
