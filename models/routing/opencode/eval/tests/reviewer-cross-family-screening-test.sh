#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
record="$root/records/reviewer-cross-family-screening"

assert_file "$record/protocol.md"
assert_file "$record/config/freeze.json"
assert_file "$record/config/astra.json"
assert_file "$record/config/sol61.json"
assert_file "$record/config/capability-isolation.json"
assert_file "$record/config/reviewer-prompt.md"
assert_file "$record/run-screening.sh"
assert_file "$record/normalize-results.sh"
assert_file "$record/ledger.json"
assert_file "$record/adjudication.json"
assert_file "$record/freeze-manifest.json"

python3 - "$root" "$record" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

eval_root = Path(sys.argv[1])
record = Path(sys.argv[2])
freeze = json.loads((record / "config/freeze.json").read_text(encoding="utf-8"))
ledger = json.loads((record / "ledger.json").read_text(encoding="utf-8"))
adjudication = json.loads((record / "adjudication.json").read_text(encoding="utf-8"))
manifest = json.loads((record / "freeze-manifest.json").read_text(encoding="utf-8"))
approval_path = record / "approval.json"
approved = approval_path.exists()

assert freeze["status_at_freeze"] == "AWAITING_APPROVAL"
assert freeze["runtime_at_freeze"] == "1.18.32"
assert freeze["historical_reference"]["runtime_version"] == "1.18.31"
assert freeze["historical_reference"]["result"] == {
    "gate": "BLOCK", "detected": 3, "missed": 1, "ambiguous": 1,
    "clean_material_findings": 0,
}
assert freeze["models"] == {
    "astra": {"model": "github-copilot/gpt-6-astra", "variant": "xhigh"},
    "sol61": {"model": "github-copilot/gpt-6.1-sol", "variant": "high"},
}
assert freeze["order"] == [
    "clean-astra", "clean-sol61", "R-API-sol61", "R-API-astra",
    "R-AUTH-astra", "R-AUTH-sol61", "R-BOUNDARY-sol61", "R-BOUNDARY-astra",
    "R-CONCURRENCY-astra", "R-CONCURRENCY-sol61", "R-ERROR-sol61", "R-ERROR-astra",
]
budget = freeze["budget"]
assert budget == {
    "ceiling_credits": 805,
    "reporting_lag_reserve_credits": 23.341875,
    "probe_admission_credits": {"astra": 50, "sol61": 10},
    "workload_admission_per_call_credits": {"astra": 100, "sol61": 20},
    "arm_stop_threshold_credits": {"astra": 650, "sol61": 130},
    "reporting_lag_reserve_by_arm_credits": {"astra": 15, "sol61": 8.341875},
    "admission_total_credits": 780,
    "protected_total_credits": 803.341875,
}
if not approved:
    assert ledger == {"caps": {"reviewer_astra": 650, "reviewer_sol61": 130}, "entries": []}
    assert adjudication["status"] == "AWAITING_APPROVAL"
assert adjudication["routing_changed"] is False
assert set(adjudication["preregistered_outcomes"]) == {
    "NO_CHALLENGER_PASSES_THRESHOLD", "ASTRA_PASSES_THRESHOLD",
    "SOL61_PASSES_THRESHOLD", "BOTH_PASS_THRESHOLD",
    "CREDIBLE_CANDIDATE_BELOW_THRESHOLD", "INVALID_OR_INCOMPLETE",
}

expected_permission = {
    "edit": "deny", "task": "deny", "external_directory": "deny",
    "webfetch": "deny", "websearch": "deny", "skill": "allow",
    "bash": {"*": "deny", "git status*": "allow", "git diff*": "allow",
             "git log*": "allow", "git show*": "allow"},
}
production = (eval_root.parent / ".opencode/agents/reviewer.md").read_text(encoding="utf-8")
production_body = production.split("---", 2)[2].lstrip("\n")
assert (record / "config/reviewer-prompt.md").read_text(encoding="utf-8") == production_body
for key, name in (("astra", "reviewer-astra"), ("sol61", "reviewer-sol61")):
    config = json.loads((record / f"config/{key}.json").read_text(encoding="utf-8"))
    row = config["agent"][name]
    assert row["mode"] == "primary"
    assert row["model"] == freeze["models"][key]["model"]
    assert row["variant"] == freeze["models"][key]["variant"]
    assert row["temperature"] == 0.1
    assert row["permission"] == expected_permission

