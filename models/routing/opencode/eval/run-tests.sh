#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for test_file in "$root"/tests/*-test.sh; do
  bash "$test_file"
done
