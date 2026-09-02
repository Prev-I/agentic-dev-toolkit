#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

record_self_variance() {
  local file=$1
  printf 'fixture_determinism=%s\nscoring_repeatability=%s\ninstrumentation_consistency=%s\ncredit_report_consistency=%s\nself_variance_complete=true\n' "$2" "$3" "$4" "$5" >"$file"
}

freeze_thresholds() {
  local file=$1
  grep -q '^self_variance_complete=true$' "$file" 2>/dev/null || return 1
  printf 'thresholds_frozen=true\n' >>"$file"
}
