#!/usr/bin/env python3
"""Logs on 2.x: requests come from the database message loop; errors and process starts from the log."""
from datetime import datetime, timezone
import json
from pathlib import Path
import runpy
import sqlite3
import tempfile

from test_observe import CANARY, EPOCH, OBSERVE, run, schema
from test_v2_config import v2_schema
from test_v2_db import PROFILE, add_session, assistant, model, text, user


def stamp(ms):
    """Log timestamp for an offset in milliseconds, the unit the database helpers use."""
    moment = datetime.fromtimestamp((EPOCH + ms) / 1000, timezone.utc)
    return f"{moment:%Y-%m-%dT%H:%M:%S}.{moment.microsecond // 1000:03d}Z"


def line(offset, message, **kv):
    fields = {"timestamp": stamp(offset), "level": "INFO", "run": kv.pop("run", "run_a"), "role": "server", "message": message, **kv}
    return " ".join(f'{k}="{v}"' if " " in str(v) else f"{k}={v}" for k, v in fields.items())


def write_log(directory):
    directory.mkdir()
    lines = [
        # 1.x era: stream lines name the session; they must be ignored on v2.
        # Its model differs from every database message, so reading it on v2 would show.
        line(1, "stream", **{"session.id": "ses_log", "agent": "build", "providerID": "github-copilot", "modelID": "claude-opus-5.5"}),
        # 2.x era: no stream line; llm runtime selected has no session.id.
        line(2, "llm runtime selected", **{"llm.runtime": "native", "llm.provider": "github-copilot", "llm.model": "gpt-6-luna"}),
        line(1500, "stream error", **{"session.id": "ses_log", "agent": "build", "providerID": "github-copilot",
                                      "modelID": "gpt-6.1-sol", "mode": "primary", "error.error": "429 rate limit " + "x"}),
        line(1511, "other", **{"session.id": "ses_log", "run": "run_b", "role": "cli"}),
    ]
    (directory / "opencode.log").write_text("\n".join(lines) + "\n")


