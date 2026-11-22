#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2: one screening call
# against its own sandboxed server. Source this file.
#
#   dispatch_fixture --outdir DIR --label L --prompt-file F (--agent A | --model P/M#V)
#                    --sandbox-parent DIR --config FILE --credentials FILE
#                    [--opencode-dir DIR] [--expect A@P/M#V] [--workspace DIR]
#                    [--workspace-out DIR] [--routing-profile-id ID | --profile-id ID]
#                    [--profile-digest SHA] [--stop-credits N] [--timeout S]
#                    [--ledger FILE] [--account NAME] [--attempt N]
#       0 when the call is OK, 1 otherwise, 2 on a usage error. Writes
#       DIR/raw.jsonl, DIR/response.txt, DIR/assistant.json and DIR/dispatch.json.
#   dispatch_classification DIR, dispatch_response_text DIR, dispatch_extract_json DIR
#       unchanged from V1.
#
# dispatch_fixture runs in its own bash process, so its traps never touch the
# caller's: the sandbox (v2-sandbox.sh) is created under --sandbox-parent,
# populated with --config, --credentials and --opencode-dir, served, and
# destroyed on every exit path, including TERM and INT. --workspace's contents
# are copied into SANDBOX/work, the call's cwd; with --workspace-out,
# SANDBOX/work is copied there before the sandbox goes. --workspace-out must be
# absent or empty (2 otherwise); a failed copy is INVALID_ENVIRONMENT/
# WORKSPACE_OUT_FAILED. server_layers records each layer of both GET
# /api/config answers as {path, type, info_sha256}, never the config itself.
# DIR/setup.err keeps only the adapter's own setup messages: the log of a
# server that exits early goes to this process's stderr (V2_SERVER_LOG_FD).
#
# The client is `timeout --preserve-status S [capped-opencode.sh] OPENCODE_BIN
# --server URL run (--agent A | --model P/M#V) --format json --archived --auto
# PROMPT`, with --stop-credits running it through capped-opencode.sh, which
# also stops the server on a budget stop or a signal. The client's environment
# holds only PATH=/usr/bin:/bin, the sandbox's HOME, its own XDG_* under
# SANDBOX/client and OPENCODE_PASSWORD (plus the capped wrapper's EVAL_*, which
# the wrapper removes before the client starts, and its stream file,
# SANDBOX/client/stream.jsonl); the password is never in an
# argv. For --agent, GET /api/agent/A is polled first (agents load lazily), and
# when --expect is absent the expected `A@P/M#V` is the agent's resolved model.
# For --model without --expect, any agent passes the routing check, but the
# model must be exactly P/M#V.
#
# After the call, the session's assistant messages (V2_PICK_ASSISTANT) go to
# DIR/assistant.json and routing_observed is v2config.assistant_uses of them.
# Classification, first match wins: BUDGET_STOP, TIMEOUT (exit 124, 137, 143),
# CAPABILITY_REGRESSION or INVALID_ENVIRONMENT (non-zero exit),
# ROUTING_MISMATCH (routing_observed is not exactly [expected]),
# EMPTY_RESPONSE, OK. A sandbox that cannot be created, populated, served or
# filled is INVALID_ENVIRONMENT/SANDBOX_REFUSED; an agent that does not resolve
# is INVALID_ENVIRONMENT/AGENT_UNRESOLVED.
#
# Credits are reported cost * 100. A stream with no step_start costs 0; one
# with a step_start and no reported cost is unknown (derived_credits null,
# cost_known false). A known non-zero cost of a started call is appended to
# --ledger under --account even when the call failed. unfinished_steps is the
# number of step_start events beyond the step_finish events (a call cut off
# mid-step, whose last step's cost was never reported); cost_complete is false
# when it is above 0, and the cost of the finished steps is still ledgered.
set -Eeuo pipefail
IFS=$'\n\t'
dispatch_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/classify-capability-failure.sh disable=SC1091 # path built from the script's own directory at run time
source "$dispatch_root/classify-capability-failure.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/budget-ledger.sh disable=SC1091 # path built from the script's own directory at run time
source "$dispatch_root/budget-ledger.sh"

