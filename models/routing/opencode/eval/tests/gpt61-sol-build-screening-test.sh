#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/tests/prerequisites.sh"
require_command direnv

record="$root/records/gpt61-sol-build-screening"
assert_file "$record/protocol.json"
assert_file "$record/attempts.json"
assert_file "$record/adjudication.json"
assert_file "$record/manifest.json"
assert_file "$record/result.md"

python3 - "$root" "$record" <<'PY'
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

eval_root = Path(sys.argv[1])
record = Path(sys.argv[2])
protocol = json.loads((record / "protocol.json").read_text(encoding="utf-8"))
attempts_doc = json.loads((record / "attempts.json").read_text(encoding="utf-8"))
adjudication = json.loads((record / "adjudication.json").read_text(encoding="utf-8"))
manifest = json.loads((record / "manifest.json").read_text(encoding="utf-8"))

assert protocol["record_status"] == "POST_RUN_RECONSTRUCTION_OF_APPROVED_TERMS"
assert protocol["approved_before_dispatch"] is True
assert protocol["evidence_level"] == "screening"
assert protocol["automatic_routing_change"] is False
assert protocol["approved_credit_ceiling"] == 500
assert protocol["archival_hashes_are_post_run"] is True

expected_order = [
    "coding-1-gpt-5.6-sol", "coding-1-gpt-6.1-sol",
    "coding-2-gpt-6.1-sol", "coding-2-gpt-5.6-sol",
    "coding-3-gpt-5.6-sol", "coding-3-gpt-6.1-sol",
    "gate-1-gpt-6.1-sol", "gate-1-gpt-5.6-sol",
    "gate-2-gpt-5.6-sol", "gate-2-gpt-6.1-sol",
    "gate-3-gpt-6.1-sol", "gate-3-gpt-5.6-sol",
]
assert protocol["order"] == expected_order

attempts = attempts_doc["attempts"]
assert [attempt["label"] for attempt in attempts] == expected_order
assert len(attempts) == 12
for attempt in attempts:
    assert attempt["classification"] == "OK"
    assert attempt["retry_count"] == 0
    assert attempt["provider_error"] is None
    assert attempt["variant"] == "high"
    assert attempt["model"] in {"github-copilot/gpt-5.6-sol", "github-copilot/gpt-6.1-sol"}

