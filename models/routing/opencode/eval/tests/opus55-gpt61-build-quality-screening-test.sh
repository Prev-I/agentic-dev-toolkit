#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
record="$root/records/opus55-gpt61-build-quality-screening"

assert_file "$record/protocol.json"
assert_file "$record/coding-prompt.txt"
assert_file "$record/gate-prompt.txt"
assert_file "$record/run-screening.sh"
assert_file "$record/ledger.json"
assert_file "$record/attempts.json"
assert_file "$record/adjudication.json"
assert_file "$record/freeze-manifest.json"
assert_file "$record/config/build-isolation.json"
assert_file "$record/verify-results.sh"

python3 - "$root" "$record" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

eval_root = Path(sys.argv[1])
record = Path(sys.argv[2])
protocol = json.loads((record / "protocol.json").read_text(encoding="utf-8"))
ledger = json.loads((record / "ledger.json").read_text(encoding="utf-8"))
attempts = json.loads((record / "attempts.json").read_text(encoding="utf-8"))
adjudication = json.loads((record / "adjudication.json").read_text(encoding="utf-8"))
manifest = json.loads((record / "freeze-manifest.json").read_text(encoding="utf-8"))
approval_path = record / "approval.json"
approved = approval_path.exists()

assert protocol["status_at_freeze"] == "AWAITING_APPROVAL"
assert protocol["runtime_at_freeze"] == "1.18.32"
assert protocol["recommended_option"] == "FRESH_PAIRED_ARMS"
assert protocol["models"] == [
    {"id": "github-copilot/claude-opus-5.5", "variant": "high", "role": "challenger"},
    {"id": "github-copilot/gpt-6.1-sol", "variant": "high", "role": "current"},
]
assert protocol["order"] == [
    "coding-1-opus55", "coding-1-sol61", "coding-2-sol61", "coding-2-opus55",
    "coding-3-opus55", "coding-3-sol61", "gate-1-sol61", "gate-1-opus55",
    "gate-2-opus55", "gate-2-sol61", "gate-3-sol61", "gate-3-opus55",
]
budget = protocol["budget"]
assert budget["ceiling_credits"] == 630
assert budget["reporting_lag_reserve_credits"] == 23.341875
assert budget["probe_admission_credits"] == {"opus55": 16, "sol61": 8}
assert budget["coding_admission_per_attempt_credits"] == {"opus55": 135.6139, "sol61": 30.82167}
assert budget["gate_admission_per_attempt_credits"] == {"opus55": 19.90142, "sol61": 7.808}
assert budget["arm_stop_threshold_credits"] == {"opus55": 482.54596, "sol61": 123.88901}
assert budget["admission_total_credits"] == 606.43497
assert budget["protected_total_credits"] == 629.776845
assert protocol["alternative_option"]["id"] == "HISTORICAL_SOL_CONTROL"
assert protocol["alternative_option"]["equal_budget"] is False
assert protocol["alternative_option"]["contemporaneous"] is False
assert protocol["alternative_option"]["ceiling_credits"] == 510
assert protocol["automatic_routing_change"] is False
if not approved:
    assert ledger == {"caps": {"build_opus55": 482.54596, "build_sol61": 123.88901}, "entries": []}
    assert attempts == {"status": "AWAITING_APPROVAL", "attempts": []}
    assert adjudication["status"] == "AWAITING_APPROVAL"
assert adjudication["routing_changed"] is False
assert set(adjudication["preregistered_outcomes"]) == {
    "OPUS55_CREDIBLE_BUILD_CANDIDATE", "KEEP_CURRENT_SOL61",
    "BOTH_PASS_NO_CLEAR_WINNER", "INVALID_OR_INCOMPLETE",
}

assert (record / "coding-prompt.txt").read_bytes() == (eval_root / "records/gpt61-sol-build-screening/coding-prompt.txt").read_bytes()
assert (record / "gate-prompt.txt").read_bytes() == (eval_root / "records/gpt61-sol-build-screening/gate-prompt.txt").read_bytes()

