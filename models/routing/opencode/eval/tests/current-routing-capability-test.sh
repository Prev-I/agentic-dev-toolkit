#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
/usr/bin/python3 - "$root" <<'PY'
import fnmatch
import json
from pathlib import Path
import sys

record = Path(sys.argv[1]) / 'records/current-routing-capability-2026-10'
summary = json.loads((record / 'summary.json').read_text())
ledger = json.loads((record / 'ledger.json').read_text())
expected = {
    'plan': ('github-copilot/claude-opus-5.5', 'xhigh'),
    'general': ('github-copilot/gpt-6.1-sol', 'medium'),
    'compaction': ('github-copilot/claude-sonnet-5.5', 'low'),
    'title': ('github-copilot/gpt-6-luna', 'low'),
    'summary': ('github-copilot/gpt-6-luna', 'low'),
    'expert': ('openai/gpt-6-astra', 'xhigh'),
}
assert {p.name for p in (record / 'probes').iterdir()} == set(expected)
assert [e['label'] for e in ledger['entries']] == [f'{r}-capability' for r in list(expected)[:-1]]
spent = 0
for role, (model, variant) in expected.items():
    probe = record / 'probes' / role
    d = json.loads((probe / 'dispatch.json').read_text())
    assert (d['dispatch_target'], d['variant']) == (model, variant)
    assert d['classification'] == 'OK' and d['provider_error_text'] is None
    assert (probe / 'response.txt').read_text().strip() == 'CAPABILITY_OK'
    assert d['retry_count'] == 0
    resolved = json.loads((record / 'resolved' / (role + '.json')).read_text())
    assert resolved['model']['providerID'] + '/' + resolved['model']['modelID'] == model
    assert resolved['variant'] == variant
    if role == 'expert':
        assert d['derived_credits'] is None
        assert json.loads((probe / 'outcome.json').read_text())['stop_reason'] == 'COST_ACCOUNTING_UNAVAILABLE'
    else:
        assert spent + 20 <= 150  # each observed call's prior admission
        spent += d['derived_credits']
assert abs(spent - sum(e['credits'] for e in ledger['entries'])) < 1e-9
assert abs(spent - summary['observed_copilot_credits']) < 1e-9
assert summary['not_run_roles'] == ['breakglass']
assert summary['reconciled_overall_credits'] is None
assert summary['routing_changed'] is False and summary['role_fitness_established'] is False
boundary = json.loads((record / 'breakglass-non-exposure.json').read_text())
assert boundary['candidate_dispatches'] == 0 and boundary['non_exposure'] is True
for role in ('build', 'plan', 'general', 'breakglass'):
    d = json.loads((record / 'permissions' / (role + '-resolved.json')).read_text())
    matches = [r['action'] for r in d['permission'] if r['permission'] == 'task'
               and fnmatch.fnmatchcase('breakglass', r['pattern'])]
    assert matches[-1] == 'deny'
print('PASS: current routing successful-call evidence, accounting stop and Breakglass Task denial')
PY
