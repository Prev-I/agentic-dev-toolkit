#!/usr/bin/env bash
set -Eeuo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
record=$(cd "$here/.." && pwd)
eval_root=$(cd "$record/../.." && pwd)
ledger="$record/ledger.json"
[[ ! -e "$here/dispatch" && ! -e "$here/started.json" ]] || {
  printf 'Single-call probe already attempted; no retry permitted\n' >&2; exit 3;
}

# Inspect only credential metadata; no values or identifiers leave this process.
/usr/bin/python3 - "$here" <<'PY'
import json, os
from pathlib import Path
import sys
auth = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'opencode/auth.json'
a = json.loads(auth.read_text()).get('openai', {})
passed = (a.get('type') == 'oauth' and bool(a.get('accountId')) and bool(a.get('access'))
          and bool(a.get('refresh')) and not a.get('key') and not a.get('apiKey')
          and not os.environ.get('OPENAI_API_KEY')
          and not os.environ.get('OPENCODE_CONFIG') and not os.environ.get('OPENCODE_CONFIG_CONTENT'))
if not passed:
    raise SystemExit('Subscription authentication precondition failed; no dispatch')
(Path(sys.argv[1]) / 'authentication-check.json').write_text(json.dumps({
    'provider': 'openai', 'credential_type': a.get('type'), 'oauth_account_present': bool(a.get('accountId')),
    'api_key_credential_present': False, 'api_key_environment_present': False,
    'subscription_auth_precondition_passed': True,
    'historical_expert_auth_at_dispatch_independently_captured': False
}, indent=2) + '\n')
PY

