#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash "$root/scoring/fixture-integrity-v2.sh"
/usr/bin/python3 - "$root" <<'PY'
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

root = Path(sys.argv[1])
v2 = root / 'fixtures/reviewer-seeded-defects-v2'
spec = importlib.util.spec_from_file_location('scorer', root / 'scoring/reviewer-v2.py')
scorer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scorer)
oracle = json.loads((v2 / 'oracle.json').read_text())
findings = {'seeded': [], 'clean': []}
for case in oracle['expected_ids']:
    truth = json.loads((v2 / 'cases' / case / 'ground-truth.json').read_text())
    findings['seeded'].append({'id': case, 'files': truth['overrides'], 'all_reported': [
        {'file': truth['overrides'][0], 'severity': 'material', 'evidence': truth.get('witness', 'ownership bypass')}
    ]})
assert scorer.attribute(v2, findings)['gate'] == 'pass'
concurrency = next(f for f in findings['seeded'] if f['id'] == 'R-CONCURRENCY')
concurrency['all_reported'].append({'file': 'counter.sh', 'severity': 'material', 'evidence': 'counter.read_text()'})
assert scorer.attribute(v2, findings)['attribution']['R-CONCURRENCY'] == 'detected'
concurrency['all_reported'].append(dict(concurrency['all_reported'][0]))
assert scorer.attribute(v2, findings)['attribution']['R-CONCURRENCY'] == 'ambiguous'
concurrency['all_reported'] = [{'file': 'counter.sh', 'severity': 'material', 'evidence': 'counter.read_text()'}]
assert scorer.attribute(v2, findings)['attribution']['R-CONCURRENCY'] == 'missed'
concurrency['all_reported'][0]['evidence'] = None
assert scorer.attribute(v2, findings)['attribution']['R-CONCURRENCY'] == 'missed'
findings['clean'] = [{'severity': 'material'}]
assert scorer.attribute(v2, findings)['gate'] == 'block'
import copy
duplicate = copy.deepcopy(findings)
duplicate['seeded'].append(copy.deepcopy(duplicate['seeded'][0]))
try:
    scorer.attribute(v2, duplicate)
except ValueError:
    pass
else:
    raise AssertionError('duplicate cases must fail closed')

# Run as the owning non-root user: writable but unreadable is the reported case.
with tempfile.TemporaryDirectory() as tmp:
    import os
    assert os.geteuid() != 0, 'read-permission proof requires a non-root user'
    counter = Path(tmp) / 'unreadable'
    counter.write_text('41\n')
    counter.chmod(0o200)
    old = subprocess.run(['bash', '-c', 'source "$1"; increment_counter "$2"', '_',
                          str(root / 'fixtures/reviewer-seeded-defects/clean/counter.sh'), str(counter)],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    counter.chmod(0o600)
    assert old.returncode == 0 and counter.read_text() == '1\n' and old.stderr
    for variant in ('clean', 'cases/R-CONCURRENCY'):
        file = v2 / variant / 'counter.sh'
        missing = Path(tmp) / 'missing'
        result = subprocess.run(['bash', '-c', 'source "$1"; increment_counter "$2"', '_', str(file), str(missing)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode != 0 and not missing.exists()
        counter = Path(tmp) / 'counter'
        counter.write_text('41\n')
        counter.chmod(0o200)
        result = subprocess.run(['bash', '-c', 'source "$1"; increment_counter "$2"', '_', str(file), str(counter)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        counter.chmod(0o600)
        assert result.returncode != 0 and counter.read_text() == '41\n'
        counter.write_text('malicious[0]\n')
        result = subprocess.run(['bash', '-c', 'source "$1"; increment_counter "$2"', '_', str(file), str(counter)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode != 0 and counter.read_text() == 'malicious[0]\n'
        counter.write_text('7\n')
        subprocess.run(['bash', '-c', 'source "$1"; increment_counter "$2"', '_', str(file), str(counter)], check=True)
        assert counter.read_text() == '8\n'
    clean = subprocess.run(['bash', '-c', 'source "$1"; validate_page_size 0', '_', str(v2 / 'clean/pagination.sh')])
    seed = subprocess.run(['bash', '-c', 'source "$1"; validate_page_size 0', '_', str(v2 / 'cases/R-BOUNDARY/pagination.sh')])
    assert clean.returncode != 0 and seed.returncode == 0
print('PASS: POST_RUN_DIAGNOSTIC v2 fixture proof and fail-closed witness attribution')
PY
