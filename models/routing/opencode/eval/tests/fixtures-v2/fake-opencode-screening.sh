#!/usr/bin/env bash
# Fake `opencode` for the screening sandbox and dispatch tests. Two commands:
#
#   serve --hostname H --port P
#       like fake-opencode-serve.sh, it answers GET /api/config like a 2.x
#       server, then execs fake-api.py on port P (so the server's pid is this
#       script's, and fake-api.py's). Every agent in the config's `agents` gets
#       a lazy GET /api/agent/<name> fixture with the row's model as
#       {id, providerID, variant}.
#   --server URL run (--agent A | --model P/M#V) --format json --archived --auto PROMPT
#       emits 2.x JSONL for the scenario keyed by A (or P/M#V), and writes the
#       session's messages into the running fake server's fixtures.
#
# Both start under `env -i`, so settings arrive only through a wrapper that
# exports FAKE_SCREEN_STATE=<dir> and execs this script:
#   FAKE_SCREEN_STATE/log          receives, per serve:
#                                    "serve pid=<pid> cwd=<cwd> home=<home>"
#                                    "serve-env <sorted exported NAMES, comma-separated>"
#                                  and per run:
#                                    "run pid=<pid> cwd=<cwd> xdg_config=<XDG_CONFIG_HOME>"
#                                    "run-argv [arg] [arg] ..."
#                                    "run-env <sorted exported NAMES>"
#                                  Names only: values (the password) are never logged.
#   FAKE_SCREEN_STATE/models.json  served as GET /api/model, when present
#   FAKE_SCREEN_STATE/mode         `leak` adds a layer /etc/opencode-outside
#   FAKE_SCREEN_STATE/fixtures     written by serve: the server's fixture directory
#   FAKE_SCREEN_STATE/scenario.json  read by run: {KEY: {text, cost_per_step,
#                                  steps, step_sleep, exit, error_message,
#                                  observed_model: {providerID, id, variant},
#                                  write_file: {path, content}}}. Defaults:
#                                  text "", cost_per_step 0, steps 1,
#                                  step_sleep 0, exit 0; cost_per_step null
#                                  omits every step_finish (unknown cost);
#                                  observed_model defaults to the agent's
#                                  fixture model, or to the --model value.
# Serve's layers are the config document ($XDG_CONFIG_HOME/opencode/opencode.json)
# and the working directory; the first GET /api/config answers 404, as a server
# still loading would. Fixtures are written under $XDG_CACHE_HOME, inside the
# sandbox. The API password is the OPENCODE_PASSWORD the fake was given. Run's
# sessions are ses_1, ses_2, ... (a counter in FAKE_SCREEN_STATE).
set -Eeuo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state=${FAKE_SCREEN_STATE:?FAKE_SCREEN_STATE is not set}

env_names() {
  compgen -e | sort | paste -sd, -
}

serve() {
  local port='' mode=''
  while (( $# )); do
    case "$1" in
      --port) port=${2:?}; shift 2 ;;
      --hostname) shift 2 ;;
      *) printf 'fake-opencode-screening: unknown flag %s\n' "$1" >&2; exit 2 ;;
    esac
  done
  [[ ! -f "$state/mode" ]] || mode=$(<"$state/mode")
  printf 'serve pid=%s cwd=%s home=%s\n' "$$" "$PWD" "$HOME" >>"$state/log"
  printf 'serve-env %s\n' "$(env_names)" >>"$state/log"

  local fixtures="${XDG_CACHE_HOME:?}/fake-api"
  mkdir -p "$fixtures"
  printf '%s\n' "$fixtures" >"$state/fixtures"
  python3 -B - "${XDG_CONFIG_HOME:?}/opencode/opencode.json" "$fixtures" "$PWD" "$mode" <<'PY'
import json
import os
import sys

cfg_path, fixtures, cwd, mode = sys.argv[1:]
with open(cfg_path) as f:
    cfg = json.load(f)
layers = [{"path": cfg_path, "type": "document", "info": cfg},
          {"path": cwd, "type": "directory", "info": None}]
if mode == "leak":
    layers.append({"path": "/etc/opencode-outside", "type": "directory", "info": None})
with open(os.path.join(fixtures, "api_config.json"), "w") as f:
    json.dump(layers, f)
open(os.path.join(fixtures, "api_config.lazy"), "w").close()
with open(os.path.join(fixtures, "api_info.json"), "w") as f:
    json.dump({"version": "2.3.0-fake"}, f)
for name, row in (cfg.get("agents") or {}).items():
    model = row.get("model") if isinstance(row, dict) else None
    if not isinstance(model, dict):
        continue
    data = {"id": name, "name": name, "mode": row.get("mode"),
            "model": {"id": model.get("model"), "providerID": model.get("providerID"),
                      "variant": model.get("variant")}}
    stem = os.path.join(fixtures, "api_agent_" + name)
    with open(stem + ".json", "w") as f:
        json.dump({"location": {"directory": cwd}, "data": data}, f)
    open(stem + ".lazy", "w").close()