assert manifest["status"] == "PRE_DISPATCH_FREEZE"
listed = {item["path"] for item in manifest["files"]}
required = {
    "records/opus55-gpt61-build-quality-screening/protocol.json",
    "records/opus55-gpt61-build-quality-screening/coding-prompt.txt",
    "records/opus55-gpt61-build-quality-screening/gate-prompt.txt",
    "records/opus55-gpt61-build-quality-screening/run-screening.sh",
    "records/opus55-gpt61-build-quality-screening/ledger.json",
    "records/opus55-gpt61-build-quality-screening/attempts.json",
    "records/opus55-gpt61-build-quality-screening/adjudication.json",
    "records/opus55-gpt61-build-quality-screening/config/build-isolation.json",
    "records/opus55-gpt61-build-quality-screening/verify-results.sh",
    "records/opus55-gpt61-build-quality-screening/catalog-snapshot.json",
    "runtime/opencode-v1-adapter/capped-opencode.sh",
    "runtime/opencode-v1-adapter/dispatch-fixture.sh",
    "runtime/opencode-v1-adapter/budget-ledger.sh",
    "runtime/opencode-v1-adapter/provenance.sh",
    "runtime/opencode-v1-adapter/classify-capability-failure.sh",
    "runtime/opencode-v1-adapter/verify-freeze-manifest.sh",
    "runtime/opencode-v1-adapter/capture-tree-patch.sh",
    "records/opus55-reviewer-screening/capability-prompt.txt",
    "records/astra-build-followup/oracle.sh",
    "records/sol-build/empty-path-check.sh",
    "fixtures/build-workloads/build-feature/fixture.json",
    "fixtures/build-workloads/build-feature/task.md",
    "fixtures/build-workloads/build-feature/oracle.sh",
    "fixtures/build-workloads/build-feature/snapshot/README.md",
    "fixtures/build-workloads/build-feature/snapshot/lib/strings.sh",
    "fixtures/build-workloads/build-feature/snapshot/tests/acceptance.sh",
    "fixtures/build-workloads/build-feature/snapshot/tests/regression.sh",
    "records/astra-build-followup/base-snapshot/environments/linux/install.sh",
    "records/astra-build-followup/base-snapshot/tests/install.sh",
    "records/astra-build-followup/base-snapshot/instructions/adapters/claude-code/CLAUDE.md",
}
assert required <= listed
for item in manifest["files"]:
    path = eval_root / item["path"]
    assert path.is_file(), item["path"]
    if not (approved and item.get("mutable_after_dispatch")):
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"], item["path"]
if approved:
    approval = json.loads(approval_path.read_text(encoding="utf-8"))
    assert approval == {
        "experiment_id": "opus55-gpt61-build-quality-screening-20261003",
        "status": "APPROVED_FOR_DISPATCH",
        "approved_ceiling_credits": 630,
        "execution_option": "FRESH_PAIRED_ARMS",
        "freeze_manifest_sha256": hashlib.sha256((record / "freeze-manifest.json").read_bytes()).hexdigest(),
    }
PY

fake=$(mktemp)
trap 'rm -f "$fake"' EXIT
printf '#!/usr/bin/env bash\nprintf "model dispatch unexpectedly reached\\n" >&2\nexit 99\n' >"$fake"
chmod +x "$fake"
set +e
output=$(EVAL_APPROVAL_FILE="$record/.test-no-approval" OPENCODE_BIN="$fake" bash "$record/run-screening.sh" 2>&1)
status=$?
set -e
assert_eq 3 "$status" "frozen Build runner must refuse dispatch"
assert_contains "$output" "AWAITING_APPROVAL"
if [[ ! -f "$record/approval.json" ]]; then
  [[ ! -e "$record/runs" && ! -e "$record/capability" ]] || fail "frozen Build runner created dispatch output"
fi

bad_approval=$(mktemp)
trap 'rm -f "$bad_approval" "$fake"' EXIT
printf '{"experiment_id":"wrong","status":"APPROVED_FOR_DISPATCH","approved_ceiling_credits":630,"execution_option":"FRESH_PAIRED_ARMS","freeze_manifest_sha256":"wrong"}\n' >"$bad_approval"
set +e
bad_output=$(EVAL_APPROVAL_FILE="$bad_approval" OPENCODE_BIN="$fake" bash "$record/run-screening.sh" 2>&1)
bad_status=$?
set -e
assert_eq 3 "$bad_status" "mismatched Build approval must refuse dispatch"
assert_contains "$bad_output" "approval record does not match"

printf 'PASS: Build quality protocol is frozen and non-dispatchable\n'
