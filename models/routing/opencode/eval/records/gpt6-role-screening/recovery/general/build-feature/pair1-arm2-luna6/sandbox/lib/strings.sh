#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

upper() {
  printf '%s\n' "${1^^}"
}