PY
  if [[ -f "$state/models.json" ]]; then
    cp "$state/models.json" "$fixtures/api_model.json"
  fi
  exec env FAKE_API_PASSWORD="${OPENCODE_PASSWORD:?}" python3 -B "$here/fake-api.py" "${port:?}" "$fixtures"
}

run() {
  local agent='' model='' key n sid fixtures i steps cost sleep_s text code message
  local observed write_path write_content
  {
    printf 'run pid=%s cwd=%s xdg_config=%s\n' "$$" "$PWD" "${XDG_CONFIG_HOME:-}"
    printf 'run-argv'; printf ' [%s]' "$@"; printf '\n'
    printf 'run-env %s\n' "$(env_names)"
  } >>"$state/log"
  [[ "${1:-}" == --server && "${3:-}" == run ]] \
    || { printf 'fake-opencode-screening: expected --server URL run ...\n' >&2; exit 2; }
  shift 3
  while (( $# )); do
    case "$1" in
      --agent) agent=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --format) shift 2 ;;
      --archived|--auto) shift ;;
      -*) printf 'fake-opencode-screening: unknown run flag %s\n' "$1" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  key=${agent:-$model}
  [[ -n "$key" ]] || { printf 'fake-opencode-screening: run needs --agent or --model\n' >&2; exit 2; }
  fixtures=$(<"$state/fixtures")
  n=$(( $(cat "$state/session-counter" 2>/dev/null || printf 0) + 1 ))
  printf '%s\n' "$n" >"$state/session-counter"
  sid="ses_$n"

  local sc='{}'
  [[ ! -f "$state/scenario.json" ]] || sc=$(jq -c --arg k "$key" '.[$k] // {}' "$state/scenario.json")
  steps=$(jq -r '.steps // 1' <<<"$sc")
  cost=$(jq -r 'if has("cost_per_step") then .cost_per_step else 0 end' <<<"$sc")
  sleep_s=$(jq -r '.step_sleep // 0' <<<"$sc")
  text=$(jq -r '.text // ""' <<<"$sc")
  code=$(jq -r '.exit // 0' <<<"$sc")
  message=$(jq -r '.error_message // ""' <<<"$sc")
  write_path=$(jq -r '.write_file.path // ""' <<<"$sc")
  write_content=$(jq -r '.write_file.content // ""' <<<"$sc")
  observed=$(jq -c '.observed_model // empty' <<<"$sc")
  if [[ -z "$observed" && -n "$agent" && -f "$fixtures/api_agent_$agent.json" ]]; then
    observed=$(jq -c '.data.model' "$fixtures/api_agent_$agent.json")
  elif [[ -z "$observed" && -n "$model" ]]; then
    observed=$(jq -cn --arg m "$model" \
      '{providerID: ($m | split("/")[0]), id: ($m | split("/")[1:] | join("/") | split("#")[0]), variant: ($m | split("#")[1])}')
  fi

  jq -n --arg a "${agent:-build}" --argjson m "${observed:-null}" \
    '{data: ([{id: "msg_u0", type: "user", text: "prompt", files: [], time: {}}]
             + (if $m == null then [] else [{id: "msg_a1", type: "assistant", agent: $a, model: $m,
                 finish: "stop", time: {}, tokens: {}, content: []}] end))}' \
    >"$fixtures/api_session_${sid}_message.json"

  if [[ "$code" != 0 ]]; then
    jq -cn --arg s "$sid" --arg m "$message" '{type: "error", sessionID: $s, error: {data: {message: $m}}}'
    exit "$code"
  fi
  for ((i = 1; i <= steps; i++)); do
    printf '{"type":"step_start","sessionID":"%s","part":{"type":"step-start"}}\n' "$sid"
    if (( i == 1 )); then
      printf '{"type":"tool_use","sessionID":"%s","part":{"tool":"read","state":{"status":"completed"}}}\n' "$sid"
    fi
    sleep "$sleep_s"
    if [[ "$cost" != null ]]; then
      printf '{"type":"step_finish","sessionID":"%s","part":{"reason":"stop","cost":%s,"tokens":{"total":%s}}}\n' \
        "$sid" "$cost" "$(( i * 10 ))"
    fi
  done
  if [[ -n "$write_path" ]]; then
    mkdir -p "$(dirname "$write_path")"
    printf '%s' "$write_content" >"$write_path"
  fi
  jq -cn --arg s "$sid" --arg t "$text" '{type: "text", sessionID: $s, part: {text: $t}}'
}

case "${1:-}" in
  serve) shift; serve "$@" ;;
  --server) run "$@" ;;
  *) printf 'fake-opencode-screening: only "serve" and "--server URL run" are supported\n' >&2; exit 2 ;;
esac
