#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

emit_run_record() {
  local profile=$1 commit=$2 runtime=$3 runner=$4 provider=$5 model=$6 variant=$7 pricing=$8
  printf '{"routing_profile_id":"%s","routing_profile_commit":"%s","runtime_version":"%s","eval_runner_version":"%s","timestamp":"%s","provider":"%s","model":"%s","variant":"%s","pricing_regime":"%s","observed_cost":null,"normalized_steady_state_cost":null,"credits":null,"tokens":null,"wall_clock_ms":null,"retry_count":0}\n' \
    "$profile" "$commit" "$runtime" "$runner" "$(date --iso-8601=seconds)" "$provider" "$model" "$variant" "$pricing"
}

validate_installed_manifest() {
  local file=$1 field
  for field in profile_id source_commit installed_at opencode_version; do
    grep -q "\"$field\"" "$file" || return 1
  done
}
