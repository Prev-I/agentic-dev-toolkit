#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

probe_model_variant() {
  local model=$1 variant=$2 output=$3 bin=${OPENCODE_BIN:-opencode}
  local raw start end status classification pricing version provider model_name invocation
  raw=$(mktemp)
  trap 'rm -f "$raw"' RETURN
  start=$(date +%s%3N)
  set +e
  "$bin" run --model "$model" --variant "$variant" --format json "Reply with exactly: CAPABILITY_OK" >"$raw" 2>&1
  status=$?
  set -e
  end=$(date +%s%3N)
  if (( status == 0 )) && grep -q 'CAPABILITY_OK' "$raw"; then classification=USABLE; else classification=AMBIGUOUS_FAILURE; fi
  provider=${model%%/*}
  model_name=${model#*/}
  version=$($bin --version 2>/dev/null || printf unknown)
  invocation="opencode run --model $model --variant $variant --format json Reply with exactly: CAPABILITY_OK"
  pricing=standard
  if [[ "$model_name" == gpt-5.6-sol && "$(date +%F)" < 2026-09-04 ]]; then pricing=promotional; fi
  MODEL="$model_name" PROVIDER="$provider" VARIANT="$variant" STATUS="$status" CLASSIFICATION="$classification" \
    PRICING="$pricing" VERSION="$version" INVOCATION="$invocation" START="$start" END="$end" RAW="$raw" \
    python3 - "$output" <<'PY'
import json
import os
import sys

raw = open(os.environ["RAW"], encoding="utf-8", errors="replace").read()
record = {
    "timestamp": __import__("datetime").datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "provider": os.environ["PROVIDER"],
    "model": os.environ["MODEL"],
    "variant": os.environ["VARIANT"],
    "exact_invocation": os.environ["INVOCATION"],
    "exit_status": int(os.environ["STATUS"]),
    "classification": os.environ["CLASSIFICATION"],
    "pricing_regime": os.environ["PRICING"],
    "wall_clock_ms": int(os.environ["END"]) - int(os.environ["START"]),
    "retry_count": 0,
    "observed_cost": None,
    "normalized_steady_state_cost": None,
    "raw_response": raw,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
  [[ "$classification" == USABLE ]]
}
