#!/usr/bin/env bash
# Shared run helpers for the OpenCode 2 verifiers. Source this file.
#
#   v2_run_isolated COLLECTOR [ARGS...]   run COLLECTOR WORKDIR ARGS... isolated
#   v2_stop_pid PID                       stop the process group PID leads
#   v2_auth_refused                       true when the last request got 401/403
#   v2_call_role URL ROLE WORKDIR         one `opencode run` of ROLE; writes
#                                         WORKDIR/calls/ROLE{.jsonl,.err,.json,.assistant.json}
#   V2_PICK_ASSISTANT                     the jq predicate that picks the used model
#
# v2_run_isolated runs the collector in a subshell that owns its EXIT/INT/TERM
# traps (the caller's traps are never read or modified) and returns the
# subshell's status. The collector receives a fresh temp directory as its first
# argument; that directory and the ones v2_call_role creates are removed on
# exit and on INT/TERM. A watchdog ends the subshell if the caller dies by a
# signal it has no handler for, and stops as soon as the subshell is gone.
# Process groups whose leader pids the collector appends to _V2_PIDS are stopped
# (v2_stop_pid) before the directories are removed. The watchdog's
# command line carries `_vr_watchdog PARENT INNER` (the name is relied on by the
# verifier's test).
set -Eeuo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/v2-http.sh"

_V2_TMPDIRS=()
# Process-group leaders (started with setsid) to stop before the temp dirs go.
_V2_PIDS=()

# v2_stop_pid PID: TERM the process group led by PID (and PID), wait up to 5 s
# for the whole group to be gone, then KILL what is left of it; reaps PID when
# it is this shell's child. The group, not the leader, decides: a leader that
# exits first must not leave its children running.
v2_stop_pid() {
  local pid=$1 state
  [[ -n "$pid" ]] || return 0
  kill -s TERM -- "-$pid" 2>/dev/null || true
  kill -s TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 50); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null || true)
    if [[ -z "$state" || "$state" == Z* ]]; then
      # The leader is gone or a zombie: reap it (a zombie still counts as a
      # group member), then the group alone decides.
      wait "$pid" 2>/dev/null || true
      kill -0 -- "-$pid" 2>/dev/null || break
    fi
    sleep 0.1
  done
  if kill -0 -- "-$pid" 2>/dev/null; then
    kill -s KILL -- "-$pid" 2>/dev/null || true
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill -s KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  # Forget it, so a reused pid is never signalled later.
  local kept=() p
  for p in "${_V2_PIDS[@]}"; do
    [[ "$p" == "$pid" ]] || kept+=("$p")
  done
  _V2_PIDS=("${kept[@]}")
}

_v2_cleanup() {
  local d p
  for p in "${_V2_PIDS[@]}"; do
    v2_stop_pid "$p"
  done
  for d in "${_V2_TMPDIRS[@]}"; do
    [[ -z "$d" ]] || rm -rf "${d:?}"
  done
  _V2_TMPDIRS=()
}

v2_auth_refused() {
  [[ "$V2_LAST_STATUS" == 401 || "$V2_LAST_STATUS" == 403 ]]
}

v2_run_isolated() {
  local rc=0 parent=$BASHPID
  (
    inner=$BASHPID
    watchdog=''
    trap '_v2_cleanup; [[ -z "$watchdog" ]] || kill "$watchdog" 2>/dev/null || true' EXIT
    trap '_v2_cleanup; trap - INT; kill -s INT "$BASHPID"' INT
    trap '_v2_cleanup; trap - TERM; kill -s TERM "$BASHPID"' TERM
    # shellcheck disable=SC2016  # expanded by the watchdog's own shell
    "${BASH:-bash}" -c '
      while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 0.5; done
      if kill -0 "$2" 2>/dev/null; then kill -s TERM "$2" 2>/dev/null; fi
      exit 0' _vr_watchdog "$parent" "$inner" >/dev/null 2>&1 </dev/null &
    watchdog=$!
    work=$(mktemp -d)
    _V2_TMPDIRS+=("$work")
    "$1" "$work" "${@:2}"
  ) || rc=$?
  return "$rc"
}

# The one predicate that picks the assistant message a session used: an object
# (taken from .info when that is an object) with role assistant and a non-empty
# model object. Last match wins.
V2_PICK_ASSISTANT='[(.data // [])[] | select(type == "object")
  | (if (.info | type) == "object" then .info else . end)
  | select(.role == "assistant" and (.model | type) == "object" and (.model | length) > 0)] | last // empty'

# v2_call_role URL ROLE WORKDIR -> writes WORKDIR/calls/ROLE.json
v2_call_role() {
  local url=$1 role=$2 work=$3 probe token out rc=0 sid='' body='' have=0
  probe=$(mktemp -d)
  _V2_TMPDIRS+=("$probe")
  token="probe-$RANDOM-$RANDOM-$$"
  printf '%s\n' "$token" >"$probe/probe.txt"
  out="$work/calls/$role.jsonl"
  (
    cd "$probe"
    OPENCODE_PASSWORD="$V2_PASSWORD" timeout "${V2_CALL_TIMEOUT:-300}" \
      "${OPENCODE_BIN:-opencode}" --server "$url" run --agent "$role" \
      --format json --archived --auto \
      "Read the file probe.txt in the working directory and reply with its exact contents." \
      </dev/null >"$out" 2>"$work/calls/$role.err"
  ) || rc=$?
  rm -rf "$probe"
  sid=$(jq -rs 'map(select(.sessionID != null) | .sessionID) | first // empty' "$out" 2>/dev/null || true)
  if [[ -n "$sid" ]]; then
    for _ in 1 2 3 4 5 6; do
      if body=$(v2_api_get "$url" "/api/session/$sid/message" 2>/dev/null); then
        jq -c "$V2_PICK_ASSISTANT" <<<"$body" >"$work/calls/$role.assistant.json" 2>/dev/null || true
        if [[ -s "$work/calls/$role.assistant.json" ]]; then
          have=1
          break
        fi
      fi
      sleep 0.5
    done
  fi
  jq -n --argjson rc "$rc" --arg sid "$sid" --argjson have "$have" \
    --slurpfile ev <(jq -c . "$out" 2>/dev/null || true) \
    '{exit_code: $rc, session: $sid, messages: ($have == 1),
      tool_called: ([$ev[] | select(.type == "tool_use" and .part.tool == "read")] | length > 0),
      cost: ([$ev[] | select(.type == "step_finish") | .part.cost // 0] | add // 0)}' \
    >"$work/calls/$role.json"
}

