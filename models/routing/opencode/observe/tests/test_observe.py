#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import runpy


CANARY = "PROPRIETARY_CANARY_6f3b9f"
EPOCH = 1791100000000
HERE = Path(__file__).resolve().parent
OBSERVE = HERE.parent / "observe"
MANIFEST = HERE.parent.parent / "eval" / "manifests" / "current-routing-targets.json"


def schema(db):
    db.executescript(
        """
        CREATE TABLE session (
          id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT, version TEXT,
          title TEXT, agent TEXT, model TEXT, time_created INTEGER, time_updated INTEGER
        );
        CREATE TABLE message (
          id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER,
          time_updated INTEGER, data TEXT
        );
        CREATE TABLE part (
          id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT,
          time_created INTEGER, time_updated INTEGER, data TEXT
        );
        """
    )


def add_session(db, sid, root, agent="build", model="github-copilot/gpt-6.1-sol", parent=None, start=1):
    start = EPOCH + start if start < EPOCH else start
    provider, model_id = model.split("/", 1)
    variants = {"build": "high", "reviewer": "high", "expert": "xhigh", "breakglass": "max"}
    stored_model = json.dumps({"providerID": provider, "id": model_id, "variant": variants.get(agent, "medium")})
    db.execute(
        "INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?)",
        (sid, parent, str(root), "1.18.32", "Private " + CANARY, agent, stored_model, start, start + 100),
    )


def add_message(db, sid, mid, when, role, agent="build", provider="github-copilot", model="gpt-6.1-sol", variant="high", error=None):
    when = EPOCH + when if when < EPOCH else when
    data = {"role": role, "agent": agent, "time": {"created": when}}
    if role == "user":
        data["model"] = {"providerID": provider, "modelID": model, "variant": variant}
    else:
        data.update({"providerID": provider, "modelID": model, "variant": variant, "mode": agent})
        if error:
            data["error"] = error
    db.execute("INSERT INTO message VALUES (?,?,?,?,?)", (mid, sid, when, when, json.dumps(data)))


def add_part(db, sid, mid, pid, when, data):
    when = EPOCH + when if when < EPOCH else when
    db.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", (pid, mid, sid, when, when, json.dumps(data)))


def add_text(db, sid, mid, when, text):
    add_part(db, sid, mid, mid + "_text", when, {"type": "text", "text": text})


def add_skill(db, sid, mid, when, name):
    add_part(db, sid, mid, mid + "_skill", when, {"type": "tool", "tool": "skill", "state": {"status": "completed", "input": {"name": name}, "output": CANARY}})


def add_edit(db, sid, mid, when, relative, change="update"):
    add_part(
        db, sid, mid, mid + "_edit_" + str(when), when,
        {"type": "tool", "tool": "apply_patch", "state": {
            "status": "completed", "input": {"patchText": CANARY}, "output": CANARY,
            "metadata": {"diff": CANARY, "files": [{
                "filePath": "/private/" + CANARY, "relativePath": relative,
                "type": change, "patch": CANARY, "additions": 1, "deletions": 1,
            }]},
        }},
    )


def add_denied_edit(db, sid, mid, when, relative):
    add_part(db, sid, mid, mid + "_denied", when, {"type": "tool", "tool": "apply_patch", "state": {
        "status": "error", "input": {"patchText": CANARY}, "error": CANARY,
        "metadata": {"files": [{"relativePath": relative, "type": "update", "patch": CANARY}]},
    }})


def add_task(db, sid, mid, when, subagent, child):
    add_part(db, sid, mid, mid + "_task", when, {"type": "tool", "tool": "task", "state": {
        "status": "completed", "input": {"subagent_type": subagent, "prompt": CANARY},
        "output": CANARY, "metadata": {"sessionId": child, "parentSessionId": sid},
    }})


def add_question_answer(db, sid, mid, when, answer):
    add_part(db, sid, mid, mid + "_question", when, {"type": "tool", "tool": "question", "state": {
        "status": "completed", "input": {"questions": CANARY}, "output": CANARY,
        "metadata": {"answers": [[answer, CANARY]]},
    }})


def add_snapshot_patch(db, sid, mid, when, relative):
    add_part(db, sid, mid, mid + "_snapshot", when, {"type": "patch", "hash": CANARY, "files": [relative]})


