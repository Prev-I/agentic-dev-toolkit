#!/usr/bin/env python3
"""The 2.x session reader: session_v2 + session_message, never the frozen 1.x tables."""
import json
from pathlib import Path
import runpy
import sqlite3
import tempfile

from test_observe import CANARY, EPOCH, MANIFEST, OBSERVE, run, schema
from test_v2_config import V2_MANIFEST, v2_schema

PROFILE = "1970-01-01T00:00:00Z"
PACKET = "\n".join(f"## {h}\n{CANARY}" for h in (
    "Problem statement", "Context", "Options considered", "Arguments",
    "Risks", "Requesting agent", "Desired output"))


def model(provider="github-copilot", model_id="gpt-6.1-sol", variant="high"):
    return {"providerID": provider, "id": model_id, "variant": variant}


def add_session(db, sid, root, agent="build", stored_model=None, parent=None, start=1, version="2.3.0"):
    start = EPOCH + start
    db.execute("INSERT INTO session_v2 VALUES (?,?,?,?,?,?,?,?,?)",
               (sid, parent, str(root), version, agent,
                json.dumps(stored_model) if stored_model else None, start, start + 100, CANARY))


def add_row(db, sid, mid, when, kind, data, seq=None):
    seq = when * 10 if seq is None else seq
    when = EPOCH + when
    data = {**data, "time": {"created": when}}
    db.execute("INSERT INTO session_message VALUES (?,?,?,?,?,?,?)",
               (mid, sid, kind, seq, when, when, json.dumps(data)))


def user(db, sid, mid, when, text, seq=None):
    add_row(db, sid, mid, when, "user", {"text": text, "files": []}, seq)


def assistant(db, sid, mid, when, content, agent="build", route=None, finish="stop", seq=None):
    add_row(db, sid, mid, when, "assistant", {
        "agent": agent, "model": route or model(), "content": content,
        "finish": finish, "rawFinish": CANARY, "cost": 0, "tokens": {}}, seq)


def tool(name, inp, meta=None, status="completed"):
    return {"type": "tool", "id": "t_" + name, "name": name, "executed": True,
            "state": {"status": status, "input": inp, "metadata": meta or {}, "content": CANARY}}


def text(value):
    return {"type": "text", "text": value, "native": CANARY}


def patch(relative):
    return tool("apply_patch", {"patchText": CANARY}, {"files": [
        {"filePath": "/private/" + CANARY, "relativePath": relative, "type": "update", "patch": CANARY}]})


def stale_v1(db, repo):
    """Frozen 1.x tables holding sessions the 2.x reader must never see."""
    schema(db)
    db.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?)",
               ("ses_stale", None, str(repo), "1.18.32", CANARY, "build",
                json.dumps(model(model_id="gpt-6-luna", variant="low")), EPOCH + 50, EPOCH + 150))
    db.execute("INSERT INTO message VALUES (?,?,?,?,?)", ("st_a", "ses_stale", EPOCH + 51, EPOCH + 51, json.dumps(
        {"role": "assistant", "agent": "build", "providerID": "github-copilot", "modelID": "gpt-6-luna", "variant": "low",
         "error": {"name": "APIError", "data": {"statusCode": 429, "message": CANARY}}})))
    db.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", ("st_p", "st_a", "ses_stale", EPOCH + 51, EPOCH + 51, json.dumps(
        {"type": "tool", "tool": "apply_patch", "state": {"status": "completed", "input": {}, "metadata": {
            "files": [{"relativePath": "tests/conftest.py", "type": "update"}]}}})))
    db.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", ("st_q", "st_a", "ses_stale", EPOCH + 51, EPOCH + 51, json.dumps(
        {"type": "patch", "files": ["src/stale-snapshot.py"]})))


