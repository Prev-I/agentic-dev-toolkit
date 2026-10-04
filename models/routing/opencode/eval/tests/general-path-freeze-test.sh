#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
/usr/bin/python3 - "$root" <<'PY'
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
r = root / 'records/general-path-screening'
p = json.loads((r / 'protocol.json').read_text())
c = json.loads((r / 'catalog-snapshot.json').read_text())['models']
assert p['status_at_freeze'] == 'AWAITING_APPROVAL'
assert not p['automatic_routing_change'] and not p['workload']['gate_workload']
assert p['workload']['attempts_per_model'] == 3
assert len(set(p['order'])) == 9
for model in p['models']:
    assert c[model['key']]['id'] == model['id']
    assert c[model['key']]['requested_variant'] == model['variant']
maxima = {k: Decimal(0) for k in c}
for raw in (root / 'records/opus55-gpt61-build-quality-screening/runs').glob('*-coding-*/dispatch/raw.jsonl'):
    totals = {k: Decimal(0) for k in c}
    for line in raw.read_text().splitlines():
        e = json.loads(line)
        if e.get('type') != 'step_finish':
            continue
        t = e['part']['tokens']; cache = t['cache']
        for k, prices in c.items():
            totals[k] += (Decimal(t['input'] + cache['write']) * Decimal(str(prices['input'])) +
                          Decimal(t['output'] + t['reasoning']) * Decimal(str(prices['output'])) +
                          Decimal(cache['read']) * Decimal(str(prices['cache_read']))) / Decimal(10000)
    maxima = {k: max(maxima[k], totals[k]) for k in c}
for k, maximum in maxima.items():
    assert maximum == Decimal(str(p['budget']['coding_projection_per_attempt'][k]))
admission = sum(3 * v + Decimal(str(p['budget']['probe_projection'][k])) for k, v in maxima.items())
assert admission == Decimal('691.62284')
assert admission + Decimal('70.025625') == Decimal('761.648465')
assert p['budget']['proposed_ceiling_credits'] == 765
manifest = json.loads((r / 'freeze-manifest.json').read_text())
for item in manifest['files']:
    assert hashlib.sha256((root / item['path']).read_bytes()).hexdigest() == item['sha256'], item['path']
assert not (r / 'approval.json').exists() and not (r / 'runs').exists()
print('PASS: General design freeze, prices, token replay and ceiling derivation')
PY