def build_fixture(base):
    repo = base / "work" / "repo"
    repo.mkdir(parents=True)
    (repo / ".git").mkdir()
    db_path = base / "opencode.db"
    db = sqlite3.connect(db_path)
    schema(db)

    # Aligned route and respected gate.
    add_session(db, "ses_aligned", repo, start=1000)
    add_message(db, "ses_aligned", "a_u1", 1001, "user")
    add_text(db, "ses_aligned", "a_u1", 1001, "Build this " + CANARY)
    add_message(db, "ses_aligned", "a_a1", 1002, "assistant")
    add_skill(db, "ses_aligned", "a_a1", 1002, "brainstorming")
    add_message(db, "ses_aligned", "a_u2", 1003, "user")
    add_text(db, "ses_aligned", "a_u2", 1003, "Approved, proceed " + CANARY)
    add_message(db, "ses_aligned", "a_a2", 1004, "assistant")
    add_edit(db, "ses_aligned", "a_a2", 1004, "src/aligned.py")

    # Production routing mismatch.
    add_session(db, "ses_mismatch", repo, model="github-copilot/gpt-6-luna", start=2000)
    add_message(db, "ses_mismatch", "m_u", 2001, "user", model="gpt-6-luna", variant="low")
    add_text(db, "ses_mismatch", "m_u", 2001, CANARY)
    add_message(db, "ses_mismatch", "m_a", 2002, "assistant", model="gpt-6-luna", variant="low")
    add_text(db, "ses_mismatch", "m_a", 2002, CANARY)

    # Eval dispatcher mismatch in a real worktree, excluded through retained evidence.
    add_session(db, "ses_Dispatch123", repo, model="openai/gpt-6-astra", start=3000)
    add_message(db, "ses_Dispatch123", "d_u", 3001, "user", provider="openai", model="gpt-6-astra", variant="xhigh")
    add_text(db, "ses_Dispatch123", "d_u", 3001, CANARY)
    add_message(db, "ses_Dispatch123", "d_a", 3002, "assistant", provider="openai", model="gpt-6-astra", variant="xhigh")

    # Provider error.
    add_session(db, "ses_error", repo, start=4000)
    add_message(db, "ses_error", "e_u", 4001, "user")
    add_text(db, "ses_error", "e_u", 4001, CANARY)
    add_message(db, "ses_error", "e_a", 4002, "assistant", error={"name": "APIError", "data": {"message": CANARY + " rate limit", "statusCode": 429, "isRetryable": True, "responseBody": CANARY}})

    # Gate skipped.
    add_session(db, "ses_gate_skip", repo, start=5000)
    add_message(db, "ses_gate_skip", "g_u", 5001, "user")
    add_text(db, "ses_gate_skip", "g_u", 5001, CANARY)
    add_message(db, "ses_gate_skip", "g_a", 5002, "assistant")
    add_skill(db, "ses_gate_skip", "g_a", 5002, "brainstorming")
    add_edit(db, "ses_gate_skip", "g_a", 5003, "src/gate.py")

    # Existing shared test modified.
    add_session(db, "ses_scope", repo, start=6000)
    add_message(db, "ses_scope", "s_u", 6001, "user")
    add_text(db, "ses_scope", "s_u", 6001, CANARY)
    add_message(db, "ses_scope", "s_a", 6002, "assistant")
    add_edit(db, "ses_scope", "s_a", 6002, "tests/conftest.py")

    # Rework: edit, human correction, edit same path.
    add_session(db, "ses_rework", repo, start=7000)
    add_message(db, "ses_rework", "r_u1", 7001, "user")
    add_text(db, "ses_rework", "r_u1", 7001, CANARY)
    add_message(db, "ses_rework", "r_a1", 7002, "assistant")
    add_edit(db, "ses_rework", "r_a1", 7002, "src/rework.py")
    add_message(db, "ses_rework", "r_u2", 7003, "user")
    add_text(db, "ses_rework", "r_u2", 7003, "No, fix it " + CANARY)
    add_message(db, "ses_rework", "r_a2", 7004, "assistant")
    add_edit(db, "ses_rework", "r_a2", 7004, "src/rework.py")

    # Parent/child reviewer escalation.
    add_session(db, "ses_parent", repo, start=8000)
    add_message(db, "ses_parent", "p_u", 8001, "user")
    add_text(db, "ses_parent", "p_u", 8001, CANARY)
    add_message(db, "ses_parent", "p_a", 8002, "assistant")
    add_task(db, "ses_parent", "p_a", 8002, "reviewer", "ses_child")
    add_session(db, "ses_child", repo, agent="reviewer", model="github-copilot/claude-opus-5.5", parent="ses_parent", start=8003)
    add_message(db, "ses_child", "c_a", 8004, "assistant", agent="reviewer", model="gpt-6-luna", variant="low")
    add_text(db, "ses_child", "c_a", 8004, CANARY)
    add_part(db, "ses_child", "c_a", "c_reasoning", 8004, {"type": "reasoning", "text": CANARY})
    add_session(db, "ses_breakglass_child", repo, agent="breakglass", model="openai/gpt-6.1-sol", parent="ses_parent", start=8005)
    add_message(db, "ses_breakglass_child", "b_a", 8006, "assistant", agent="breakglass", provider="openai", model="gpt-6.1-sol", variant="max")

    # Question-tool approval and a snapshot-detected edit remain gate-adherent.
    add_session(db, "ses_question_gate", repo, start=8500)
    add_message(db, "ses_question_gate", "q_u", 8501, "user")
    add_text(db, "ses_question_gate", "q_u", 8501, CANARY)
    add_message(db, "ses_question_gate", "q_a1", 8502, "assistant")
    add_skill(db, "ses_question_gate", "q_a1", 8502, "brainstorming")
    add_question_answer(db, "ses_question_gate", "q_a1", 8503, "Approved")
    add_message(db, "ses_question_gate", "q_a2", 8504, "assistant")
    add_snapshot_patch(db, "ses_question_gate", "q_a2", 8504, "src/question-approved.py")

    # Assistant asking to proceed cannot approve itself; denied edits do not count.
    add_session(db, "ses_self_approval", repo, start=8600)
    add_message(db, "ses_self_approval", "sa_u", 8601, "user")
    add_text(db, "ses_self_approval", "sa_u", 8601, CANARY)
    add_message(db, "ses_self_approval", "sa_a", 8602, "assistant")
    add_skill(db, "ses_self_approval", "sa_a", 8602, "brainstorming")
    add_text(db, "ses_self_approval", "sa_a", 8602, "Shall I proceed? " + CANARY)
    add_denied_edit(db, "ses_self_approval", "sa_a", 8603, "src/denied.py")
    add_message(db, "ses_self_approval", "sa_a2", 8604, "assistant")
    add_edit(db, "ses_self_approval", "sa_a2", 8604, "src/self-approved.py")

    # Approval remains latched across later user instructions.
    add_session(db, "ses_latched", repo, start=8700)
    add_message(db, "ses_latched", "l_u1", 8701, "user")
    add_text(db, "ses_latched", "l_u1", 8701, CANARY)
    add_message(db, "ses_latched", "l_a1", 8702, "assistant")
    add_skill(db, "ses_latched", "l_a1", 8702, "brainstorming")
    add_message(db, "ses_latched", "l_u2", 8703, "user")
    add_text(db, "ses_latched", "l_u2", 8703, "Approved")
    add_message(db, "ses_latched", "l_a2", 8704, "assistant")
    add_edit(db, "ses_latched", "l_a2", 8704, "src/latched.py")
    add_message(db, "ses_latched", "l_u3", 8705, "user")
    add_text(db, "ses_latched", "l_u3", 8705, "Also add tests")
    add_message(db, "ses_latched", "l_a3", 8706, "assistant")
    add_edit(db, "ses_latched", "l_a3", 8706, "src/latched.py")

    # Production directory can disappear after worktree cleanup.
    add_session(db, "ses_removed_worktree", base / "removed-production", start=8800)
    add_message(db, "ses_removed_worktree", "rw_u", 8801, "user")
    add_text(db, "ses_removed_worktree", "rw_u", 8801, CANARY)
    add_message(db, "ses_removed_worktree", "rw_a", 8802, "assistant")

    # One identifiable OpenSpec change with an edit outside its declared files.
    change = repo / "openspec" / "changes" / "observe-me"
    change.mkdir(parents=True)
    (change / "tasks.md").write_text("Update `src/allowed.py` " + CANARY, encoding="utf-8")
    add_session(db, "ses_openspec", repo, start=9000)
    add_message(db, "ses_openspec", "o_u", 9001, "user")
    add_text(db, "ses_openspec", "o_u", 9001, "Continue change observe-me " + CANARY)
    add_message(db, "ses_openspec", "o_a", 9002, "assistant")
    add_edit(db, "ses_openspec", "o_a", 9002, "src/not-declared.py")
    db.commit()
    db.close()

    logs = base / "logs"
    logs.mkdir()
    (logs / "runtime.log").write_text(
        "\n".join([
            'timestamp=2026-10-04T10:00:00Z level=INFO run=test message=stream providerID=github-copilot modelID=gpt-6-luna session.id=ses_aligned small=true agent=title mode=title',
            'timestamp=2026-10-04T10:00:01Z level=INFO run=test message=stream providerID=openai modelID=gpt-6-astra session.id=ses_Dispatch123 small=true agent=title mode=title',
            'timestamp=2026-10-04T10:00:02Z level=ERROR run=test message="stream error" providerID=github-copilot modelID=gpt-6.1-sol session.id=ses_error small=false agent=build mode=build error.error="' + CANARY + ' 429 rate limit"',
            'timestamp=2026-10-04T10:00:03Z level=INFO run=test message=stream providerID=github-copilot modelID=gpt-6.1-sol session.id=ses_error small=false agent=build mode=build',
        ]) + "\n",
        encoding="utf-8",
    )
    records = base / "eval-records"
    records.mkdir()
    (records / "dispatcher.json").write_text(json.dumps({"session": "ses_Dispatch123", "content": CANARY}), encoding="utf-8")
    return db_path, logs, records


