#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$root/fixtures/reviewer-seeded-defects-v2"
source "$root/scoring/fixture-defect-detectors.sh"
# Reuse the v1 behavioral detectors for unchanged files, not the v1 counter
# locking heuristic (v2 deliberately has an early-release seed).
for entry in "${FIXTURE_KNOWN_CHECKS[@]}"; do
  IFS=: read -r description detector name <<<"$entry"
  [[ "$name" != counter.sh ]] || continue
  if "$detector" "$fixture/clean/$name"; then
    printf 'v2 clean defect: %s\n' "$description" >&2; exit 1
  fi
done
for case in R-API R-AUTH R-BOUNDARY R-ERROR; do
  IFS=: read -r own_detector name <<<"${FIXTURE_EXPECTED_DEFECT[$case]}"
  "$own_detector" "$fixture/cases/$case/$name" || { printf 'v2 missing seed: %s\n' "$case" >&2; exit 1; }
  for entry in "${FIXTURE_KNOWN_CHECKS[@]}"; do
    IFS=: read -r description detector checked_name <<<"$entry"
    [[ "$checked_name" == "$name" && "$detector" != "$own_detector" ]] || continue
    if "$detector" "$fixture/cases/$case/$name"; then
      printf 'v2 unintended seed defect: %s/%s\n' "$case" "$description" >&2; exit 1
    fi
  done
done
/usr/bin/python3 - "$fixture" <<'PY'
import json
from pathlib import Path
import sys
f = Path(sys.argv[1])
clean = (f / 'clean/counter.sh').read_text()
seed = (f / 'cases/R-CONCURRENCY/counter.sh').read_text()
w = json.loads((f / 'cases/R-CONCURRENCY/ground-truth.json').read_text())['witness']
if not w or w in clean or seed.count(w) != 1:
    raise SystemExit('invalid concurrency witness')
if seed.index('LOCK_EX') >= seed.index('LOCK_UN') or seed.index('LOCK_UN') >= seed.index('counter.read_text'):
    raise SystemExit('missing premature-unlock seed')
if seed.replace('        ' + w + '\n', '') != clean:
    raise SystemExit('counter seed contains another difference')
for case in (f / 'cases').iterdir():
    truth = json.loads((case / 'ground-truth.json').read_text())
    if {p.name for p in case.glob('*.sh')} != set(truth['overrides']):
        raise SystemExit('override inventory mismatch')
PY
printf 'PASS: POST_RUN_DIAGNOSTIC v2 fixture integrity\n'