assert manifest["status"] == "PRE_DISPATCH_FREEZE"
listed = {item["path"] for item in manifest["files"]}
required = {
    "records/reviewer-cross-family-screening/protocol.md",
    "records/reviewer-cross-family-screening/config/freeze.json",
    "records/reviewer-cross-family-screening/config/astra.json",
    "records/reviewer-cross-family-screening/config/sol61.json",
    "records/reviewer-cross-family-screening/config/capability-isolation.json",
    "records/reviewer-cross-family-screening/config/reviewer-prompt.md",
    "records/reviewer-cross-family-screening/reviewer-request.txt",
    "records/reviewer-cross-family-screening/capability-prompt.txt",
    "records/reviewer-cross-family-screening/run-screening.sh",
    "records/reviewer-cross-family-screening/normalize-results.sh",
    "records/reviewer-cross-family-screening/ledger.json",
    "records/reviewer-cross-family-screening/adjudication.json",
    "records/reviewer-cross-family-screening/score-results.sh",
    "records/reviewer-cross-family-screening/catalog-snapshot.json",
    "runtime/opencode-v1-adapter/capped-opencode.sh",
    "runtime/opencode-v1-adapter/dispatch-fixture.sh",
    "runtime/opencode-v1-adapter/budget-ledger.sh",
    "runtime/opencode-v1-adapter/provenance.sh",
    "runtime/opencode-v1-adapter/classify-capability-failure.sh",
    "runtime/opencode-v1-adapter/verify-freeze-manifest.sh",
    "../.opencode/agents/reviewer.md",
    "fixtures/reviewer-seeded-defects/fixture.json",
    "fixtures/reviewer-seeded-defects/oracle.json",
    "fixtures/reviewer-seeded-defects/clean/api.sh",
    "fixtures/reviewer-seeded-defects/clean/api_contract.sh",
    "fixtures/reviewer-seeded-defects/clean/authorization.sh",
    "fixtures/reviewer-seeded-defects/clean/counter.sh",
    "fixtures/reviewer-seeded-defects/clean/pagination.sh",
    "fixtures/reviewer-seeded-defects/clean/storage.sh",
    "fixtures/reviewer-seeded-defects/clean/ground-truth.json",
    "fixtures/reviewer-seeded-defects/cases/R-API/api.sh",
    "fixtures/reviewer-seeded-defects/cases/R-API/ground-truth.json",
    "fixtures/reviewer-seeded-defects/cases/R-AUTH/authorization.sh",
    "fixtures/reviewer-seeded-defects/cases/R-AUTH/ground-truth.json",
    "fixtures/reviewer-seeded-defects/cases/R-BOUNDARY/pagination.sh",
    "fixtures/reviewer-seeded-defects/cases/R-BOUNDARY/ground-truth.json",
    "fixtures/reviewer-seeded-defects/cases/R-CONCURRENCY/counter.sh",
    "fixtures/reviewer-seeded-defects/cases/R-CONCURRENCY/ground-truth.json",
    "fixtures/reviewer-seeded-defects/cases/R-ERROR/storage.sh",
    "fixtures/reviewer-seeded-defects/cases/R-ERROR/ground-truth.json",
    "scoring/reviewer.sh",
    "scoring/fixture-defect-detectors.sh",
    "records/opus55-reviewer-screening/adjudication.json",
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
        "experiment_id": "reviewer-cross-family-quality-screening-20261003",
        "status": "APPROVED_FOR_DISPATCH",
        "approved_ceiling_credits": 805,
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
assert_eq 3 "$status" "frozen Reviewer runner must refuse dispatch"
assert_contains "$output" "AWAITING_APPROVAL"
if [[ ! -f "$record/approval.json" ]]; then
  [[ ! -e "$record/runs" && ! -e "$record/capability" ]] || fail "frozen Reviewer runner created dispatch output"
fi

bad_approval=$(mktemp)
trap 'rm -f "$bad_approval" "$fake"' EXIT
printf '{"experiment_id":"wrong","status":"APPROVED_FOR_DISPATCH","approved_ceiling_credits":805,"freeze_manifest_sha256":"wrong"}\n' >"$bad_approval"
set +e
bad_output=$(EVAL_APPROVAL_FILE="$bad_approval" OPENCODE_BIN="$fake" bash "$record/run-screening.sh" 2>&1)
bad_status=$?
set -e
assert_eq 3 "$bad_status" "mismatched Reviewer approval must refuse dispatch"
assert_contains "$bad_output" "approval record does not match"

printf 'PASS: Reviewer cross-family protocol is frozen and non-dispatchable\n'