def run(*args):
    if args and args[0] == "report" and "--activation-config" not in args:
        args = (*args, "--activation-config", "")
    return subprocess.run([sys.executable, str(OBSERVE), *args], text=True, capture_output=True)


def main():
    with tempfile.TemporaryDirectory(prefix="observe-test-") as tmp:
        base = Path(tmp)
        db, logs, records = build_fixture(base)
        state = base / "state"
        original_db = db.read_bytes()
        result = run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST), "--format", "json")
        assert result.returncode == 0, result.stderr
        assert db.read_bytes() == original_db
        report = json.loads(result.stdout)
        assert report["coverage"]["opencode_versions"] == ["1.18.32"]
        assert report["session_classes"] == {"eval_dispatcher": 1, "production": 12, "pre_profile": 0}
        assert report["signals"]["routing"] == 3
        assert report["signals"]["escalation"] == 1
        assert report["signals"]["provider_error"] == 1
        assert report["signals"]["gate"] == 2
        assert report["signals"]["scope"] == 2
        assert report["signals"]["rework"] == 2
        assert report["escalations"]["reviewer"] == 1
        assert report["checkpoint"] == {"build_sessions_with_gate": 5, "minimum": 15, "maximum": 20}
        assert {item["reason"] for item in report["review"]} >= {
            "root_model_differs", "request_route_differs", "breakglass_child", "rate_limit", "edit_before_approval",
            "shared_test_or_setup_modified", "outside_active_openspec_change",
            "same_file_modified_after_user_turn",
        }
        review_paths = {path for item in report["review"] for path in item.get("paths", [])}
        assert review_paths == {
            "src/gate.py", "src/self-approved.py", "src/latched.py",
            "tests/conftest.py", "src/rework.py", "src/not-declared.py",
        }
        assert report["agent_signals"]["build"] == {
            "gate": 2, "provider_error": 1, "rework": 2, "routing": 2, "scope": 2,
        }
        assert report["agent_signals"]["reviewer"] == {"routing": 1}
        assert report["agent_signals"]["breakglass"] == {"escalation": 1}
        assert report["provider_errors"] == {"github-copilot": {"build": {"rate_limit": 1}}}
        assert report["provider_retries"] == {"github-copilot": {"build": 1}}
        assert any(item == {
            "agent": "title", "provider": "github-copilot", "model": "gpt-6-luna",
            "variant": None, "requests": 1,
        } for item in report["routing_requests"])

        serialized = result.stdout + result.stderr
        for path in state.rglob("*"):
            if path.is_file():
                serialized += path.read_text(encoding="utf-8", errors="replace")
        assert CANARY not in serialized
        assert "ses_" not in serialized
        assert str(base) not in serialized

        text = run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST))
        assert "To review:" in text.stdout and "root_model_differs" in text.stdout

        routing = next(i for i in report["review"] if i["reason"] == "root_model_differs")
        confirm = run("review", "confirm", routing["session"], "routing", routing["reason"], "--state-dir", str(state), "--note", "confirmed locally")
        assert confirm.returncode == 0, confirm.stderr
        rerun = run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST), "--format", "json")
        rerun_report = json.loads(rerun.stdout)
        assert rerun_report["triggers"]["routing_mismatch"] is True
        same_session_other_reasons = [i for i in rerun_report["review"] if i["session"] == routing["session"] and i["signal"] == "routing" and i["reason"] != routing["reason"]]
        assert same_session_other_reasons and all(item["status"] == "pending" for item in same_session_other_reasons)

        error = next(i for i in report["review"] if i["signal"] == "provider_error")
        gate = next(i for i in report["review"] if i["signal"] == "gate")
        rework = next(i for i in report["review"] if i["signal"] == "rework")
        assert run("review", "confirm", error["session"], "provider_error", error["reason"], "--state-dir", str(state)).returncode == 0
        assert run("review", "confirm", gate["session"], "gate", gate["reason"], "--state-dir", str(state)).returncode == 0
        assert run("review", "confirm", rework["session"], "rework", rework["reason"], "--rollback", "--state-dir", str(state)).returncode == 0
        one_each = json.loads(run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST), "--format", "json").stdout)
        assert one_each["triggers"]["provider_errors_recurring"] is False
        assert one_each["triggers"]["gates_skipped"] is False
        assert one_each["triggers"]["rollback_required"] is True

        fixture_db = sqlite3.connect(db)
        add_session(fixture_db, "ses_error_second", base / "work" / "repo", start=10000)
        add_message(fixture_db, "ses_error_second", "e2_u", 10001, "user")
        add_text(fixture_db, "ses_error_second", "e2_u", 10001, CANARY)
        add_message(fixture_db, "ses_error_second", "e2_a", 10002, "assistant", error={"name": "APIError", "data": {"message": CANARY, "statusCode": 429, "isRetryable": True}})
        add_session(fixture_db, "ses_gate_second", base / "work" / "repo", start=11000)
        add_message(fixture_db, "ses_gate_second", "g2_u", 11001, "user")
        add_text(fixture_db, "ses_gate_second", "g2_u", 11001, CANARY)
        add_message(fixture_db, "ses_gate_second", "g2_a", 11002, "assistant")
        add_skill(fixture_db, "ses_gate_second", "g2_a", 11002, "brainstorming")
        add_edit(fixture_db, "ses_gate_second", "g2_a", 11003, "src/gate-second.py")
        fixture_db.commit()
        fixture_db.close()
        with_second = json.loads(run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST), "--format", "json").stdout)
        second_error = next(i for i in with_second["review"] if i["signal"] == "provider_error" and i["status"] == "pending")
        second_gate = next(i for i in with_second["review"] if i["signal"] == "gate" and i["status"] == "pending")
        assert run("review", "confirm", second_error["session"], "provider_error", second_error["reason"], "--state-dir", str(state)).returncode == 0
        assert run("review", "confirm", second_gate["session"], "gate", second_gate["reason"], "--state-dir", str(state)).returncode == 0
        threshold = json.loads(run("report", "--since", "1970-01-01", "--db", str(db), "--log-dir", str(logs), "--eval-records", str(records), "--state-dir", str(state), "--manifest", str(MANIFEST), "--format", "json").stdout)
        assert threshold["triggers"]["provider_errors_recurring"] is True
        assert threshold["triggers"]["gates_skipped"] is True

        locate = run("locate", routing["session"], "--db", str(db), "--state-dir", str(state))
        assert locate.stdout.strip() == "ses_mismatch"
        assert not any("ses_mismatch" in p.read_text(encoding="utf-8", errors="replace") for p in state.rglob("*") if p.is_file())

        source = OBSERVE.read_text(encoding="utf-8")
        for forbidden in ("import subprocess", "import socket", "import urllib", "import http"):
            assert forbidden not in source

        inside = run("report", "--since", "1970-01-01", "--db", str(db), "--state-dir", str(base / "work" / "repo" / "state"), "--manifest", str(MANIFEST))
        assert inside.returncode == 2
        assert CANARY not in inside.stderr
        raw_review = run("review", "confirm", "ses_raw", "routing", "root_model_differs", "--state-dir", str(state))
        assert raw_review.returncode == 2
        assert "ses_raw" not in (state / "review.jsonl").read_text(encoding="utf-8")

        module = runpy.run_path(str(OBSERVE))
        classify = module["classify_gate_turn"]
        frozen = HERE.parent.parent / "eval" / "records" / "opus55-gpt61-build-quality-screening" / "runs"
        for expected_path in sorted(frozen.glob("*-gate-*/gate-classification.txt")):
            run_dir = expected_path.parent
            response = (run_dir / "dispatch" / "response.txt").read_text(encoding="utf-8", errors="replace")
            has_edits = bool((run_dir / "work-product.patch").read_bytes())
            assert classify(response, has_edits) == expected_path.read_text(encoding="utf-8").strip()

    print("PASS: routing observation signals and privacy boundary")


if __name__ == "__main__":
    main()
