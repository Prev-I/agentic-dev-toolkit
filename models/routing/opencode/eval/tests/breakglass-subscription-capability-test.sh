#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
/usr/bin/python3 - "$root" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

r = Path(sys.argv[1]) / 'records/current-routing-capability-2026-10'
c = r / 'breakglass-completion'
account = json.loads((r / 'ledger.json').read_text())['subscription_account']
assert account['provider'] == 'openai' and account['unit'] == 'calls'
assert account['unit_definition'].startswith('primary probe dispatches')
auxiliary = account['auxiliary_requests']
assert len(auxiliary) == 2
assert [(e['provider'], e['agent']) for e in auxiliary] == [('openai', 'title'), ('github-copilot', 'title')]
assert all(e['cost'] is None and e['tokens'] is None for e in auxiliary)
assert account['allowance']['ceiling_calls'] == 1
assert account['allowance']['historical_calls_excluded'] is True
assert account['accounting_basis'] == 'subscription quota, not metered consumption spend'
entries = account['entries']
assert len(entries) == 2 and sum(e['calls'] for e in entries) == 2
historical, new = entries
assert historical['scope'] == 'historical' and historical['recorded_retroactively'] is True
assert new['scope'] == 'new_allowance' and new['calls'] == 1 and new['status'] == 'PASS'
for e in entries:
    d = json.loads((r / e['dispatch']).read_text())
    assert e['derived_credits'] is None and e['tokens'] == d['tokens']
    assert d['classification'] == 'OK' and d['retry_count'] == 0
d = json.loads((c / 'dispatch/dispatch.json').read_text())
assert d['dispatch_target'] == 'agent:breakglass-capability-only' and d['variant'] == 'max'
assert d['provider_error_text'] is None
assert (c / 'dispatch/response.txt').read_text().strip() == 'CAPABILITY_OK'
resolved = json.loads((c / 'resolved-experiment.json').read_text())
assert resolved['model'] == {'providerID': 'openai', 'modelID': 'gpt-6.1-sol'}
assert resolved['variant'] == 'max' and resolved['mode'] == 'primary'
assert resolved['permission'] == {'edit': 'deny', 'bash': 'deny', 'task': 'deny'}
assert resolved['effective_permissions_identical_to_active_breakglass'] is True
assert resolved['task_tool_available'] is False
auth = json.loads((c / 'authentication-check.json').read_text())
assert auth['credential_type'] == 'oauth' and auth['subscription_auth_precondition_passed'] is True
assert auth['api_key_credential_present'] is False and auth['api_key_environment_present'] is False
assert auth['resolved_openai_provider_options_absent'] is True
outcome = json.loads((c / 'outcome.json').read_text())
assert outcome['result'] == 'PASS' and outcome['calls'] == 1 and outcome['task_dispatches'] == 0
assert outcome['routing_changed'] is False and outcome['role_fitness_established'] is False
# Real guard must refuse before authentication inspection or any possible request.
before = (r / 'ledger.json').read_bytes()
result = subprocess.run(['bash', str(c / 'run-once.sh')], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert result.returncode == 3 and b'no retry permitted' in result.stderr
assert before == (r / 'ledger.json').read_bytes()
print('PASS: subscription accounting, one-call reservation and Breakglass successful primary inference')
PY
