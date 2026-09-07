#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
bin=${EVAL_REAL_OPENCODE:-opencode}
if [[ "${1:-}" == --version ]]; then exec "$bin" "$@"; fi
stream=$(mktemp)
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill -TERM -- "-$pid" 2>/dev/null || true; fi
  cat "$stream"
  rm -f "$stream"
}
trap cleanup EXIT
trap 'exit 143' TERM INT
setsid "$bin" "$@" > "$stream" 2>&1 &
pid=$!
stopped=false
while kill -0 "$pid" 2>/dev/null; do
  if jq -Rse '
    [split("\n")[] | fromjson? | select(.type == "step_finish") | .part.cost // 0]
    | (add // 0) * 100 >= 400
  ' "$stream" >/dev/null; then
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
if [[ "$stopped" == true ]]; then
  printf '\nEVAL_BUDGET_STOP: completed-step cost reached 400 credits\n' >&2
  exit 143
fi
exit "$status"
