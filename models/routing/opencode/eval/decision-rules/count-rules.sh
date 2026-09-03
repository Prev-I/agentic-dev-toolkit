#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

count_decision() {
  local n=$1 a=$2 b=$3 gap winner
  (( a >= b )) && gap=$((a-b)) || gap=$((b-a))
  (( a >= b )) && winner=$a || winner=$b
  case "$n" in
    3)
      if (( a <= 1 && b <= 1 )); then printf 'fixture_finding\n'
      elif (( gap == 3 )); then printf 'separates\n'
      elif (( gap == 2 )); then printf 'extend_n5\n'
      elif (( gap <= 1 )); then printf 'no_separation\n'
      else printf 'inconclusive\n'; fi
      ;;
    5)
      if (( a <= 2 && b <= 2 )); then printf 'fixture_finding\n'
      elif (( winner >= 4 && gap >= 3 )); then printf 'separates\n'
      elif (( gap == 2 )); then printf 'inconclusive\n'
      elif (( gap <= 1 )); then printf 'no_separation\n'
      else printf 'inconclusive\n'; fi
      ;;
    *) printf 'inconclusive\n' ;;
  esac
}
