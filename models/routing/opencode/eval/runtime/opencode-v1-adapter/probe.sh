#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

probe_model_variant() {
  local model=$1 variant=$2 output=$3 bin=${OPENCODE_BIN:-opencode}
  local raw start end status classification pricing version provider model_name invocation repository repository_commit environment
  raw=$(mktemp)
  trap 'rm -f "$raw"' RETURN
  start=$(date +%s%3N)
  set +e
  "$bin" run --model "$model" --variant "$variant" --format json "Reply with exactly: CAPABILITY_OK" >"$raw" 2>&1
  status=$?
  set -e
  end=$(date +%s%3N)
  if (( status == 0 )) && python3 - "$raw" <<'PY'
import json
import sys

for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "text" and event.get("part", {}).get("text", "").strip() == "CAPABILITY_OK":
        raise SystemExit(0)
raise SystemExit(1)
PY
  then classification=USABLE; else classification=AMBIGUOUS_FAILURE; fi
  provider=${model%%/*}
  model_name=${model#*/}
  version=$($bin --version 2>/dev/null || printf unknown)
  repository=${PROBE_REPOSITORY:-.}
  repository_commit=$(git -C "$repository" rev-parse HEAD 2>/dev/null || printf unknown)
  environment="$(uname -s) $(uname -r) $(uname -m)"
  invocation="opencode run --model $model --variant $variant --format json Reply with exactly: CAPABILITY_OK"
  pricing=standard
  if [[ "$provider" == github-copilot && "$model_name" == gpt-5.6-sol && "$(date +%F)" < 2026-09-04 ]]; then pricing=promotional; fi
  MODEL="$model_name" PROVIDER="$provider" VARIANT="$variant" STATUS="$status" CLASSIFICATION="$classification" \
    PRICING="$pricing" VERSION="$version" INVOCATION="$invocation" START="$start" END="$end" RAW="$raw" \
    REPOSITORY_COMMIT="$repository_commit" ENVIRONMENT="$environment" \
    python3 - "$output" <<'PY'
import json
import os
import sys

text = None
tokens = None
token_usage = None
observed_cost = None
errors = []
for line in open(os.environ["RAW"], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        if line.strip():
            errors.append(line.strip())
        continue
    part = event.get("part", {})
    if event.get("type") == "text":
        text = part.get("text")
    if event.get("type") == "step_finish":
        token_usage = part.get("tokens")
        tokens = token_usage.get("total") if isinstance(token_usage, dict) else None
        observed_cost = part.get("cost")
record = {
    "timestamp": __import__("datetime").datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "repository_commit": os.environ["REPOSITORY_COMMIT"],
    "environment": os.environ["ENVIRONMENT"],
    "provider": os.environ["PROVIDER"],
    "model": os.environ["MODEL"],
    "variant": os.environ["VARIANT"],
    "exact_invocation": os.environ["INVOCATION"],
    "exit_status": int(os.environ["STATUS"]),
    "classification": os.environ["CLASSIFICATION"],
    "pricing_regime": os.environ["PRICING"],
    "wall_clock_ms": int(os.environ["END"]) - int(os.environ["START"]),
    "retry_count": 0,
    "observed_cost": observed_cost,
    "normalized_steady_state_cost": None,
    "tokens": tokens,
    "token_usage": token_usage,
    "response_text": text,
    "error_text": "\n".join(errors)[:2000] or None,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
  [[ "$classification" == USABLE ]]
}
