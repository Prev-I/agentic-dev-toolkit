#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../../../.." && pwd)
eval_root="$repo/models/routing/opencode/eval"
protocol="$root/protocol.json"
ledger="$root/ledger.json"
base="$eval_root/records/astra-build-followup/base-snapshot"
coding_prompt="$root/coding-prompt.txt"
gate_prompt="$root/gate-prompt.txt"
gate_fixture="$eval_root/fixtures/build-workloads/build-feature"
manifest="$root/freeze-manifest.json"
approval=${EVAL_APPROVAL_FILE:-$root/approval.json}
isolation_config="$root/config/build-isolation.json"

status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status_at_freeze"])' "$protocol")
if [[ "$status" != AWAITING_APPROVAL || ! -f "$approval" ]]; then
  printf 'dispatch refused: status_at_freeze=%s; explicit ceiling approval is required in approval.json\n' "$status" >&2
  exit 3
fi
if ! APPROVAL="$approval" MANIFEST="$manifest" python3 <<'PY'
import hashlib
import json
import os
import sys
document = json.load(open(os.environ["APPROVAL"], encoding="utf-8"))
expected = {
    "experiment_id": "opus55-gpt61-build-quality-screening-20261003",
    "status": "APPROVED_FOR_DISPATCH",
    "approved_ceiling_credits": 630,
    "execution_option": "FRESH_PAIRED_ARMS",
    "freeze_manifest_sha256": hashlib.sha256(open(os.environ["MANIFEST"], "rb").read()).hexdigest(),
}
if document != expected:
    raise SystemExit(1)
PY
then
  printf 'dispatch refused: approval record does not match the frozen manifest and ceiling\n' >&2
  exit 3
fi

source "$eval_root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$eval_root/runtime/opencode-v1-adapter/verify-freeze-manifest.sh"
verify_freeze_manifest "$eval_root" "$manifest"
[[ "$(${OPENCODE_BIN:-opencode} --version)" == 1.18.32 ]] || {
  printf 'runtime mismatch: expected OpenCode 1.18.32\n' >&2
  exit 1
}

model_for() {
  case "$1" in
    opus55) printf 'github-copilot/claude-opus-5.5\n' ;;
    sol61) printf 'github-copilot/gpt-6.1-sol\n' ;;
    *) return 2 ;;
  esac
}

account_for() {
  case "$1" in
    opus55) printf 'build_opus55\n' ;;
    sol61) printf 'build_sol61\n' ;;
    *) return 2 ;;
  esac
}

budget_value() {
  python3 - "$protocol" "$1" "$2" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
print(document["budget"][sys.argv[2]][sys.argv[3]])
PY
}

remaining_allowance() {
  python3 - "$ledger" "$1" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
account = sys.argv[2]
spent = sum(float(item["credits"]) for item in document["entries"] if item["account"] == account)
print(float(document["caps"][account]) - spent)
PY
}

dispatch_capped() {
  local account=$1; shift
  local remaining
  remaining=$(remaining_allowance "$account")
  EVAL_REAL_OPENCODE=${OPENCODE_BIN:-opencode} \
  EVAL_CALL_STOP_CREDITS="$remaining" \
  OPENCODE_BIN="$eval_root/runtime/opencode-v1-adapter/capped-opencode.sh" \
    dispatch_fixture "$@"
}

prepare_config_home() {
  local destination=$1
  mkdir -p "$destination/opencode"
  cp "$isolation_config" "$destination/opencode/opencode.json"
}

check_fallback() {
  local raw=$1
  if python3 - "$raw" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
raise SystemExit(0 if "Falling back to default agent" in text else 1)
PY
  then
    printf 'subagent fallback detected: %s\n' "$raw" >&2
    return 1
  fi
}

check_repository_isolation() {
  local raw=$1
  if grep -Eq "github\.com/Prev-I|$(printf '%s' "$repo" | sed 's/[][\.^$*+?{}|()]/\\&/g')" "$raw"; then
    printf 'repository access detected in isolated dispatch: %s\n' "$raw" >&2
    return 1
  fi
}

validate_isolated_config() {
  local config_home=$1
  local raw="$root/resolved-config.json"
  XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    "${OPENCODE_BIN:-opencode}" debug config >"$raw"
  python3 - "$raw" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document.get("plugin") == ["superpowers@git+https://github.com/obra/superpowers.git#v6.4.2"]
assert document.get("references", {}) == {}
assert document.get("instructions", []) == []
PY
}