def build(base):
    repo = base / "work" / "repo"
    repo.mkdir(parents=True)
    (repo / ".git").mkdir()
    path = base / "opencode.db"
    db = sqlite3.connect(path)
    v2_schema(db)
    stale_v1(db, repo)

    # 2.3.0 session, model NULL, aligned: gate respected, text/reasoning/skill/apply_patch.
    add_session(db, "ses_v2_aligned", repo, start=1000)
    user(db, "ses_v2_aligned", "a_u1", 1001, "Build this " + CANARY)
    assistant(db, "ses_v2_aligned", "a_a1", 1002, [
        {"type": "reasoning", "text": CANARY, "native": CANARY, "time": {}},
        text("Shall I proceed? " + CANARY), tool("skill", {"name": "brainstorming"})])
    user(db, "ses_v2_aligned", "a_u2", 1003, "Approved, proceed " + CANARY)
    assistant(db, "ses_v2_aligned", "a_a2", 1004, [patch("src/aligned.py")])
    add_row(db, "ses_v2_aligned", "a_idle", 1005, "idle", {"outcome": CANARY})
    add_row(db, "ses_v2_aligned", "a_comp", 1006, "compaction", {"status": "done", "reason": CANARY, "summary": CANARY, "metadata": {}})
    add_row(db, "ses_v2_aligned", "a_sw", 1007, "agent-switched", {"agent": "plan", "previous": "build"})

    # 2.3.0 session, model NULL, routed off-target per message.
    add_session(db, "ses_v2_mismatch", repo, start=2000)
    user(db, "ses_v2_mismatch", "m_u", 2001, CANARY)
    assistant(db, "ses_v2_mismatch", "m_a", 2002, [text(CANARY)], route=model(model_id="gpt-6-luna", variant="low"))

    # Only a system/synthetic row "approves": it is not user text, so the gate is skipped.
    add_session(db, "ses_v2_gate", repo, start=3000)
    user(db, "ses_v2_gate", "g_u", 3001, CANARY)
    assistant(db, "ses_v2_gate", "g_a1", 3002, [tool("skill", {"name": "brainstorming"})])
    add_row(db, "ses_v2_gate", "g_sys", 3003, "system", {"text": "Approved, proceed " + CANARY})
    add_row(db, "ses_v2_gate", "g_syn", 3004, "synthetic", {"text": "Approved, proceed " + CANARY})
    assistant(db, "ses_v2_gate", "g_a2", 3005, [patch("src/gate.py"),
              patch("src/denied.py") | {"state": {"status": "error", "input": {}, "metadata": {"files": [{"relativePath": "src/denied.py", "type": "update"}]}}}])

    # Delegations: the 1.x-shaped task tool and the 2.x subagent tool. The
    # children are absent from session_v2, so they are counted only through
    # the tool calls: removing either branch changes the counts.
    add_session(db, "ses_v2_parent", repo, start=4000)
    user(db, "ses_v2_parent", "p_u", 4001, CANARY)
    assistant(db, "ses_v2_parent", "p_a", 4002, [
        tool("task", {"subagent_type": "reviewer", "prompt": CANARY}, {"sessionId": "ses_v2_review", "model": CANARY}),
        tool("subagent", {"agent": "expert", "prompt": PACKET}, {"sessionID": "ses_v2_expert"})])

    # Delegations whose children DO exist in session_v2, each with its own
    # assistant message: their requests are counted per child agent.
    add_session(db, "ses_v2_parent2", repo, start=4500)
    user(db, "ses_v2_parent2", "p2_u", 4501, CANARY)
    assistant(db, "ses_v2_parent2", "p2_a", 4502, [
        tool("task", {"subagent_type": "reviewer", "prompt": CANARY}, {"sessionId": "ses_v2_c_review"}),
        tool("subagent", {"agent": "expert", "prompt": PACKET}, {"sessionID": "ses_v2_c_expert"})])
    add_session(db, "ses_v2_c_review", repo, agent="reviewer", parent="ses_v2_parent2", start=4510)
    assistant(db, "ses_v2_c_review", "c1_a", 4511, [text(CANARY)], agent="reviewer",
              route=model(model_id="claude-opus-5.5", variant="high"))
    add_session(db, "ses_v2_c_expert", repo, agent="expert", parent="ses_v2_parent2", start=4520)
    assistant(db, "ses_v2_c_expert", "c2_a", 4521, [text(CANARY)], agent="expert",
              route=model(provider="openai", model_id="gpt-6-astra", variant="xhigh"))

    # Build root whose first assistant turn ran as plan: the root model comes
    # from build's own message, never from plan's.
    add_session(db, "ses_v2_switch", repo, start=6000)
    user(db, "ses_v2_switch", "w_u", 6001, CANARY)
    assistant(db, "ses_v2_switch", "w_a1", 6002, [text(CANARY)], agent="plan",
              route=model(model_id="claude-opus-5.5", variant="xhigh"))
    assistant(db, "ses_v2_switch", "w_a2", 6003, [text(CANARY)])
    # Only plan ran: build's model stays unknown, so no root comparison.
    add_session(db, "ses_v2_plan_only", repo, start=6500)
    assistant(db, "ses_v2_plan_only", "po_a", 6501, [text(CANARY)], agent="plan",
              route=model(model_id="claude-opus-5.5", variant="xhigh"))

    # NULL agent: taken from the first assistant message; with none, unchanged.
    add_session(db, "ses_v2_noagent", repo, agent=None, start=7000)
    user(db, "ses_v2_noagent", "n_u", 7001, CANARY)
    assistant(db, "ses_v2_noagent", "n_a", 7002, [text(CANARY)], route=model(model_id="gpt-6-luna", variant="low"))
    add_session(db, "ses_v2_noagent_empty", repo, agent=None, start=7500)
    user(db, "ses_v2_noagent_empty", "ne_u", 7501, CANARY)

    # Same millisecond: seq, not id, orders the approval before the edit.
    add_session(db, "ses_v2_seq", repo, start=8000)
    user(db, "ses_v2_seq", "q_u", 8001, CANARY)
    assistant(db, "ses_v2_seq", "q_a1", 8002, [tool("skill", {"name": "brainstorming"})])
    assistant(db, "ses_v2_seq", "q_a", 8003, [patch("src/seq.py")], seq=80032)
    user(db, "ses_v2_seq", "q_b", 8003, "Approved, proceed " + CANARY, seq=80031)

    # A migrated 1.x session, model stored on the row as in 1.x.
    add_session(db, "ses_v2_migrated", repo, stored_model=model(), start=5000, version="1.18.32")
    user(db, "ses_v2_migrated", "mg_u", 5001, CANARY)
    assistant(db, "ses_v2_migrated", "mg_a", 5002, [text(CANARY)])
    db.commit()
    db.close()
    return path