def main():
    module = runpy.run_path(str(OBSERVE))
    detect_schema, ObserveError, fill_models = module["detect_schema"], module["ObserveError"], module["v2_fill_models"]
    with tempfile.TemporaryDirectory(prefix="observe-v2-log-") as tmp:
        base = Path(tmp)
        logs = base / "log"
        write_log(logs)
        parse = module["parse_log_files"]

        # Unit level: v1 keeps its stream line, v2 never reads one; errors and starts are shared.
        v1 = parse(logs, 0, "v1")
        v2 = parse(logs, 0, "v2")
        assert [s["sid"] for s in v1[0]] == ["ses_log"] and v2[0] == []
        assert list(v1[1]) == list(v2[1]) == ["ses_log"]
        assert v1[1]["ses_log"][0][0] == "rate_limit" and v2[1]["ses_log"][0][1]["provider"] == "github-copilot"
        assert v1[3] == v2[3] and "ses_log" in v2[3]

        # End to end on a 2.x database.
        repo = base / "work" / "repo"
        (repo / ".git").mkdir(parents=True)
        path = base / "opencode.db"
        db = sqlite3.connect(path)
        v2_schema(db)
        add_session(db, "ses_log", repo, start=1000)
        user(db, "ses_log", "l_u", 1001, CANARY)
        assistant(db, "ses_log", "l_a", 1002, [text(CANARY)], route=model(model_id="gpt-6-luna", variant="low"))
        # After the stream error (1500 ms): a 1.x-style retry detector would count it.
        assistant(db, "ses_log", "l_b", 2000, [text(CANARY)])
        # A title message is one request under one key, not two.
        assistant(db, "ses_log", "l_t", 3000, [text(CANARY)], agent="title", route=model(model_id="gpt-6-luna", variant="low"))
        db.commit()
        db.close()

        def report(log_dir, state):
            result = run("report", "--since", "1970-01-01", "--profile-effective", PROFILE, "--db", str(path),
                         "--log-dir", str(log_dir), "--eval-records", "", "--state-dir", str(state), "--format", "json")
            assert result.returncode == 0, result.stderr
            assert CANARY not in result.stdout
            return json.loads(result.stdout), (state / "hash.key").read_bytes()

        out, key = report(logs, base / "state")
        sid = module["session_hash"](key, "ses_log")
        assert out["coverage"]["stream_source"] == "database" and out["coverage"]["log_files"] == 1
        assert set(out["coverage"]["unavailable_signals"]) == {"snapshot_edits", "log_stream_signals", "title_requests"}
        errors = [f for f in out["review"] if f["signal"] == "provider_error"]
        assert [(f["session"], f["reason"], f["agent"]) for f in errors] == [(sid, "rate_limit", "build")], errors
        # Requests follow the error in the database, yet the signal is unavailable on 2.x.
        assert out["provider_retries"] == {}, out["provider_retries"]
        # The log's stream line is never read on v2: only the database's off-target message is flagged,
        # once, by the message loop; request_model_differs (stream-derived) never fires.
        routing = [(f["reason"], f["observed_model"]) for f in out["review"] if f["signal"] == "routing"]
        assert sorted(routing) == [("request_route_differs", "github-copilot/gpt-6-luna"),
                                   ("root_model_differs", "github-copilot/gpt-6-luna")], routing
        assert not any("opus" in item for _, item in routing)
        requests = {(r["agent"], r["provider"], r["model"], r["variant"]): r["requests"] for r in out["routing_requests"]}
        assert requests == {("build", "github-copilot", "gpt-6-luna", "low"): 1,
                            ("build", "github-copilot", "gpt-6.1-sol", "high"): 1,
                            ("title", "github-copilot", "gpt-6-luna", "low"): 1}, requests

        # No log directory: requests still come from the message loop.
        bare, _ = report("", base / "state2")
        assert bare["coverage"]["stream_source"] == "database" and bare["coverage"]["log_files"] == 0

        # 1.x coverage names the log.
        v1db = base / "v1.db"
        conn = sqlite3.connect(v1db)
        schema(conn)
        conn.commit()
        conn.close()
        result = run("report", "--since", "1970-01-01", "--profile-effective", PROFILE, "--db", str(v1db),
                     "--manifest", str(Path(OBSERVE).parent.parent / "eval/manifests/current-routing-targets.json"),
                     "--log-dir", "", "--eval-records", "", "--state-dir", str(base / "state3"), "--format", "json")
        assert json.loads(result.stdout)["coverage"]["stream_source"] == "log"

        # A session_v2 table that fails the v2 column check is never read as 1.x.
        broken = base / "broken.db"
        conn = sqlite3.connect(broken)
        schema(conn)
        conn.executescript("""
            CREATE TABLE session_v2 (id TEXT, parent_id TEXT, directory TEXT, version TEXT,
              agent TEXT, model TEXT, time_created INTEGER, time_updated INTEGER);
            CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT,
              time_created INTEGER, time_updated INTEGER, data TEXT);""")
        conn.commit()
        conn.close()
        ro = sqlite3.connect(broken.as_uri() + "?mode=ro", uri=True)
        try:
            detect_schema(ro)
            raise AssertionError("expected unsupported_session_schema")
        except ObserveError as error:
            assert str(error) == "unsupported_session_schema"
        finally:
            ro.close()
        bad = run("report", "--since", "1970-01-01", "--profile-effective", PROFILE, "--db", str(broken),
                  "--log-dir", "", "--eval-records", "", "--state-dir", str(base / "state4"))
        assert bad.returncode == 2 and "unsupported_session_schema" in bad.stderr, bad.stderr

    # The NULL-model fallback needs a session agent to match.
    def row(agent):
        return {"data": {"role": "assistant", "agent": agent, "model": {"providerID": "p", "id": "m", "variant": "v"}}}
    sessions = {"none": {"agent": None, "model": None}, "build": {"agent": "build", "model": None},
                "other": {"agent": "build", "model": None}}
    fill_models(sessions, {"none": [row(None)], "build": [row("build")], "other": [row("plan")]})
    assert sessions["none"]["model"] is None, "None == None must not match"
    assert sessions["build"]["model"]["id"] == "m" and sessions["other"]["model"] is None
    print("PASS: 2.x logs")


if __name__ == "__main__":
    main()
