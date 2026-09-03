#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

emit_run_record() {
  local profile=$1 commit=$2 runtime=$3 runner=$4 provider=$5 model=$6 variant=$7 pricing=$8
  printf '{"routing_profile_id":"%s","routing_profile_commit":"%s","runtime_version":"%s","eval_runner_version":"%s","timestamp":"%s","provider":"%s","model":"%s","variant":"%s","pricing_regime":"%s","observed_cost":null,"normalized_steady_state_cost":null,"credits":null,"tokens":null,"wall_clock_ms":null,"retry_count":0}\n' \
    "$profile" "$commit" "$runtime" "$runner" "$(date --iso-8601=seconds)" "$provider" "$model" "$variant" "$pricing"
}

validate_installed_manifest() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
required = {"profile_id", "source_commit", "installed_at", "opencode_version"}
raise SystemExit(0 if isinstance(data, dict) and required <= data.keys() else 1)
PY
}