def report(db, state, *extra):
    result = run("report", "--since", "1970-01-01", "--profile-effective", PROFILE, "--db", str(db),
                 "--log-dir", "", "--eval-records", "", "--state-dir", str(state), *extra)
    assert result.returncode == 0, result.stderr
    assert CANARY not in result.stdout and CANARY not in result.stderr
    return result


def main():
    module = runpy.run_path(str(OBSERVE))
    session_hash, detect_schema, ObserveError = module["session_hash"], module["detect_schema"], module["ObserveError"]
    with tempfile.TemporaryDirectory(prefix="observe-v2-db-") as tmp:
        base = Path(tmp)
        db = build(base)
        state = base / "state"
        original = db.read_bytes()
        out = json.loads(report(db, state, "--format", "json").stdout)
        assert db.read_bytes() == original
        serialized = json.dumps(out) + (state / "latest-report.json").read_text()
        assert CANARY not in serialized
        report(db, state)  # text format stays private too
        key = (state / "hash.key").read_bytes()
        hashes = {sid: session_hash(key, sid) for sid in (
            "ses_v2_aligned", "ses_v2_mismatch", "ses_v2_gate", "ses_v2_parent", "ses_v2_parent2", "ses_v2_migrated", "ses_stale",
            "ses_v2_switch", "ses_v2_plan_only", "ses_v2_noagent", "ses_v2_noagent_empty", "ses_v2_seq")}

        # Default manifest follows the schema; only session_v2 rows are read.
        assert out["coverage"]["session_schema"] == "v2"
        assert out["coverage"]["unavailable_signals"] == ["snapshot_edits", "retries", "log_stream_signals", "title_requests"]
        assert out["coverage"]["opencode_versions"] == ["1.18.32", "2.3.0"], out["coverage"]
        assert out["session_classes"] == {"eval_dispatcher": 1, "production": 10, "pre_profile": 0}, out["session_classes"]
        assert out["coverage"]["sessions_agent_from_messages"] == 1
        assert out["populations"]["production"]["agents"] == {"build": 10}, out["populations"]["production"]["agents"]
        assert hashes["ses_stale"] not in serialized
        assert "src/stale-snapshot.py" not in serialized and "tests/conftest.py" not in serialized
        assert out["signals"]["provider_error"] == 0 and out["signals"]["scope"] == 0

        # Routing with model NULL comes from the assistant messages.
        routing = [item for item in out["review"] if item["signal"] == "routing"]
        assert {(item["session"], item["reason"], item["observed_model"], item.get("variant")) for item in routing} == {
            (hashes["ses_v2_mismatch"], "root_model_differs", "github-copilot/gpt-6-luna", "low"),
            (hashes["ses_v2_mismatch"], "request_route_differs", "github-copilot/gpt-6-luna", "low"),
            (hashes["ses_v2_noagent"], "root_model_differs", "github-copilot/gpt-6-luna", "low"),
            (hashes["ses_v2_noagent"], "request_route_differs", "github-copilot/gpt-6-luna", "low"),
        }, routing
        requests = {(r["agent"], r["provider"], r["model"], r["variant"]): r["requests"] for r in out["routing_requests"]}
        assert requests == {
            ("build", "github-copilot", "gpt-6.1-sol", "high"): 10,
            ("build", "github-copilot", "gpt-6-luna", "low"): 2,
            ("plan", "github-copilot", "claude-opus-5.5", "xhigh"): 2,
            # Children present in session_v2: counted per child agent.
            ("reviewer", "github-copilot", "claude-opus-5.5", "high"): 1,
            ("expert", "openai", "gpt-6-astra", "xhigh"): 1,
        }, requests

        # Gate: user approval counts, system/synthetic text never does; denied edits do not count.
        assert out["gate_outcomes"] == {"ADHERENT": 2, "NON_ADHERENT": 1}, out["gate_outcomes"]
        gates = [item for item in out["review"] if item["signal"] == "gate"]
        assert [(g["session"], g["paths"]) for g in gates] == [(hashes["ses_v2_gate"], ["src/gate.py"])], gates
        assert out["checkpoint"]["build_sessions_with_gate"] == 3

        # Delegations: task and subagent produce the same tasks entries.
        assert out["escalations"] == {"expert": 2, "reviewer": 2, "breakglass": 0}, out["escalations"]
        assert out["populations"]["production"]["task_children"] == {"expert": 2, "reviewer": 2}
        assert sorted(out["expert_escalations"], key=lambda e: e["parent"]) == sorted(
            [{"parent": hashes[name], "repository": "product", "decision_packet": True}
             for name in ("ses_v2_parent", "ses_v2_parent2")], key=lambda e: e["parent"])

        # locate reads session_v2, never the stale session table.
        found = run("locate", hashes["ses_v2_aligned"], "--db", str(db), "--state-dir", str(state))
        assert found.returncode == 0 and found.stdout.strip() == "ses_v2_aligned", found.stderr
        stale = run("locate", hashes["ses_stale"], "--db", str(db), "--state-dir", str(state))
        assert stale.returncode == 2 and "session_hash_not_found" in stale.stderr

        # The message reader on its own.
        ro = sqlite3.connect(db.as_uri() + "?mode=ro", uri=True)
        try:
            assert detect_schema(ro) == "v2"
            sessions = module["read_sessions"](ro, "v2")
            assert "ses_stale" not in sessions and sessions["ses_v2_aligned"]["model"] is None
            messages = module["read_messages"](ro, "v2", ["ses_v2_aligned", "ses_v2_gate", "ses_v2_parent", "ses_v2_seq"])
            assert [m["id"] for m in messages["ses_v2_seq"]] == ["q_u", "q_a1", "q_b", "q_a"]
            aligned = messages["ses_v2_aligned"]
            assert [m["data"]["role"] for m in aligned] == ["user", "assistant", "user", "assistant"]
            assert aligned[1]["skills"] == ["brainstorming"] and len(aligned[1]["texts"]) == 1
            assert aligned[1]["data"]["providerID"] == "github-copilot" and aligned[1]["data"]["modelID"] == "gpt-6.1-sol"
            assert aligned[1]["data"]["variant"] == "high" and aligned[1]["time"] == EPOCH + 1002
            assert aligned[3]["edits"] == [("src/aligned.py", "update")] and aligned[3]["snapshot_edits"] == []
            assert all("retries" not in m and "error" not in m["data"] for rows in messages.values() for m in rows)
            assert [m["data"]["role"] for m in messages["ses_v2_gate"]] == ["user", "assistant", "assistant"]
            tasks = messages["ses_v2_parent"][1]["tasks"]
            assert tasks == [{"agent": "reviewer", "child": "ses_v2_review", "packet": False},
                             {"agent": "expert", "child": "ses_v2_expert", "packet": True}], tasks
        finally:
            ro.close()

        # 1.x databases report their schema and no unavailable signals.
        v1 = base / "v1.db"
        conn = sqlite3.connect(v1)
        schema(conn)
        conn.commit()
        conn.close()
        v1_out = json.loads(report(v1, base / "state-v1", "--manifest", str(MANIFEST), "--format", "json").stdout)
        assert v1_out["coverage"]["session_schema"] == "v1" and "unavailable_signals" not in v1_out["coverage"]

        # Unknown schema fails closed in every command.
        unknown = base / "unknown.db"
        conn = sqlite3.connect(unknown)
        conn.execute("CREATE TABLE other (id TEXT)")
        conn.commit()
        conn.close()
        bad = run("report", "--since", "1970-01-01", "--profile-effective", PROFILE, "--db", str(unknown),
                  "--manifest", str(V2_MANIFEST), "--log-dir", "", "--eval-records", "", "--state-dir", str(state))
        assert bad.returncode == 2 and "unsupported_session_schema" in bad.stderr, bad.stderr
        bad = run("locate", "0" * 16, "--db", str(unknown), "--state-dir", str(state))
        assert bad.returncode == 2 and "unsupported_session_schema" in bad.stderr, bad.stderr
        ro = sqlite3.connect(unknown.as_uri() + "?mode=ro", uri=True)
        try:
            detect_schema(ro)
            raise AssertionError("expected unsupported_session_schema")
        except ObserveError as error:
            assert str(error) == "unsupported_session_schema"
        finally:
            ro.close()
    print("PASS: 2.x session reader")


if __name__ == "__main__":
    main()