run_probe() {
  local key=$1 account projection out sandbox config_home
  account=$(account_for "$key")
  projection=$(budget_value probe_admission_credits "$key")
  out="$root/capability/$key"
  [[ ! -e "$out" ]] || return 2
  ledger_admit "$ledger" "$account" "$projection" || return 1
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$config_home"
  trap 'rm -rf "$sandbox" "$config_home"' RETURN
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_capped "$account" --outdir "$out" --label "build-quality-$key-capability" \
    --prompt-file "$eval_root/records/opus55-reviewer-screening/capability-prompt.txt" \
    --model "$(model_for "$key")" --variant high --workspace "$sandbox" --timeout 120 \
    --ledger "$ledger" --account "$account" --attempt 1; then
      status=0
    else
      status=$?
    fi
  check_fallback "$out/raw.jsonl"
  check_repository_isolation "$out/raw.jsonl"
  python3 - "$out/dispatch.json" <<'PY'
import json
import sys
if json.load(open(sys.argv[1], encoding="utf-8"))["derived_credits"] is None:
    raise SystemExit(1)
PY
  (( status == 0 )) || return "$status"
  [[ "$(<"$out/response.txt")" == CAPABILITY_OK ]] || return 1
  ledger_spent "$ledger" "$account" >/dev/null
}

run_coding() {
  local key=$1 attempt=$2 sequence=$3 account projection out sandbox config_home
  account=$(account_for "$key")
  projection=$(budget_value coding_admission_per_attempt_credits "$key")
  out="$root/runs/$sequence-coding-$attempt-$key"
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$config_home"
  trap 'rm -rf "$sandbox" "$config_home"' RETURN
  [[ ! -e "$out" ]] || return 2
  ledger_admit "$ledger" "$account" "$projection" || return 1
  mkdir -p "$out"
  cp -R "$base/." "$sandbox/"
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_capped "$account" --outdir "$out/dispatch" --label "coding-$attempt-$key" \
    --prompt-file "$coding_prompt" --model "$(model_for "$key")" --variant high \
    --workspace "$sandbox" --timeout 480 --ledger "$ledger" --account "$account" \
    --attempt "$attempt"; then
      status=0
    else
      status=$?
    fi
  check_fallback "$out/dispatch/raw.jsonl"
  check_repository_isolation "$out/dispatch/raw.jsonl"
  bash "$eval_root/runtime/opencode-v1-adapter/capture-tree-patch.sh" \
    "$base" "$sandbox" "$out/work-product.patch"
  python3 - "$out/dispatch/dispatch.json" <<'PY'
import json
import sys
if json.load(open(sys.argv[1], encoding="utf-8"))["derived_credits"] is None:
    raise SystemExit(1)
PY
  ledger_spent "$ledger" "$account" >/dev/null
  (( status == 0 )) || return "$status"
}

run_gate() {
  local key=$1 attempt=$2 sequence=$3 account projection out sandbox config_home
  account=$(account_for "$key")
  projection=$(budget_value gate_admission_per_attempt_credits "$key")
  out="$root/runs/$sequence-gate-$attempt-$key"
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$config_home"
  trap 'rm -rf "$sandbox" "$config_home"' RETURN
  [[ ! -e "$out" ]] || return 2
  ledger_admit "$ledger" "$account" "$projection" || return 1
  mkdir -p "$out"
  cp -R "$gate_fixture/snapshot/." "$sandbox/"
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_capped "$account" --outdir "$out/dispatch" --label "gate-$attempt-$key" \
    --prompt-file "$gate_prompt" --model "$(model_for "$key")" --variant high \
    --workspace "$sandbox" --timeout 480 --ledger "$ledger" --account "$account" \
    --attempt "$attempt"; then
      status=0
    else
      status=$?
    fi
  check_fallback "$out/dispatch/raw.jsonl"
  check_repository_isolation "$out/dispatch/raw.jsonl"
  bash "$eval_root/runtime/opencode-v1-adapter/capture-tree-patch.sh" \
    "$gate_fixture/snapshot" "$sandbox" "$out/work-product.patch"
  python3 - "$out/dispatch/dispatch.json" <<'PY'
import json
import sys
if json.load(open(sys.argv[1], encoding="utf-8"))["derived_credits"] is None:
    raise SystemExit(1)
PY
  ledger_spent "$ledger" "$account" >/dev/null
  (( status == 0 )) || return "$status"
}

validation_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
prepare_config_home "$validation_home"
validate_isolated_config "$validation_home"
rm -rf "$validation_home"

run_probe opus55
run_probe sol61
run_coding opus55 1 01
run_coding sol61 1 02
run_coding sol61 2 03
run_coding opus55 2 04
run_coding opus55 3 05
run_coding sol61 3 06
run_gate sol61 1 07
run_gate opus55 1 08
run_gate opus55 2 09
run_gate sol61 2 10
run_gate sol61 3 11
run_gate opus55 3 12

printf 'dispatch collection complete; run the frozen verification procedure before adjudication\n'
