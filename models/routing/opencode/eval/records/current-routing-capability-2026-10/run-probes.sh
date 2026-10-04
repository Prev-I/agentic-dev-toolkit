#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
eval_root=$(cd "$root/../.." && pwd)
source "$eval_root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
ledger="$root/ledger.json"
mkdir -p "$root/resolved"
# Capture every requested active row before paid dispatches, including rows that
# might not run because an earlier stop condition fires.
for role in plan general compaction title summary expert breakglass; do
  [[ ! -e "$root/resolved/$role.json" ]] || { printf 'inventory already exists\n' >&2; exit 2; }
  opencode debug agent "$role" >"$root/resolved/$role.json"
done
workspace=$(mktemp -d /tmp/capability.XXXXXX)
config_home=$(mktemp -d /tmp/capability-config.XXXXXX)
trap 'rm -rf "$workspace" "$config_home"' EXIT
mkdir -p "$config_home/opencode"
printf '%s\n' '{"agent":{"build":{"permission":"deny"}}}' >"$config_home/opencode/opencode.json"
for role in plan general compaction title summary expert breakglass; do
  readarray -t row < <(/usr/bin/python3 - "$root/resolved/$role.json" "$role" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
provider = d['model']['providerID']
if sys.argv[2] in ('expert', 'breakglass') and provider != 'openai':
    raise SystemExit('Direct OpenAI provider required')
print(provider + '/' + d['model']['modelID'])
print(d['variant'])
PY
)
  [[ ${#row[@]} == 2 ]] || exit 1
  ledger_admit "$ledger" current_routing_capability 20 || exit 1
  [[ ! -e "$root/probes/$role" ]] || exit 2
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_fixture --outdir "$root/probes/$role" --label "$role-capability" \
      --prompt-file "$root/capability-prompt.txt" --model "${row[0]}" --variant "${row[1]}" \
      --workspace "$workspace" --timeout 120 --ledger "$ledger" --account current_routing_capability; then
    status=0
  else
    status=$?
  fi
  ROLE="$role" STATUS="$status" /usr/bin/python3 - "$root/probes/$role" <<'PY'
import json, os, sys
from pathlib import Path
p = Path(sys.argv[1]); d = json.loads((p / 'dispatch.json').read_text())
reason = None
if int(os.environ['STATUS']) != 0 or d.get('provider_error_text'):
    reason = 'DISPATCH_OR_PROVIDER_ERROR'
elif (p / 'response.txt').read_text().strip() != 'CAPABILITY_OK':
    reason = 'RESPONSE_MISMATCH'
elif d['derived_credits'] is None:
    reason = 'COST_ACCOUNTING_UNAVAILABLE'
result = {'role': os.environ['ROLE'], 'successful_inference': d['classification'] == 'OK' and (p / 'response.txt').read_text().strip() == 'CAPABILITY_OK',
          'stop_reason': reason, 'observed_cost': d['observed_cost'], 'derived_credits': d['derived_credits']}
(p / 'outcome.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
raise SystemExit(1 if reason else 0)
PY
done
