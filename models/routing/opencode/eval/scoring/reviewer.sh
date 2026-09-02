#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

reviewer_gate() {
  local required=$1 detected=$2 allowed_clean=$3 clean_findings=$4
  if (( detected >= required && clean_findings <= allowed_clean )); then printf 'pass\n'; else printf 'block\n'; fi
}
