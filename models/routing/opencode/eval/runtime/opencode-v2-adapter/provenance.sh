#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2. Changes: no
# pricing_regime argument (the field is always opencode_reported), a
# profile_digest field, and no Copilot-only credit derivation.
set -Eeuo pipefail
IFS=$'\n\t'

emit_run_record() {
  local profile=$1 digest=$2 commit=$3 runtime=$4 runner=$5 provider=$6 model=$7 variant=$8
  printf '{"routing_profile_id":"%s","profile_digest":"%s","routing_profile_commit":"%s","runtime_version":"%s","eval_runner_version":"%s","timestamp":"%s","provider":"%s","model":"%s","variant":"%s","pricing_regime":"opencode_reported","observed_cost":null,"normalized_steady_state_cost":null,"credits":null,"tokens":null,"wall_clock_ms":null,"retry_count":0}\n' \
    "$profile" "$digest" "$commit" "$runtime" "$runner" "$(date --iso-8601=seconds)" "$provider" "$model" "$variant"
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
