#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../../../.." && pwd)
eval_root="$repo/models/routing/opencode/eval"
freeze="$root/config/freeze.json"
fixture="$eval_root/fixtures/reviewer-seeded-defects"
ledger="$root/ledger.json"
prompt="$root/reviewer-request.txt"
capability_prompt="$root/capability-prompt.txt"
manifest="$root/freeze-manifest.json"
approval=${EVAL_APPROVAL_FILE:-$root/approval.json}

status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status_at_freeze"])' "$freeze")
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
    "experiment_id": "reviewer-cross-family-quality-screening-20261003",
    "status": "APPROVED_FOR_DISPATCH",
    "approved_ceiling_credits": 805,
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
source "$eval_root/scoring/fixture-defect-detectors.sh"
source "$eval_root/runtime/opencode-v1-adapter/verify-freeze-manifest.sh"

verify_freeze_manifest "$eval_root" "$manifest"
fixture_integrity_check "$fixture"
[[ "$(${OPENCODE_BIN:-opencode} --version)" == 1.18.32 ]] || {
  printf 'runtime mismatch: expected OpenCode 1.18.32\n' >&2
  exit 1
}

model_value() {
  python3 - "$freeze" "$1" "$2" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
print(document["models"][sys.argv[2]][sys.argv[3]])
PY
}

budget_value() {
  python3 - "$freeze" "$1" "$2" <<'PY'
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
  local source_config=$1 destination=$2
  mkdir -p "$destination/opencode"
  cp "$source_config" "$destination/opencode/opencode.json"
  [[ ! -f "$root/config/reviewer-prompt.md" ]] || \
    cp "$root/config/reviewer-prompt.md" "$destination/opencode/reviewer-prompt.md"
}

agent_for() {
  case "$1" in
    astra) printf 'reviewer-astra\n' ;;
    sol61) printf 'reviewer-sol61\n' ;;
    *) return 2 ;;
  esac
}

mkdir -p "$root/resolved-config"
for key in astra sol61; do
  agent=$(agent_for "$key")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$root/config/$key.json" "$config_home"
  XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    "${OPENCODE_BIN:-opencode}" debug agent "$agent" >"$root/resolved-config/$key.json"
  python3 - "$root/resolved-config/$key.json" "$(model_value "$key" model)" "$(model_value "$key" variant)" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["model"]["providerID"] + "/" + document["model"]["modelID"] == sys.argv[2]
assert document["variant"] == sys.argv[3]
assert document["mode"] == "primary"
permissions = document["permission"]
for required in (("edit", "deny"), ("task", "deny"), ("external_directory", "deny"), ("webfetch", "deny"), ("websearch", "deny")):
    key, action = required
    assert any(item["permission"] == key and item["action"] == action for item in permissions)
PY
  rm -rf "$config_home"
done

account_for() {
  case "$1" in
    astra) printf 'reviewer_astra\n' ;;
    sol61) printf 'reviewer_sol61\n' ;;
    *) return 2 ;;
  esac
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
  if grep -Eq "agentic-dev-toolkit|github\.com/Prev-I|$(printf '%s' "$repo" | sed 's/[][\.^$*+?{}|()]/\\&/g')" "$raw"; then
    printf 'repository access detected in isolated dispatch: %s\n' "$raw" >&2
    return 1
  fi
}

run_probe() {
  local key=$1 account projection out credits sandbox config_home
  account=$(account_for "$key")
  projection=$(budget_value probe_admission_credits "$key")
  out="$root/capability/$key"
  [[ ! -e "$out" ]] || { printf 'probe already exists: %s\n' "$out" >&2; return 2; }
  ledger_admit "$ledger" "$account" "$projection" || return 1
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$root/config/capability-isolation.json" "$config_home"
  trap 'rm -rf "$sandbox" "$config_home"' RETURN
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_capped "$account" --outdir "$out" --label "reviewer-$key-capability" \
    --prompt-file "$capability_prompt" --model "$(model_value "$key" model)" \
    --variant "$(model_value "$key" variant)" --workspace "$sandbox" --timeout 120 \
    --ledger "$ledger" --account "$account" --attempt 1; then
      status=0
    else
      status=$?
    fi
  check_fallback "$out/raw.jsonl"
  check_repository_isolation "$out/raw.jsonl"
  credits=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["derived_credits"])' "$out/dispatch.json")
  [[ "$credits" != None ]] || return 1
  (( status == 0 )) || return "$status"
  [[ "$(<"$out/response.txt")" == CAPABILITY_OK ]] || return 1
  ledger_spent "$ledger" "$account" >/dev/null
}

run_case() {
  local key=$1 case_id=$2 sequence=$3 agent account projection config out sandbox case_dir credits config_home
  agent=$(agent_for "$key")
  account=$(account_for "$key")
  projection=$(budget_value workload_admission_per_call_credits "$key")
  config="$root/config/$key.json"
  out="$root/runs/$sequence-$case_id-$key"
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")
  config_home=$(mktemp -d "${TMPDIR:-/tmp}/eval-config.XXXXXX")
  prepare_config_home "$config" "$config_home"
  trap 'rm -rf "$sandbox" "$config_home"' RETURN
  [[ ! -e "$out" ]] || { printf 'run already exists: %s\n' "$out" >&2; return 2; }
  ledger_admit "$ledger" "$account" "$projection" || return 1
  cp "$fixture/clean/"*.sh "$sandbox/"
  if [[ "$case_id" != clean ]]; then
    case_dir="$fixture/cases/$case_id"
    python3 - "$case_dir/ground-truth.json" "$case_dir" "$sandbox" <<'PY'
import json
import shutil
import sys
ground_truth_path, case_dir, sandbox = sys.argv[1:]
for override in json.load(open(ground_truth_path, encoding="utf-8"))["overrides"]:
    shutil.copy(f"{case_dir}/{override}", f"{sandbox}/{override}")
PY
  fi
  if XDG_CONFIG_HOME="$config_home" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    dispatch_capped "$account" --outdir "$out/dispatch" \
    --label "reviewer-$case_id-$key" --prompt-file "$prompt" --agent "$agent" \
    --workspace "$sandbox" --timeout 480 --ledger "$ledger" --account "$account" \
    --attempt 1; then
      status=0
    else
      status=$?
    fi
  check_fallback "$out/dispatch/raw.jsonl"
  check_repository_isolation "$out/dispatch/raw.jsonl"
  dispatch_extract_json "$out/dispatch" >"$out/reported.json"
  credits=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["derived_credits"])' "$out/dispatch/dispatch.json")
  [[ "$credits" != None ]] || return 1
  ledger_spent "$ledger" "$account" >/dev/null
  (( status == 0 )) || return "$status"
}

run_probe astra
run_probe sol61
run_case astra clean 01
run_case sol61 clean 02
run_case sol61 R-API 03
run_case astra R-API 04
run_case astra R-AUTH 05
run_case sol61 R-AUTH 06
run_case sol61 R-BOUNDARY 07
run_case astra R-BOUNDARY 08
run_case astra R-CONCURRENCY 09
run_case sol61 R-CONCURRENCY 10
run_case sol61 R-ERROR 11
run_case astra R-ERROR 12