dispatch_fixture() {
  "${BASH:-bash}" "$dispatch_root/dispatch-fixture.sh" __dispatch "$@"
}

_df_err() {
  printf 'dispatch_fixture: %s\n' "$*" >&2
}

_df_sandbox=''
_df_client=''

_df_cleanup() {
  if [[ -n "$_df_client" ]]; then
    v2_stop_pid "$_df_client"
    _df_client=''
  fi
  if [[ -n "$_df_sandbox" ]]; then
    v2_sandbox_destroy "$_df_sandbox" || true
    _df_sandbox=''
  fi
}

_df_signal() {
  trap - TERM INT
  _df_cleanup
  exit "$1"
}

_dispatch_main() {
  local outdir="" label="" prompt_file="" agent="" model="" fixture_workspace=""
  local timeout_seconds=900 ledger="" account=evaluation attempt=1
  local routing_profile_id="" routing_profile_id_set=false parent="" config="" creds=""
  local ocdir="" expect="" profile_digest="" stop_credits="" workspace_out=""
  local bin=${OPENCODE_BIN:-opencode}

  while (( $# )); do
    (( $# >= 2 )) || { _df_err "option $1 needs a value"; return 2; }
    case "$1" in
      --outdir) outdir=$2 ;;
      --label) label=$2 ;;
      --prompt-file) prompt_file=$2 ;;
      --agent) agent=$2 ;;
      --model) model=$2 ;;
      --workspace) fixture_workspace=$2 ;;
      --workspace-out) workspace_out=$2 ;;
      --routing-profile-id|--profile-id) routing_profile_id=$2; routing_profile_id_set=true ;;
      --profile-digest) profile_digest=$2 ;;
      --timeout) timeout_seconds=$2 ;;
      --ledger) ledger=$2 ;;
      --account) account=$2 ;;
      --attempt) attempt=$2 ;;
      --sandbox-parent) parent=$2 ;;
      --config) config=$2 ;;
      --credentials) creds=$2 ;;
      --opencode-dir) ocdir=$2 ;;
      --expect) expect=$2 ;;
      --stop-credits) stop_credits=$2 ;;
      *) _df_err "unknown option $1"; return 2 ;;
    esac
    shift 2
  done
  [[ -n "$outdir" && -n "$label" && -n "$prompt_file" ]] \
    || { _df_err "--outdir, --label and --prompt-file are required"; return 2; }
  [[ -n "$parent" && -n "$config" && -n "$creds" ]] \
    || { _df_err "--sandbox-parent, --config and --credentials are required"; return 2; }
  if [[ -n "$agent" && -n "$model" ]] || [[ -z "$agent" && -z "$model" ]]; then
    _df_err "exactly one of --agent and --model is required"; return 2
  fi
  if [[ -n "$model" && ! "$model" =~ ^[^/#]+/[^#]+#[^#]+$ ]]; then
    _df_err "--model takes provider/model#variant, not $model"; return 2
  fi
  [[ "$routing_profile_id_set" == false || -n "$routing_profile_id" ]] \
    || { _df_err "--profile-id is empty"; return 2; }
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ && "$attempt" =~ ^[0-9]+$ ]] \
    || { _df_err "--timeout and --attempt take integers"; return 2; }
  [[ -z "$stop_credits" || "$stop_credits" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || { _df_err "--stop-credits takes a number"; return 2; }
  [[ -f "$prompt_file" && -f "$config" && -f "$creds" ]] \
    || { _df_err "no such prompt, config or credentials file"; return 2; }
  [[ -z "$fixture_workspace" || -d "$fixture_workspace" ]] \
    || { _df_err "no such workspace: $fixture_workspace"; return 2; }
  if [[ "$bin" == */* ]]; then
    bin=$(realpath -e -- "$bin" 2>/dev/null) || { _df_err "no such opencode binary: $OPENCODE_BIN"; return 2; }
  else
    bin=$(command -v -- "$bin") || { _df_err "opencode binary not found on PATH"; return 2; }
  fi

  mkdir -p "$outdir"
  outdir=$(cd "$outdir" && pwd -P)
  if [[ -n "$workspace_out" ]]; then
    workspace_out=$(realpath -m -- "$workspace_out")
    if [[ -e "$workspace_out" && ! -d "$workspace_out" ]] \
        || { [[ -d "$workspace_out" ]] && [[ -n "$(ls -A -- "$workspace_out")" ]]; }; then
      _df_err "--workspace-out must be absent or an empty directory: $workspace_out"
      return 2
    fi
  fi
  local raw="$outdir/raw.jsonl" setup_err="$outdir/setup.err"
  local prompt commit target status='' start end version=unknown url='' agent_data=''
  local setup_failure='' classification failure_class sb logfd
  prompt=$(<"$prompt_file")
  commit=$(git -C "$dispatch_root" rev-parse HEAD 2>/dev/null || printf unknown)
  [[ -n "$routing_profile_id" ]] || routing_profile_id=direct-model-evaluation
  if [[ -n "$agent" ]]; then target="agent:$agent"; else target="$model"; fi
  : >"$raw"
  : >"$setup_err"
  rm -f "$outdir/assistant.json" "$outdir/response.txt" "$outdir/dispatch.json"

  trap _df_cleanup EXIT
  trap '_df_signal 143' TERM
  trap '_df_signal 130' INT

  # 1-2. Sandbox, server, workspace. Not in $(...) for serve: the server must
  # be this shell's child.
  if ! sb=$(v2_sandbox_create "$parent" 2>>"$setup_err"); then
    setup_failure=SANDBOX_REFUSED
  else
    _df_sandbox=$sb
    # The workspace is in place before the server starts, so the recorded
    # directory-layer answer describes the tree the call runs in.
    if ! v2_sandbox_populate "$sb" "$config" "$creds" ${ocdir:+"$ocdir"} 2>>"$setup_err" \
        || { [[ -n "$fixture_workspace" ]] && ! cp -a -- "$fixture_workspace/." "$sb/work/" 2>>"$setup_err"; } \
        || ! mkdir -p "$sb/client/config" "$sb/client/data" "$sb/client/state" "$sb/client/cache" 2>>"$setup_err" \
        || ! { exec {logfd}>&2; V2_SERVER_LOG_FD=$logfd v2_sandbox_serve "$sb" 2>>"$setup_err"; }; then
      setup_failure=SANDBOX_REFUSED
    fi
    [[ -z "${logfd:-}" ]] || exec {logfd}>&-
  fi
  if [[ -z "$setup_failure" ]]; then
    url=$(<"$sb/url")
    version=$(<"$sb/version")
    # 3. Lazy agent load, and the expected routing when not given.
    if [[ -n "$agent" ]]; then
      if ! agent_data=$(v2_agent_get "$url" "$agent" "$sb/work" 2>>"$setup_err"); then
        setup_failure=AGENT_UNRESOLVED
      elif [[ -z "$expect" ]]; then
        expect=$(python3 -I -B -c 'import json, sys
m = json.loads(sys.argv[2]).get("model") or {}
print("%s@%s/%s#%s" % (sys.argv[1], m.get("providerID"), m.get("id"), m.get("variant")))' "$agent" "$agent_data")
      fi
    fi
  fi
  if [[ -n "$setup_failure" ]]; then
    _df_err "the sandbox could not be prepared ($setup_failure):"
    cat "$setup_err" >&2
  fi

  # 4. The call.
  start=$(date +%s%3N)
  if [[ -z "$setup_failure" ]]; then
    local cmd=(timeout --preserve-status "$timeout_seconds")
    if [[ -n "$stop_credits" ]]; then cmd+=("$dispatch_root/capped-opencode.sh"); else cmd+=("$bin"); fi
    cmd+=(--server "$url" run)
    if [[ -n "$agent" ]]; then cmd+=(--agent "$agent"); else cmd+=(--model "$model"); fi
    cmd+=(--format json --archived --auto "$prompt")
    (
      cd "$sb/work" || exit 1
      v2_close_extra_fds
      # Only the allowlist reaches the client: every inherited variable is
      # unexported, then the few it needs are exported (never put in argv).
      # shellcheck disable=SC2163 # the variable named by $name is unexported
      for name in $(compgen -e); do export -n "$name" 2>/dev/null || true; done
      export PATH=/usr/bin:/bin HOME="$sb/home" \
        XDG_CONFIG_HOME="$sb/client/config" XDG_DATA_HOME="$sb/client/data" \
        XDG_STATE_HOME="$sb/client/state" XDG_CACHE_HOME="$sb/client/cache" \
        OPENCODE_PASSWORD="$V2_PASSWORD"
      if [[ -n "$stop_credits" ]]; then
        EVAL_SERVER_PID=$(<"$sb/pid") || exit 1
        export EVAL_REAL_OPENCODE="$bin" EVAL_CALL_STOP_CREDITS="$stop_credits" EVAL_SERVER_PID \
          EVAL_STREAM_FILE="$sb/client/stream.jsonl"
      fi
      exec "${cmd[@]}"
    ) </dev/null >"$raw" 2>&1 &
    _df_client=$!
    # A trapped signal interrupts wait; wait again until the client is reaped.
    while :; do
      status=0
      wait "$_df_client" || status=$?
      kill -0 "$_df_client" 2>/dev/null || break
    done
    _df_client=''
  fi
  end=$(date +%s%3N)

  # 5. The stream, then the session's assistant messages.
  python3 -I -B - "$raw" "$outdir/response.txt" "$outdir/.parsed.json" <<'PY'
import json
import sys

raw, response, parsed = sys.argv[1:]
texts = []
cost = None
tokens = None
error_message = ""
error_status = None
session = None
started = False
starts = finishes = 0
for line in open(raw, encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(event, dict):
        continue
    if session is None and isinstance(event.get("sessionID"), str):
        session = event["sessionID"]
    part = event.get("part") if isinstance(event.get("part"), dict) else {}
    kind = event.get("type")
    if kind == "text":
        texts.append(str(part.get("text", "")))
    elif kind == "step_start":
        started = True
        starts += 1
    elif kind == "step_finish":
        finishes += 1
        # cost is per step and summed; tokens are a running snapshot, so the
        # last one is the total.
        step_cost = part.get("cost")
        if isinstance(step_cost, (int, float)) and not isinstance(step_cost, bool):
            cost = (cost or 0) + step_cost
        tokens = part.get("tokens")
    elif kind == "error":
        error = event.get("error") if isinstance(event.get("error"), dict) else {}
        data = error.get("data", {})
        if isinstance(data, dict):
            error_message = str(data.get("message", ""))
            error_status = data.get("statusCode")
with open(response, "w", encoding="utf-8") as handle:
    handle.write("\n".join(texts))
with open(parsed, "w", encoding="utf-8") as handle:
    json.dump({"cost": cost, "tokens": tokens, "error_text": error_message or None,
               "status_code": error_status, "session": session, "step_started": started,
               "cost_known": (not started) or cost is not None,
               "unfinished_steps": max(starts - finishes, 0)}, handle)
PY

  local sid body tries=1 i
  printf '[]\n' >"$outdir/assistant.json"
  sid=$(jq -r '.session // empty' "$outdir/.parsed.json")
  if [[ -z "$setup_failure" && "$sid" =~ ^[A-Za-z0-9_-]+$ ]]; then
    [[ "$status" != 0 ]] || tries=6
    for ((i = 1; i <= tries; i++)); do
      if body=$(v2_api_get "$url" "/api/session/$sid/message" 2>/dev/null) \
          && jq -c "$V2_PICK_ASSISTANT" <<<"$body" >"$outdir/.assistant.json" 2>/dev/null \
          && [[ -s "$outdir/.assistant.json" ]]; then
        mv "$outdir/.assistant.json" "$outdir/assistant.json"
        break
      fi
      rm -f "$outdir/.assistant.json"
      (( i == tries )) || sleep 0.5
    done
  fi
  local routing
  routing=$(python3 -I -B - "$dispatch_root" "$outdir/assistant.json" "$expect" "$model" <<'PY'
import json
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config  # noqa: E402

path, expect, model = sys.argv[2:]
try:
    entries = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    entries = []
observed = v2config.assistant_uses(entries)
if expect:
    expected, match = expect, observed == [expect]
else:
    expected = "*@" + model
    match = len(observed) == 1 and observed[0].endswith("@" + model)
print(json.dumps({"expected": expected, "observed": observed, "match": match}))
PY
)

  # 6. The workspace, for the build role's patch; 7. the sandbox goes.
  local out_failed=false
  if [[ -n "$workspace_out" && -z "$setup_failure" ]]; then
    if ! mkdir -p "$workspace_out" || ! cp -a -- "$sb/work/." "$workspace_out/"; then
      _df_err "cannot copy the workspace to $workspace_out"
      out_failed=true
    fi
  fi
  if [[ -n "$_df_sandbox" && -f "$_df_sandbox/layers.json" ]]; then
    # Each layer's `info` is the effective config, provider settings included,
    # so the record keeps only its sha256 (canonical JSON; null for null).
    python3 -I -B - "$_df_sandbox/layers.json" "$outdir/.layers.json" <<'PY' || rm -f "$outdir/.layers.json"
import hashlib
import json
import sys

source, out = sys.argv[1:]
answers = json.load(open(source, encoding="utf-8"))

def digest(info):
    if info is None:
        return None
    canonical = json.dumps(info, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

def layers(answer):
    if not isinstance(answer, list):
        return None
    return [{"path": layer.get("path"), "type": layer.get("type"),
             "info_sha256": digest(layer.get("info"))}
            for layer in answer if isinstance(layer, dict)]

with open(out, "w", encoding="utf-8") as handle:
    json.dump({which: layers(answers.get(which)) for which in ("default", "directory")}, handle)
PY
  fi
  if [[ -n "$_df_sandbox" ]]; then
    v2_sandbox_destroy "$_df_sandbox" || true
    _df_sandbox=''
  fi

  # Credits and classification.
  local cost cost_known started credits=null provider
  cost=$(jq -r '.cost // "null"' "$outdir/.parsed.json")
  cost_known=$(jq -r '.cost_known' "$outdir/.parsed.json")
  started=$(jq -r '.step_started' "$outdir/.parsed.json")
  if [[ "$cost_known" == true ]]; then
    if [[ "$cost" == null ]]; then credits=0; else credits=$(ledger_credits_from_cost "$cost"); fi
  fi
  if [[ -n "$model" ]]; then provider=${model%%/*}; else provider=${expect#*@}; provider=${provider%%/*}; fi
  if [[ -n "$ledger" && "$started" == true && "$credits" != null ]]; then
    ledger_append "$ledger" "$account" "$label" "$provider" "$credits"
  fi

  if [[ -n "$setup_failure" ]]; then
    classification=INVALID_ENVIRONMENT
    failure_class=$setup_failure
  else
    failure_class=$(classify_capability_failure "$outdir/.parsed.json")
    # timeout --preserve-status forwards the stopped command's own status
    # (128 + signal), so 143 and 137 are timeouts too.
    # Anchored: the wrapper prints the marker on a line of its own, and a JSON
    # event quoting it (model text) must not count.
    if grep -q '^EVAL_BUDGET_STOP:' "$raw"; then
      classification=BUDGET_STOP
    elif (( status == 124 || status == 143 || status == 137 )); then
      classification=TIMEOUT
    elif (( status != 0 )); then
      if [[ "$(capability_stop_class "$failure_class")" == CAPABILITY_REGRESSION ]]; then
        classification=CAPABILITY_REGRESSION
      else
        classification=INVALID_ENVIRONMENT
      fi
    elif [[ "$(jq -r .match <<<"$routing")" != true ]]; then
      classification=ROUTING_MISMATCH
    elif [[ ! -s "$outdir/response.txt" ]]; then
      classification=EMPTY_RESPONSE
    else
      classification=OK
    fi
  fi
  if [[ "$out_failed" == true ]]; then
    classification=INVALID_ENVIRONMENT
    failure_class=WORKSPACE_OUT_FAILED
  fi

  LABEL="$label" TARGET="$target" ATTEMPT="$attempt" ROUTING_PROFILE_ID="$routing_profile_id" \
    PROFILE_DIGEST="$profile_digest" VERSION="$version" COMMIT="$commit" STATUS="$status" \
    START="$start" END="$end" CREDITS="$credits" CLASSIFICATION="$classification" \
    FAILURE_CLASS="$failure_class" PARSED="$outdir/.parsed.json" LAYERS="$outdir/.layers.json" \
    ROUTING="$routing" TIMEOUT_SECONDS="$timeout_seconds" \
    python3 -I -B - "$outdir/dispatch.json" <<'PY'
import datetime
import json
import os
import sys

env = os.environ
parsed = json.load(open(env["PARSED"], encoding="utf-8"))
routing = json.loads(env["ROUTING"])
try:
    layers = json.load(open(env["LAYERS"], encoding="utf-8"))
except (OSError, ValueError):
    layers = None
credits = env["CREDITS"]
expected = routing["expected"]
variant = expected.rsplit("#", 1)[1] if "#" in expected else "resolved"
document = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "label": env["LABEL"],
    "attempt": int(env["ATTEMPT"]),
    "routing_profile_id": env["ROUTING_PROFILE_ID"],
    "profile_digest": env["PROFILE_DIGEST"] or None,
    "routing_profile_commit": env["COMMIT"],
    "runtime_version": env["VERSION"].strip(),
    "eval_runner_version": "oc2-dispatch-v1",
    "environment": f"{os.uname().sysname} {os.uname().release} {os.uname().machine}",
    "dispatch_target": env["TARGET"],
    "variant": variant,
    "routing_expected": expected,
    "routing_observed": routing["observed"],
    "server_layers": layers,
    "timeout_seconds": int(env["TIMEOUT_SECONDS"]),
    "exit_status": int(env["STATUS"]) if env["STATUS"] else None,
    "classification": env["CLASSIFICATION"],
    "failure_class": env["FAILURE_CLASS"] if env["CLASSIFICATION"] != "OK" else None,
    "provider_error_text": parsed.get("error_text"),
    "provider_status_code": parsed.get("status_code"),
    "observed_cost": parsed.get("cost"),
    "derived_credits": None if credits == "null" else float(credits),
    "cost_known": bool(parsed.get("cost_known")),
    "unfinished_steps": parsed.get("unfinished_steps", 0),
    "cost_complete": parsed.get("unfinished_steps", 0) == 0,
    "normalized_steady_state_cost": None,
    "tokens": parsed.get("tokens"),
    "wall_clock_ms": int(env["END"]) - int(env["START"]),
    "retry_count": 0,
    "raw_evidence": "raw.jsonl",
    "decides_gate_outcome": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  rm -f "$outdir/.parsed.json" "$outdir/.layers.json"
  [[ -s "$setup_err" ]] || rm -f "$setup_err"
  [[ "$classification" == OK ]]
}

dispatch_classification() {
  python3 -I -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["classification"])' "$1/dispatch.json"
}

dispatch_response_text() {
  cat "$1/response.txt"
}

dispatch_extract_json() {
  python3 -I -B - "$1/response.txt" <<'PY'
import json
import sys

text = open(sys.argv[1], encoding="utf-8").read()

# Decode at every "{" with the stdlib parser, which cannot be desynced by an
# unpaired quote in surrounding prose; keep the LAST object that decodes.
decoder = json.JSONDecoder()
best = None
idx = 0
while True:
    brace = text.find("{", idx)
    if brace == -1:
        break
    try:
        obj, end = decoder.raw_decode(text, brace)
        best = obj
        idx = end
    except json.JSONDecodeError:
        idx = brace + 1

if best is None:
    raise SystemExit("no parseable JSON object in response")
json.dump(best, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" != __dispatch ]]; then
    printf 'usage: source %s, then call dispatch_fixture\n' "$0" >&2
    exit 2
  fi
  shift
  # shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-sandbox.sh disable=SC1091 # path built from the script's own directory at run time
  source "$dispatch_root/v2-sandbox.sh"
  _dispatch_main "$@"
fi
