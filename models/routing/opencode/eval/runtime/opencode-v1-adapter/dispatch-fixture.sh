#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
dispatch_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$dispatch_root/classify-capability-failure.sh"
source "$dispatch_root/budget-ledger.sh"

dispatch_fixture() {
  local outdir="" label="" prompt_file="" agent="" model="" variant=""
  local fixture_workspace="" timeout_seconds=900 ledger="" account=evaluation attempt=1
  local bin=${OPENCODE_BIN:-opencode}

  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      --prompt-file) prompt_file=$2; shift 2 ;;
      --agent) agent=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      --workspace) fixture_workspace=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --account) account=$2; shift 2 ;;
      --attempt) attempt=$2; shift 2 ;;
      *) printf 'dispatch_fixture: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" && -n "$label" && -n "$prompt_file" ]] || return 2
  [[ -n "$agent" || ( -n "$model" && -n "$variant" ) ]] || return 2

  mkdir -p "$outdir"
  local raw="$outdir/raw.jsonl" start end status version commit target cwd prompt
  prompt=$(<"$prompt_file")
  version=$("$bin" --version 2>/dev/null || printf unknown)
  commit=$(git rev-parse HEAD 2>/dev/null || printf unknown)
  cwd=${fixture_workspace:-$PWD}
  if [[ -n "$agent" ]]; then target="agent:$agent"; else target="$model"; fi

  start=$(date +%s%3N)
  set +e
  if [[ -n "$agent" ]]; then
    ( cd "$cwd" && timeout --preserve-status "$timeout_seconds" \
        "$bin" run --agent "$agent" --format json "$prompt" ) >"$raw" 2>&1 </dev/null
  else
    ( cd "$cwd" && timeout --preserve-status "$timeout_seconds" \
        "$bin" run --model "$model" --variant "$variant" --format json "$prompt" ) >"$raw" 2>&1 </dev/null
  fi
  status=$?
  set -e
  end=$(date +%s%3N)

  # Extract response text, cost, tokens and any provider error from the raw stream.
  RAW="$raw" python3 - "$outdir/response.txt" "$outdir/.parsed.json" <<'PY'
import json
import os
import sys

texts = []
cost = None
tokens = None
error_message = ""
error_status = None
for line in open(os.environ["RAW"], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    part = event.get("part", {})
    if event.get("type") == "text":
        texts.append(part.get("text", ""))
    elif event.get("type") == "step_finish":
        cost = part.get("cost")
        tokens = part.get("tokens")
    elif event.get("type") == "error":
        data = event.get("error", {}).get("data", {})
        if isinstance(data, dict):
            error_message = str(data.get("message", ""))
            error_status = data.get("statusCode")
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("\n".join(texts))
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({"cost": cost, "tokens": tokens,
               "error_text": error_message or None,
               "status_code": error_status}, handle)
PY

  local cost credits failure_class classification
  cost=$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["cost"]; print("null" if v is None else v)' "$outdir/.parsed.json")
  credits=null
  if [[ -n "$model" ]]; then
    credits=$(ledger_credits_from_cost "${model%%/*}" "$cost")
  else
    credits=$(ledger_credits_from_cost github-copilot "$cost")
  fi
  if [[ -n "$ledger" && "$credits" != null ]]; then
    ledger_append "$ledger" "$account" "$label" "${model%%/*}" "$credits"
  fi

  failure_class=$(classify_capability_failure "$outdir/.parsed.json")
  # timeout(1) with --preserve-status does NOT return 124 on expiry; it forwards
  # the terminated command's own status (128+signal — 143 for the default TERM).
  # Verified empirically in this environment: GNU coreutils 9.4 timeout.
  if (( status == 124 || status == 143 || status == 137 )); then
    classification=TIMEOUT
  elif (( status != 0 )); then
    if [[ "$(capability_stop_class "$failure_class")" == CAPABILITY_REGRESSION ]]; then
      classification=CAPABILITY_REGRESSION
    else
      classification=INVALID_ENVIRONMENT
    fi
  elif [[ ! -s "$outdir/response.txt" ]]; then
    classification=EMPTY_RESPONSE
  else
    classification=OK
  fi

  LABEL="$label" TARGET="$target" VARIANT="${variant:-resolved}" ATTEMPT="$attempt" \
    VERSION="$version" COMMIT="$commit" STATUS="$status" START="$start" END="$end" \
    CREDITS="$credits" CLASSIFICATION="$classification" FAILURE_CLASS="$failure_class" \
    PARSED="$outdir/.parsed.json" TIMEOUT_SECONDS="$timeout_seconds" \
    python3 - "$outdir/dispatch.json" <<'PY'
import datetime
import json
import os
import sys

parsed = json.load(open(os.environ["PARSED"], encoding="utf-8"))
credits = os.environ["CREDITS"]
document = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "label": os.environ["LABEL"],
    "attempt": int(os.environ["ATTEMPT"]),
    "routing_profile_id": "v1-restored-2026-09",
    "routing_profile_commit": os.environ["COMMIT"],
    "runtime_version": os.environ["VERSION"].strip(),
    "eval_runner_version": "phase-r-dispatch-v1",
    "environment": f"{os.uname().sysname} {os.uname().release} {os.uname().machine}",
    "dispatch_target": os.environ["TARGET"],
    "variant": os.environ["VARIANT"],
    "timeout_seconds": int(os.environ["TIMEOUT_SECONDS"]),
    "exit_status": int(os.environ["STATUS"]),
    "classification": os.environ["CLASSIFICATION"],
    "failure_class": os.environ["FAILURE_CLASS"] if os.environ["CLASSIFICATION"] != "OK" else None,
    "provider_error_text": parsed.get("error_text"),
    "provider_status_code": parsed.get("status_code"),
    "observed_cost": parsed.get("cost"),
    "derived_credits": None if credits == "null" else float(credits),
    "normalized_steady_state_cost": None,
    "tokens": parsed.get("tokens"),
    "wall_clock_ms": int(os.environ["END"]) - int(os.environ["START"]),
    "retry_count": 0,
    "raw_evidence": "raw.jsonl",
    "decides_gate_outcome": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  rm -f "$outdir/.parsed.json"
  [[ "$classification" == OK ]]
}

dispatch_classification() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["classification"])' "$1/dispatch.json"
}

dispatch_response_text() {
  cat "$1/response.txt"
}

dispatch_extract_json() {
  python3 - "$1/response.txt" <<'PY'
import json
import sys

text = open(sys.argv[1], encoding="utf-8").read()

# A hand-rolled string/escape scanner desyncs permanently on a single
# unpaired double-quote in surrounding prose (common in real model output:
# an English sentence quoting a term, or an inline malformed-JSON example).
# json.JSONDecoder().raw_decode implements real JSON string/escape/nesting
# semantics via the stdlib parser itself, so it cannot be fooled by prose.
# Try decoding at every "{" position; keep the LAST one that succeeds.
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
