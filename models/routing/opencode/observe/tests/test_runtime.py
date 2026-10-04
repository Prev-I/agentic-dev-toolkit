#!/usr/bin/env python3
import json
import os
from pathlib import Path
import runpy
import sqlite3
import tempfile

from test_observe import CANARY, EPOCH, MANIFEST, add_edit, add_message, add_session, add_skill, add_text, run, schema


def main():
    with tempfile.TemporaryDirectory(prefix="observe-runtime-") as tmp:
        base = Path(tmp)
        # Remote identity beats directory naming, including a renamed toolkit.
        repos = (base / "renamed", base / "agentic-dev-toolkit")
        for repo, remote in zip(repos, ("git@github.com:Prev-I/agentic-dev-toolkit.git", "https://github.com/example/product.git")):
            (repo / ".git").mkdir(parents=True)
            (repo / ".git/config").write_text(f'[remote "origin"]\n url = {remote}\n')
        db_path = base / "db"
        db = sqlite3.connect(db_path)
        schema(db)
        for sid, repo in (("ses_stale", repos[0]), ("ses_override", repos[1])):
            add_session(db, sid, repo, start=1000)
            add_message(db, sid, sid + "_u", 1001, "user")
            add_text(db, sid, sid + "_u", 1001, "The design is approved. " + CANARY)
            add_message(db, sid, sid + "_a", 1002, "assistant")
            add_message(db, sid, sid + "_b", 2000, "assistant", model="other-model")
            add_skill(db, sid, sid + "_b", 2000, "brainstorming")
            add_edit(db, sid, sid + "_b", 2001, "tests/conftest.py")
            add_message(db, sid, sid + "_u2", 2002, "user")
            add_text(db, sid, sid + "_u2", 2002, "Fix this " + CANARY)
            add_message(db, sid, sid + "_c", 2003, "assistant", model="other-model")
            add_edit(db, sid, sid + "_c", 2003, "tests/conftest.py")
        db.commit()
        db.close()
        logs = base / "logs"
        logs.mkdir()
        (logs / "runtime.log").write_text('\n'.join([
            'timestamp=2026-10-02T00:00:00Z level=INFO run=old message=loading',
            'timestamp=2026-10-04T04:00:00Z level=INFO run=old message=stream session.id=ses_stale agent=build providerID=github-copilot modelID=other-model',
            'timestamp=2026-10-04T00:00:00Z level=INFO run=new message=loading',
            'timestamp=2026-10-04T04:00:00Z level=INFO run=new message=stream session.id=ses_override agent=build providerID=github-copilot modelID=other-model',
        ]) + '\n')
        previous = base / "previous.jsonc"
        previous.write_text(json.dumps({"agent": {"build": {"model": "github-copilot/old-model"}}}))
        result = run("report", "--since", "2026-10-03", "--db", str(db_path), "--log-dir", str(logs),
                     "--previous-config", str(previous), "--state-dir", str(base / "state"), "--eval-records", "", "--format", "json")
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        assert report["production_repositories"]["toolkit"]["sessions"] == 1
        assert report["production_repositories"]["product"]["sessions"] == 1
        assert report["checkpoint"]["build_sessions_with_gate"] == 0
        assert report["routing_activation_counts"]["STALE_PROCESS"] > 0
        assert report["routing_activation_counts"]["MANUAL_OVERRIDE"] > 0
        assert all(item["activation_class"] == "STALE_PROCESS" for item in report["routing_activation_audit"] if item["repository"] == "toolkit")
        assert any(item.get("activation_class") == "MANUAL_OVERRIDE" and item["status"] == "pending" for item in report["review"])
        assert all(item["observed_model"] == "github-copilot/other-model" for item in report["behavior_episodes"])
        assert {item["signal"] for item in report["behavior_episodes"]} >= {"gate", "scope", "rework"}
        assert CANARY not in result.stdout and str(base) not in result.stdout
        helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "process_metadata.py"))
        proc = base / "proc"
        (proc / "123").mkdir(parents=True)
        (proc / "stat").write_text("btime 1000\n")
        (proc / "123/comm").write_text("opencode\n")
        fields = ["S"] + ["0"] * 18 + ["100"]
        (proc / "123/stat").write_text("123 (opencode) " + " ".join(fields))
        assert len(helper["stale_processes"](2000000, proc, ticks=100)) == 1
        assert helper["stale_processes"](900000, proc, ticks=100) == []
        # A switch to the previous profile model is not a manual-override candidate.
        previous.write_text(json.dumps({"agent": {"build": {"model": "github-copilot/other-model"}}}))
        again = json.loads(run("report", "--since", "2026-10-03", "--db", str(db_path), "--log-dir", str(logs),
                              "--previous-config", str(previous), "--state-dir", str(base / "state"),
                              "--eval-records", "", "--format", "json").stdout)
        assert "MANUAL_OVERRIDE" not in again["routing_activation_counts"]
    print("PASS: stale processes, remote repositories and observed-model overrides")


if __name__ == "__main__":
    main()
