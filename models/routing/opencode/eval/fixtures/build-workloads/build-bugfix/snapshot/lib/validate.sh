#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

is_positive() {
  [[ "$1" =~ ^-?[0-9]+$ ]] || return 1
  (( $1 >= 0 ))
}

is_blank() {
  [[ -z "${1// }" ]]
}
