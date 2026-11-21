#!/usr/bin/env bash
# Fake `opencode` for the effective-routing test. Prints recorded 2.x JSONL for
# `opencode --server URL run --agent ROLE ...`; the session is ses_<ROLE>.
# FAKE_OPENCODE_NOTOOL=1 omits the tool_use event; FAKE_OPENCODE_EXIT=N exits N.
# Records argv and the password variable's presence in $FAKE_OPENCODE_LOG.
set -Eeuo pipefail
role=''
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == --agent ]] && role=${args[i + 1]}
done
if [[ -n "${FAKE_OPENCODE_LOG:-}" ]]; then
  {
    printf 'argv:'; printf ' [%s]' "$@"; printf '\n'
    printf 'password_set=%s cwd=%s probe=%s\n' "${OPENCODE_PASSWORD:+yes}" "$PWD" "$(cat probe.txt 2>/dev/null || true)"
  } >>"$FAKE_OPENCODE_LOG"
fi
sid="ses_$role"
printf '{"type":"step_start","sessionID":"%s","part":{"type":"step-start"}}\n' "$sid"
if [[ -z "${FAKE_OPENCODE_NOTOOL:-}" ]]; then
  printf '{"type":"tool_use","sessionID":"%s","part":{"tool":"read","state":{"status":"completed"}}}\n' "$sid"
fi
printf '{"type":"step_finish","sessionID":"%s","part":{"reason":"tool-calls","cost":0.026,"tokens":{"input":1}}}\n' "$sid"
printf '{"type":"text","sessionID":"%s","part":{"text":"done"}}\n' "$sid"
exit "${FAKE_OPENCODE_EXIT:-0}"
