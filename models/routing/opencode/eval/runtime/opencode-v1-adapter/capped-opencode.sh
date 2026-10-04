#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

bin=${EVAL_REAL_OPENCODE:-opencode}
stop_credits=${EVAL_CALL_STOP_CREDITS:?EVAL_CALL_STOP_CREDITS is required}

if [[ "${1:-}" == --version ]]; then exec "$bin" "$@"; fi

stream=$(mktemp)
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill -TERM -- "-$pid" 2>/dev/null || true; fi
  rm -f "$stream"
}
trap cleanup EXIT
forward_signal() {
  if [[ -n "$pid" ]]; then kill -TERM -- "-$pid" 2>/dev/null || true; fi
}
trap forward_signal TERM INT

setsid "$bin" "$@" >"$stream" 2>&1 &
pid=$!
stopped=false
while kill -0 "$pid" 2>/dev/null; do
  if python3 - "$stream" "$stop_credits" <<'PY'
import json
import sys

path, threshold = sys.argv[1], float(sys.argv[2])
cost = 0.0
for line in open(path, encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "step_finish":
        cost += float(event.get("part", {}).get("cost") or 0)
raise SystemExit(0 if cost * 100 >= threshold else 1)
PY
  then
    stopped=true
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null || true
    break
  fi
  sleep 1
done

status=0
wait "$pid" || status=$?
pid=''
cat "$stream"
if [[ "$stopped" == true ]]; then
  printf '\nEVAL_BUDGET_STOP: completed-step cost reached %s credits\n' "$stop_credits" >&2
  exit 143
fi
exit "$status"
