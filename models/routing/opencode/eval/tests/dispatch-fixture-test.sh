#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
printf 'do the thing\n' >"$workspace/prompt.txt"

make_fake() {
  local name=$1
  cat >"$workspace/$name"
  chmod +x "$workspace/$name"
}

make_fake opencode-ok <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$*" >"${DISPATCH_ARGS_SINK:-/dev/null}"
printf '{"type":"step_finish","part":{"cost":0.25,"tokens":{"total":420}}}\n'
printf '%s\n' '{"type":"text","part":{"text":"{\"ordered_path\":[\"entry\"],\"reported_hops\":1}"}}'
FAKE

make_fake opencode-error <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"error","error":{"data":{"message":"usage limit has been reached","statusCode":429}}}\n'
exit 1
FAKE

make_fake opencode-gone <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"error","error":{"data":{"message":"ProviderModelNotFoundError: model not found"}}}\n'
exit 1
FAKE

make_fake opencode-slow <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
sleep 30
FAKE

make_fake opencode-prose <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.1,"tokens":{"total":10}}}\n'
printf '{"type":"text","part":{"text":"I could not produce structured output."}}\n'
FAKE

make_fake opencode-empty <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.1,"tokens":{"total":10}}}\n'
FAKE

# --- success path, provenance, raw evidence preservation ---
out="$workspace/ok"
DISPATCH_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-ok" \
  dispatch_fixture --outdir "$out" --label explore-chain --prompt-file "$workspace/prompt.txt" \
    --agent explore --ledger "$ledger" --account evaluation \
  || fail "healthy dispatch reported failure"
assert_eq 'OK' "$(dispatch_classification "$out")"
assert_file "$out/raw.jsonl"
assert_file "$out/response.txt"
assert_file "$out/dispatch.json"
assert_contains "$(<"$out/raw.jsonl")" 'step_finish'
assert_contains "$(<"$workspace/args.txt")" '--agent explore'
assert_contains "$(<"$workspace/args.txt")" '--format json'
for field in routing_profile_commit runtime_version eval_runner_version label attempt \
             dispatch_target wall_clock_ms observed_cost derived_credits tokens exit_status classification; do
  assert_contains "$(<"$out/dispatch.json")" "\"$field\""
done
assert_eq '25' "$(ledger_spent "$ledger" evaluation)"

# --- structured extraction and parsing failure ---
assert_eq '1' "$(dispatch_extract_json "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reported_hops"])')"
prose="$workspace/prose"
OPENCODE_BIN="$workspace/opencode-prose" dispatch_fixture --outdir "$prose" --label p \
  --prompt-file "$workspace/prompt.txt" --agent explore || fail "prose dispatch should still be healthy"
assert_eq 'OK' "$(dispatch_classification "$prose")"
if dispatch_extract_json "$prose" >/dev/null 2>&1; then
  fail "accepted unparseable structured output"
fi

# --- regression: an unpaired double-quote in surrounding prose must not
# desync extraction and hide the real, well-formed final JSON object.
# (A real reviewer agent commonly writes English prose like: a value
# containing a double quote character.) ---
unpaired="$workspace/unpaired-quote"
mkdir -p "$unpaired"
printf 'The field holds a " character mid-sentence, which is not JSON.\n{"findings": ["missing auth check"], "verdict": "issues_found"}\n' \
  >"$unpaired/response.txt"
assert_eq 'issues_found' "$(dispatch_extract_json "$unpaired" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')"

# --- regression: an earlier, JSON-looking-but-unrelated substring in prose
# (e.g. an inline code example illustrating a vulnerability) must not be
# picked up instead of the real final JSON object. ---
decoy="$workspace/decoy-json"
mkdir -p "$decoy"
printf 'Example vulnerable payload: `{"displayName":"%%s"}` is unescaped.\n{"findings": ["xss"], "verdict": "issues_found"}\n' \
  >"$decoy/response.txt"
assert_eq 'xss' "$(dispatch_extract_json "$decoy" | python3 -c 'import json,sys; print(json.load(sys.stdin)["findings"][0])')"

# --- error path: transient/external maps to INVALID_ENVIRONMENT ---
err="$workspace/err"
if OPENCODE_BIN="$workspace/opencode-error" dispatch_fixture --outdir "$err" --label e \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "failed dispatch reported success"
fi
assert_eq 'INVALID_ENVIRONMENT' "$(dispatch_classification "$err")"
assert_contains "$(<"$err/dispatch.json")" '"failure_class": "QUOTA_FAILURE"'

# --- error path: capability regression is NOT laundered as INVALID_ENVIRONMENT ---
gone="$workspace/gone"
if OPENCODE_BIN="$workspace/opencode-gone" dispatch_fixture --outdir "$gone" --label g \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "capability regression reported success"
fi
assert_eq 'CAPABILITY_REGRESSION' "$(dispatch_classification "$gone")"

# --- timeout ---
slow="$workspace/slow"
if OPENCODE_BIN="$workspace/opencode-slow" dispatch_fixture --outdir "$slow" --label s \
     --prompt-file "$workspace/prompt.txt" --agent build --timeout 2; then
  fail "timed-out dispatch reported success"
fi
assert_eq 'TIMEOUT' "$(dispatch_classification "$slow")"

# --- empty response ---
empty="$workspace/empty"
if OPENCODE_BIN="$workspace/opencode-empty" dispatch_fixture --outdir "$empty" --label x \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "empty response reported success"
fi
assert_eq 'EMPTY_RESPONSE' "$(dispatch_classification "$empty")"

# --- explicit model dispatch and workspace cwd ---
mkdir -p "$workspace/fixturedir"
printf 'marker\n' >"$workspace/fixturedir/marker.txt"
model_out="$workspace/model"
DISPATCH_ARGS_SINK="$workspace/model-args.txt" OPENCODE_BIN="$workspace/opencode-ok" \
  dispatch_fixture --outdir "$model_out" --label m --prompt-file "$workspace/prompt.txt" \
    --model github-copilot/claude-sonnet-5 --variant high --workspace "$workspace/fixturedir" \
  || fail "explicit model dispatch failed"
assert_contains "$(<"$workspace/model-args.txt")" '--model github-copilot/claude-sonnet-5 --variant high'
assert_contains "$(<"$model_out/dispatch.json")" '"dispatch_target": "github-copilot/claude-sonnet-5"'

# --- the primitive owns no gate semantics ---
if grep -nE '(PASS|FAIL|pass|block)' "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh" \
     | grep -vE 'classification|CAPABILITY|INVALID|TIMEOUT|EMPTY|FAILURE_CLASS|failure_class' \
     | grep -q .; then
  fail "dispatch primitive contains gate pass/fail vocabulary"
fi

printf 'PASS: shared fixture dispatch primitive\n'
