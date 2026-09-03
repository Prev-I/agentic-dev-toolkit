#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

select_activation_target() {
  [[ $# == 1 && -n "$1" ]] || return 2
  local root=$1 json="$1/opencode.json" jsonc="$1/opencode.jsonc"
  if [[ -e "$json" && -e "$jsonc" ]]; then return 1
  elif [[ -e "$json" ]]; then printf '%s\n' "$json"
  else printf '%s\n' "$jsonc"
  fi
}
