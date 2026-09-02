#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/capture-permissions.sh"
source "$root/runtime/opencode-v1-adapter/capture-permissions.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
cat >"$workspace/opencode" <<'FAKE'
#!/usr/bin/env bash
role=${3:?}
if [[ "$role" == reviewer ]]; then
  cat <<'JSON'
{"name":"reviewer","mode":"subagent","permission":[{"permission":"edit","action":"deny","pattern":"*"},{"permission":"task","action":"deny","pattern":"*"},{"permission":"bash","action":"deny","pattern":"*"},{"permission":"bash","action":"allow","pattern":"git status*"},{"permission":"bash","action":"allow","pattern":"git diff*"},{"permission":"bash","action":"allow","pattern":"git log*"},{"permission":"bash","action":"allow","pattern":"git show*"}],"model":{"providerID":"github-copilot","modelID":"review-model"},"variant":"max","tools":{"bash":true,"task":false,"apply_patch":false,"webfetch":true,"websearch":true}}
JSON
else
  cat <<'JSON'
{"name":"expert","mode":"subagent","permission":[{"permission":"edit","action":"deny","pattern":"*"},{"permission":"task","action":"deny","pattern":"*"},{"permission":"bash","action":"deny","pattern":"*"},{"permission":"webfetch","action":"deny","pattern":"*"},{"permission":"websearch","action":"deny","pattern":"*"}],"model":{"providerID":"openai","modelID":"expert-model"},"variant":"high","tools":{"bash":false,"task":false,"apply_patch":false,"webfetch":false,"websearch":false}}
JSON
fi
FAKE
chmod +x "$workspace/opencode"

OPENCODE_BIN="$workspace/opencode" capture_agent_permissions reviewer "$workspace/reviewer.json"
OPENCODE_BIN="$workspace/opencode" capture_agent_permissions expert "$workspace/expert.json"
validate_agent_permissions reviewer "$workspace/reviewer.json"
validate_agent_permissions expert "$workspace/expert.json"
assert_contains "$(<"$workspace/reviewer.json")" '"wildcard": "deny"'
assert_contains "$(<"$workspace/reviewer.json")" '"git status*"'

python3 - "$workspace/reviewer.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["tools"]["apply_patch"] = True
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
if validate_agent_permissions reviewer "$workspace/reviewer.json"; then
  fail "accepted write-enabled Reviewer"
fi

printf 'PASS: resolved permission semantics\n'