# Resolved config can be lengthy. Capture safely without putting any credentials
# into evidence files; subprocess output is inspected in memory only.
/usr/bin/python3 - "$here" <<'PY'
import json, subprocess
from pathlib import Path
import sys
p = subprocess.run(['opencode', 'debug', 'config'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
try:
    config = json.loads(p.stdout)
except json.JSONDecodeError:
    raise SystemExit('Cannot validate resolved provider overrides; no dispatch')
provider = config.get('provider', {}).get('openai', {})
if provider.get('options', {}) or provider.get('npm') or provider.get('api'):
    raise SystemExit('OpenAI provider override requires manual verification; no dispatch')
q = Path(sys.argv[1]) / 'authentication-check.json'
d = json.loads(q.read_text())
d['resolved_openai_provider_options_absent'] = True
q.write_text(json.dumps(d, indent=2) + '\n')
PY

workspace=$(mktemp -d /tmp/breakglass-capability.XXXXXX)
trap 'rm -rf "$workspace"' EXIT
OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode debug agent breakglass | \
  /usr/bin/python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps({k:d[k] for k in ("name","mode","model","variant","permission","tools")}))' >"$workspace/active.json"
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_CONFIG="$here/config.json" \
  opencode debug agent breakglass-capability-only >"$workspace/experiment.json"
/usr/bin/python3 - "$workspace" "$here" <<'PY'
import json
from pathlib import Path
import sys
w, out = map(Path, sys.argv[1:])
active, experiment = [json.loads((w / name).read_text()) for name in ('active.json', 'experiment.json')]
expected = {'providerID': 'openai', 'modelID': 'gpt-6.1-sol'}
def effective_rules(document):
    # External skill directory discovery can reorder independent path rules
    # between CLI invocations. Retain last-match value for each tool/pattern;
    # ordered Task rules must still be exactly equal.
    rules = {}
    for rule in document['permission']:
        rules[(rule['permission'], rule['pattern'])] = rule['action']
    return rules
active_task = [r for r in active['permission'] if r['permission'] == 'task']
experiment_task = [r for r in experiment['permission'] if r['permission'] == 'task']
if not (active['model'] == experiment['model'] == expected and active['variant'] == experiment['variant'] == 'max'
        and active['mode'] == experiment['mode'] == 'primary'
        and effective_rules(active) == effective_rules(experiment) and active_task == experiment_task
        and active['tools'] == experiment['tools'] and experiment['tools']['task'] is False):
    raise SystemExit('Experiment differs from active Breakglass permissions or target; no dispatch')
# Reduced capture: no external-directory paths or unrelated host metadata.
capture = {k: experiment[k] for k in ('name', 'mode', 'model', 'variant')}
capture['permission'] = {k: 'deny' for k in ('edit', 'bash', 'task')}
capture['effective_permissions_identical_to_active_breakglass'] = True
capture['effective_tools_identical_to_active_breakglass'] = True
capture['task_tool_available'] = False
(out / 'resolved-experiment.json').write_text(json.dumps(capture, indent=2) + '\n')
PY

# Reserve once before making the request. Interrupted attempts consume allowance.
/usr/bin/python3 - "$ledger" "$here" <<'PY'
import datetime, json
from pathlib import Path
import sys
ledger, here = map(Path, sys.argv[1:])
d = json.loads(ledger.read_text()); a = d['subscription_account']
spent = sum(e['calls'] for e in a['entries'] if e['scope'] == 'new_allowance')
if spent + 1 > a['allowance']['ceiling_calls']:
    raise SystemExit('Subscription call admission refused')
stamp = datetime.datetime.now().astimezone().isoformat()
with (here / 'started.json').open('x') as f:
    json.dump({'started_at': stamp, 'reserved_calls': 1, 'account': 'openai_subscription'}, f)
a['entries'].append({'label': 'breakglass-capability', 'scope': 'new_allowance', 'calls': 1,
                     'status': 'RESERVED_BEFORE_DISPATCH', 'timestamp': stamp,
                     'derived_credits': None, 'tokens': None})
ledger.write_text(json.dumps(d, indent=2) + '\n')
PY
source "$eval_root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
if OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_CONFIG="$here/config.json" \
  dispatch_fixture --outdir "$here/dispatch" --label breakglass-subscription-capability \
    --prompt-file "$record/capability-prompt.txt" --agent breakglass-capability-only \
    --model openai/gpt-6.1-sol --variant max --workspace "$workspace" --timeout 120 --attempt 1; then
  status=0
else
  status=$?
fi
STATUS="$status" /usr/bin/python3 - "$here" "$ledger" <<'PY'
import json, os, re
from pathlib import Path
import sys
here, ledger = map(Path, sys.argv[1:])
dispatch = json.loads((here / 'dispatch/dispatch.json').read_text())
raw = (here / 'dispatch/raw.jsonl').read_text()
response = (here / 'dispatch/response.txt').read_text().strip()
error = dispatch.get('provider_error_text') or ''
if dispatch.get('provider_status_code') == 429 or re.search(r'(?i)rate.?limit|quota|usage.?limit|limit.?reached', error):
    result = 'QUOTA_BLOCKED'
elif int(os.environ['STATUS']) != 0 or error or 'Falling back to default agent' in raw:
    result = 'PROVIDER_OR_DISPATCH_ERROR'
elif response != 'CAPABILITY_OK':
    result = 'RESPONSE_MISMATCH'
else:
    result = 'PASS'
doc = {'result': result, 'model': 'openai/gpt-6.1-sol', 'requested_variant': 'max',
       'agent': 'breakglass-capability-only', 'task_dispatches': 0, 'calls': 1,
       'derived_credits': None, 'accounting_basis': 'subscription quota, not metered consumption spend',
       'tokens': dispatch['tokens'], 'role_fitness_established': False, 'routing_changed': False}
(here / 'outcome.json').write_text(json.dumps(doc, indent=2) + '\n')
d = json.loads(ledger.read_text())
e = next(e for e in d['subscription_account']['entries'] if e['scope'] == 'new_allowance')
e.update({'status': result, 'dispatch': 'breakglass-completion/dispatch/dispatch.json',
          'tokens': dispatch['tokens'], 'runtime_reported_cost': dispatch['observed_cost'],
          'dispatch_timestamp': dispatch['timestamp']})
ledger.write_text(json.dumps(d, indent=2) + '\n')
print(json.dumps(doc))
raise SystemExit(0 if result == 'PASS' else 1)
PY
