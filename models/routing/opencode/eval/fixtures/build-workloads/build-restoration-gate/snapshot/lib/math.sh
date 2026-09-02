#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

identity() {
  printf '%s\n' "$1"
}
