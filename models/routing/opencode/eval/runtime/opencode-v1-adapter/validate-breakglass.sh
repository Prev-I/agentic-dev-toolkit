#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

validate_breakglass() {
  local file=$1
  grep -q '"mode"[[:space:]]*:[[:space:]]*"primary"' "$file" &&
    grep -q '"model"[[:space:]]*:[[:space:]]*"openai/gpt-5.6-sol"' "$file" &&
    grep -q '"variant"[[:space:]]*:[[:space:]]*"max"' "$file"
}
