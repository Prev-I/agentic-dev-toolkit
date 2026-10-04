"""Single authorized production-agent probe; no model/variant/config override."""
import datetime
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

here = Path(__file__).resolve().parent
ledger = here.parent / 'current-routing-capability-2026-10/ledger.json'
stamp = lambda: datetime.datetime.now().astimezone().isoformat()
if (here / 'started.json').exists():
    raise SystemExit('Already reserved/attempted; no retry permitted')
if any(os.environ.get(k) for k in ('OPENCODE_CONFIG', 'OPENCODE_CONFIG_CONTENT', 'OPENAI_API_KEY', 'OPENCODE_DISABLE_PROJECT_CONFIG')):
    raise SystemExit('Unexpected config/auth override; no dispatch')
if subprocess.check_output(['opencode', '--version'], text=True).strip() != '1.18.32':
    raise SystemExit('Unexpected runtime; no dispatch')

with tempfile.TemporaryDirectory(prefix='title-provider-', dir='/tmp/opencode') as workspace:
    resolved = {}
    for name in ('build', 'expert', 'title', 'summary'):
        data = json.loads(subprocess.check_output(['opencode', 'debug', 'agent', name], cwd=workspace))
        resolved[name] = {key: data.get(key) for key in ('name', 'mode', 'model', 'variant')}
    expected = {'build': ('github-copilot', 'gpt-6.1-sol'), 'expert': ('openai', 'gpt-6-astra'),
                'title': ('github-copilot', 'gpt-6-luna'), 'summary': ('github-copilot', 'gpt-6-luna')}
    for name, (provider, model) in expected.items():
        assert resolved[name]['model'] == {'providerID': provider, 'modelID': model}
    auth = json.loads((Path.home() / '.local/share/opencode/auth.json').read_text()).get('openai', {})
    assert auth.get('type') == 'oauth' and auth.get('access') and not auth.get('key')
    (here / 'resolved.json').write_text(json.dumps(resolved, indent=2) + '\n')

    document = json.loads(ledger.read_text())
    assert 'title_provider_check' not in document
    reservation = {'timestamp': stamp(), 'status': 'RESERVED_BEFORE_DISPATCH',
                   'copilot_account': 'current_routing_capability', 'copilot_ceiling_credits': 10,
                   'reserved_credits': 10, 'subscription_account': 'openai_subscription',
                   'subscription_ceiling_calls': 1, 'reserved_calls': 1,
                   'unit_definition': 'one expert Task dispatch, auxiliary requests declared separately',
                   'auxiliary_requests': [], 'retry_count': 0}
    with (here / 'started.json').open('x') as output:
        json.dump(reservation, output, indent=2)
    document['title_provider_check'] = reservation
    ledger.write_text(json.dumps(document, indent=2) + '\n')
    command = ['opencode', '--print-logs', '--log-level', 'INFO', 'run', '--agent', 'build',
               '--format', 'json', (here / 'prompt.txt').read_text()]
    raw_path = here / 'raw.jsonl'
    # Keep full runtime stderr only in disposable scratch; retain provider lines.
    stderr_path = Path(workspace) / 'runtime.log'
    reason = None
    start = time.monotonic()
    with raw_path.open('w') as stdout, stderr_path.open('w') as stderr:
        process = subprocess.Popen(command, cwd=workspace, stdin=subprocess.DEVNULL,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        while process.poll() is None:
            time.sleep(0.2)
            log = stderr_path.read_text(errors='replace')
            raw = raw_path.read_text(errors='replace')
            costs = []
            for line in raw.splitlines():
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get('type') == 'step_finish':
                    costs.append(float(event['part'].get('cost') or 0))
            if re.search(r'(?:statusCode[=: ]+429|rate.limit|quota.exceeded|usage.limit|limit.reached)', log + raw, re.I):
                reason = 'QUOTA_BLOCKED'
            elif len(re.findall(r'message=stream providerID=openai .*? agent=expert ', log)) > 1:
                reason = 'SUBSCRIPTION_REQUEST_LIMIT'
            elif sum(costs) * 100 >= 10:
                reason = 'BUDGET_STOP'
            elif time.monotonic() - start > 120:
                reason = 'TIMEOUT'
            if reason:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                break
        status = process.wait()
    log = stderr_path.read_text(errors='replace')
    lines = [line for line in log.splitlines() if re.search(r'message=stream providerID=', line)]
    (here / 'provider-streams.log').write_text('\n'.join(lines) + '\n')
    requests = []
    for line in lines:
        match = re.search(r'providerID=(\S+) modelID=(\S+) session.id=(\S+) small=(\S+) agent=(\S+) mode=(\S+)', line)
        if match:
            provider, model, session, small, agent, mode = match.groups()
            requests.append(dict(provider=provider, model=model, session=session, small=small, agent=agent, mode=mode))
    # Export is local evidence retrieval, not an inference request.
    messages = []
    for session in sorted({request['session'] for request in requests}):
        export = subprocess.run(['opencode', 'export', session], cwd=workspace,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        data = json.loads(export.stdout)
        (here / f'{session}.json').write_text(json.dumps(data, indent=2) + '\n')
        messages.extend(data.get('messages', []))
    cost = sum(float(item['info'].get('cost') or 0) for item in messages
               if item['info'].get('providerID') == 'github-copilot')
    task_parts = [part for item in messages for part in item.get('parts', [])
                  if part.get('type') == 'tool' and part.get('tool') == 'task']
    expert = [request for request in requests if request['agent'] == 'expert']
    auxiliary = [request for request in requests if request['agent'] in ('title', 'summary')]
    leak = any(request['provider'] != 'github-copilot' for request in auxiliary)
    complete = status == 0 and len(task_parts) == 1 and task_parts[0]['state']['status'] == 'completed' and len(expert) == 1
    outcome = {'record_status': 'POST_RUN_DIAGNOSTIC', 'runtime_version': '1.18.32',
               'status': reason or ('PASS' if complete else 'INCOMPLETE'),
               'classification': ('LEAK_IN_PRODUCTION_PATH' if leak else 'LEAK_DISPATCHER_OVERRIDE_ONLY') if complete else None,
               'exit_status': status, 'requests': requests, 'task_dispatches': len(task_parts),
               'copilot_observed_credits': cost * 100, 'copilot_auxiliary_cost': None,
               'subscription_calls': len(task_parts), 'openai_provider_requests': len(expert),
               'auxiliary_requests': auxiliary, 'routing_changed': False,
               'budget_boundary': '10 credits reserved; completed-step watchdog, not hard in-flight cap; auxiliary title cost unavailable'}
    (here / 'outcome.json').write_text(json.dumps(outcome, indent=2) + '\n')
    document = json.loads(ledger.read_text())
    document['title_provider_check'].update(outcome)
    ledger.write_text(json.dumps(document, indent=2) + '\n')
    print(json.dumps(outcome, indent=2))
