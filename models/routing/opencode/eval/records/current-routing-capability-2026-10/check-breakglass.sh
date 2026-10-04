#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
eval_root=$(cd "$root/../.." && pwd)
source "$eval_root/runtime/opencode-v1-adapter/capture-permissions.sh"
mkdir -p "$root/permissions"
for role in build plan general breakglass; do
  capture_agent_permissions "$role" "$root/permissions/$role.json"
  opencode debug agent "$role" >"$root/permissions/$role-resolved.json"
done
# Reuse the ordered resolved-rule mechanism of capture_breakglass_non_exposure.
# The old probe helper pins GPT-5.6 and is not an oracle for this current profile.
/usr/bin/python3 - "$root" <<'PY'
import fnmatch
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
actions = {}
for role in ('build', 'plan', 'general', 'breakglass'):
    d = json.loads((root / 'permissions' / (role + '-resolved.json')).read_text())
    matches = [r['action'] for r in d['permission'] if r['permission'] == 'task'
               and fnmatch.fnmatchcase('breakglass', r['pattern'])]
    actions[role] = matches[-1] if matches else None
d = json.loads((root / 'permissions/breakglass-resolved.json').read_text())
passed = all(v == 'deny' for v in actions.values()) and d['mode'] == 'primary' and d['model'] == {
    'providerID': 'openai', 'modelID': 'gpt-6.1-sol'
} and d['variant'] == 'max' and d['tools']['task'] is False
result = {'evidence_mechanism': 'resolved_permission_and_inventory',
          'candidate_dispatches': 0, 'task_actions': actions,
          'breakglass_model': 'openai/gpt-6.1-sol', 'variant': d['variant'],
          'mode': d['mode'], 'non_exposure': passed}
(root / 'breakglass-non-exposure.json').write_text(json.dumps(result, indent=2) + '\n')
if not passed:
    raise SystemExit('Breakglass non-exposure failed')
print(json.dumps(result))
PY
