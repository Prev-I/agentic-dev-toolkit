#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

compaction_gate() { if (( $1 == $2 )); then printf 'pass\n'; else printf 'block\n'; fi; }
