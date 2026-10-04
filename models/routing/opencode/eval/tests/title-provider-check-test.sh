#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$root" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
record = root / 'records/title-provider-check-2026-10'
outcome = json.loads((record / 'outcome.json').read_text())
assert outcome['status'] == 'PASS'
assert outcome['classification'] == 'LEAK_DISPATCHER_OVERRIDE_ONLY'
assert outcome['routing_changed'] is False
assert outcome['task_dispatches'] == outcome['subscription_calls'] == outcome['openai_provider_requests'] == 1
requests = outcome['requests']
assert len(requests) == 4
assert [(r['provider'], r['agent']) for r in requests] == [
    ('github-copilot', 'title'), ('github-copilot', 'build'), ('openai', 'expert'), ('github-copilot', 'build')]
sessions = [json.loads(path.read_text()) for path in sorted(record.glob('ses_*.json'))]
assert len(sessions) == 2
parent = next(session for session in sessions if not session['info'].get('parentID'))
child = next(session for session in sessions if session['info'].get('parentID'))
assert child['info']['parentID'] == parent['info']['id']
parts = [part for session in sessions for message in session['messages'] for part in message['parts']]
tools = [part for part in parts if part['type'] == 'tool']
assert len(tools) == 1 and tools[0]['tool'] == 'task'
assert tools[0]['state']['status'] == 'completed'
assert tools[0]['state']['input']['subagent_type'] == 'expert'
assert any(part.get('text') == 'PROVIDER_PROBE_DONE' for part in parts)
credits = sum(float(message['info'].get('cost') or 0) for session in sessions
              for message in session['messages'] if message['info'].get('providerID') == 'github-copilot') * 100
assert abs(credits - 4.97982) < 1e-8
assert credits == outcome['copilot_observed_credits']
ledger_path = root / 'records/current-routing-capability-2026-10/ledger.json'
ledger = json.loads(ledger_path.read_text())
addition = ledger.pop('title_provider_check')
assert addition['reserved_credits'] == 10 and addition['reserved_calls'] == 1
assert addition['status'] == 'PASS' and addition['retry_count'] == 0
historical = json.loads(subprocess.check_output(['git', 'show', 'ceaa754:' + str(ledger_path.relative_to(root.parents[3]))]))
assert ledger == historical, 'Historical ledger structures changed'
assert (record / 'started.json').is_file()
run = subprocess.run(['/usr/bin/python3', str(record / 'run-once.py')],
                     env={'PATH': '/nonexistent', 'OPENCODE_CONFIG': 'offline-test-deny-dispatch'},
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert run.returncode != 0 and b'no retry permitted' in run.stderr
print('PASS: provider diagnostic matches linked sessions, spend, appended ledger and no-retry guard')
PY