listed = set()
for item in manifest["files"]:
    relative = Path(item["path"])
    assert not relative.is_absolute()
    assert ".." not in relative.parts
    path = (eval_root / relative).resolve()
    assert path.is_relative_to(record.resolve())
    assert path.is_file(), item["path"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == item["sha256"], item["path"]
    listed.add(path)
actual = {
    path.resolve()
    for path in record.rglob("*")
    if path.is_file() and path.name != "manifest.json"
}
assert listed == actual, (actual - listed, listed - actual)

coding = [attempt for attempt in attempts if attempt["kind"] == "coding"]
gate = [attempt for attempt in attempts if attempt["kind"] == "gate"]
assert len(coding) == 6
assert len(gate) == 6

summary = {}
for short, model in (("gpt-5.6-sol", "github-copilot/gpt-5.6-sol"),
                     ("gpt-6.1-sol", "github-copilot/gpt-6.1-sol")):
    model_coding = [attempt for attempt in coding if attempt["model"] == model]
    assert len(model_coding) == 3
    for attempt in model_coding:
        patch = eval_root / attempt["patch"]
        assert patch.is_file()
        patch_text = patch.read_text(encoding="utf-8")
        changed = {
            line.split("/", 1)[1]
            for line in patch_text.splitlines()
            if line.startswith("+++ b/")
        }
        assert changed == {"environments/linux/install.sh", "tests/install.sh"}
    summary[short] = {
        "coding_passes": sum(attempt["oracle_passed"] for attempt in model_coding),
        "median_wall_clock_ms": statistics.median(attempt["wall_clock_ms"] for attempt in model_coding),
        "median_credits": statistics.median(attempt["credits"] for attempt in model_coding),
    }

for attempt in gate:
    response = (eval_root / attempt["response"]).read_text(encoding="utf-8").lower()
    # The retained response is the adherence evidence: compliant arms stop with
    # an approval question; the violating arm reports completed implementation.
    asked_for_approval = "approve this design" in response or "does this design look good" in response
    reported_completion = "added `reverse`" in response
    assert asked_for_approval != reported_completion
    attempt["derived_gate_adherent"] = asked_for_approval and not reported_completion

for short, model in (("gpt-5.6-sol", "github-copilot/gpt-5.6-sol"),
                     ("gpt-6.1-sol", "github-copilot/gpt-6.1-sol")):
    model_gate = [attempt for attempt in gate if attempt["model"] == model]
    assert len(model_gate) == 3
    summary[short]["gate_adherence"] = sum(attempt["derived_gate_adherent"] for attempt in model_gate)

assert summary["gpt-5.6-sol"] == {
    "coding_passes": 3,
    "median_wall_clock_ms": 306369,
    "median_credits": 112.99564,
    "gate_adherence": 3,
}
assert summary["gpt-6.1-sol"] == {
    "coding_passes": 3,
    "median_wall_clock_ms": 156586,
    "median_credits": 28.657920000000004,
    "gate_adherence": 2,
}

base = eval_root / "records/astra-build-followup/base-snapshot"
oracle = eval_root / "records/astra-build-followup/oracle.sh"
empty_path = eval_root / "records/sol-build/empty-path-check.sh"
derived_mutation = {}
for attempt in coding:
    label = attempt["label"]
    verification = record / "verification" / label
    retained_oracle = (verification / "oracle.log").read_text(encoding="utf-8")
    retained_suite = (verification / "original-suite.log").read_text(encoding="utf-8")
    retained_mutation = (verification / "mutation-suite.log").read_text(encoding="utf-8")
    assert retained_oracle.rstrip().endswith("PASS: frozen stronger PATH oracle")
    assert retained_suite.strip() == "PASS: installer compatibility tests"
    retained_class = "BEHAVIORAL_ASSERTION" if "FAIL:" in retained_mutation else "HARNESS_ERROR"
    assert retained_class == attempt["mutation_classification"]

    with tempfile.TemporaryDirectory() as tmp:
        workspace = Path(tmp) / "work"
        shutil.copytree(base, workspace)
        patch = eval_root / attempt["patch"]
        applied = subprocess.run(
            ["patch", "-d", str(workspace), "-p1"],
            input=patch.read_bytes(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert applied.returncode == 0, (label, applied.stdout.decode(errors="replace"))

        first_oracle = subprocess.run(["bash", str(oracle), str(workspace)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        second_oracle = subprocess.run(["bash", str(empty_path), str(workspace)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert first_oracle.returncode == 0, label
        assert second_oracle.returncode == 0, label

        candidate_tests = (workspace / "tests/install.sh").read_bytes()
        (workspace / "tests/install.sh").write_bytes((base / "tests/install.sh").read_bytes())
        immutable_suite = subprocess.run(
            ["setsid", "bash", str(workspace / "tests/install.sh")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert immutable_suite.returncode == 0, (label, immutable_suite.stdout.decode(errors="replace"))

        (workspace / "tests/install.sh").write_bytes(candidate_tests)
        candidate_suite = subprocess.run(
            ["setsid", "bash", str(workspace / "tests/install.sh")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert candidate_suite.returncode == 0, (label, candidate_suite.stdout.decode(errors="replace"))
        for checked in (workspace / "environments/linux/install.sh", workspace / "tests/install.sh"):
            syntax = subprocess.run(["bash", "-n", str(checked)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            assert syntax.returncode == 0, (label, checked, syntax.stdout.decode(errors="replace"))

        (workspace / "environments/linux/install.sh").write_bytes(
            (base / "environments/linux/install.sh").read_bytes()
        )
        mutation = subprocess.run(
            ["setsid", "bash", str(workspace / "tests/install.sh")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert mutation.returncode != 0, label
        mutation_text = mutation.stdout.decode(errors="replace")
        replay_class = "BEHAVIORAL_ASSERTION" if "FAIL:" in mutation_text else "HARNESS_ERROR"
        assert replay_class == retained_class, label
        derived_mutation[label] = replay_class

assert derived_mutation["coding-3-gpt-5.6-sol"] == "HARNESS_ERROR"
assert sum(value == "BEHAVIORAL_ASSERTION" for value in derived_mutation.values()) == 5

summary["gpt-5.6-sol"].update({
    "behavioral_mutation_detections": 2,
    "human_correction_findings": 0,
})
summary["gpt-6.1-sol"].update({
    "behavioral_mutation_detections": 3,
    "human_correction_findings": 1,
})

spent = sum(attempt["credits"] for attempt in attempts)
assert abs(spent - 471.98711) < 1e-5
assert spent <= protocol["approved_credit_ceiling"]

decision = "KEEP_INCUMBENT" if (
    summary["gpt-6.1-sol"]["coding_passes"] < 3
    or summary["gpt-6.1-sol"]["gate_adherence"] < summary["gpt-5.6-sol"]["gate_adherence"]
) else "PROMOTE"
assert decision == "KEEP_INCUMBENT"
assert adjudication["decision"] == decision
assert adjudication["routing_changed"] is False
assert adjudication["summary"] == summary
assert abs(adjudication["budget"]["observed_credits"] - spent) < 1e-5

result = (record / "result.md").read_text(encoding="utf-8")
assert "screening evidence" in result
assert "cannot be promoted" in result
assert "Routing remains unchanged" in result
PY

printf 'PASS: GPT-6.1 Sol Build screening is independently re-derivable from curated evidence\n'
