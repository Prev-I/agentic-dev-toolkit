#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

for directory in fixtures scoring thresholds decision-rules runtime/opencode-v1-adapter records manifests; do
  assert_dir "$root/$directory"
done

printf 'PASS: Phase 0 eval layout\n'
