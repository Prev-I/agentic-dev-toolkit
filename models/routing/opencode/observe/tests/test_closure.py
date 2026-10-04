#!/usr/bin/env python3
import json
import sqlite3
import tempfile
from pathlib import Path

from test_observe import CANARY, MANIFEST, add_session, add_message, add_text, add_skill, add_edit, run, schema


def main():
    with tempfile.TemporaryDirectory(prefix="observe-closure-") as tmp:
        base = Path(tmp)
        cwd = base / "agentic-dev-toolkit"  # Name alone must not turn a non-Git cwd into toolkit.
        cwd.mkdir()
        db_path = base / "db"
        db = sqlite3.connect(db_path)
        schema(db)
        add_session(db, "ses_workspace", cwd, start=1000)
        add_message(db, "ses_workspace", "prompt", 1001, "user", agent="plan", model="claude-opus-5.5", variant="xhigh")
        add_text(db, "ses_workspace", "prompt", 1001, "The design is approved. " + CANARY)
        add_message(db, "ses_workspace", "build", 1002, "assistant")
        add_skill(db, "ses_workspace", "build", 1002, "brainstorming")
        add_edit(db, "ses_workspace", "build", 1003, "src/work.py")
        for mid, model in (("known", "claude-sonnet-5.5"), ("wrong_model", "gpt-6-luna")):
            add_message(db, "ses_workspace", mid, 2000, "assistant", agent="compaction", model=model, variant="xhigh")
            raw = json.loads(db.execute("SELECT data FROM message WHERE id=?", (mid,)).fetchone()[0])
            raw["parentID"] = "prompt"
            db.execute("UPDATE message SET data=? WHERE id=?", (json.dumps(raw), mid))
        db.commit()
        db.close()
        args = ("--db", str(db_path), "--log-dir", str(base / "none"), "--state-dir", str(base / "state"),
                "--eval-records", "", "--format", "json")
        result = run("report", *args)
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        assert report["production_repositories"]["workspace"]["sessions"] == 1
        assert report["production_repositories"]["product"]["sessions"] == 0
        assert report["production_repositories"]["toolkit"]["sessions"] == 0
        assert report["checkpoint"]["build_sessions_with_gate"] == 0
        known = [i for i in report["informational"] if i.get("activation_class") == "KNOWN_DEVIATION"]
        assert len(known) == 1
        assert known[0]["status"] == "informational"
        assert known[0]["reference"].endswith("#addendum--2026-10-04-compaction-variant-inheritance")
        record = MANIFEST.parents[2] / known[0]["reference"].split("#")[0]
        assert "## Addendum — 2026-10-04 compaction variant inheritance" in record.read_text()
        assert any(i.get("model") == "gpt-6-luna" for i in report["review"])
        assert not any(i.get("activation_class") == "KNOWN_DEVIATION" for i in report["review"])
        again = json.loads(run("report", *args).stdout)
        assert len([i for i in again["informational"] if i.get("activation_class") == "KNOWN_DEVIATION"]) == 1
        assert CANARY not in result.stdout and str(base) not in result.stdout
        db = sqlite3.connect(db_path)
        db.execute("UPDATE session SET version='1.18.33'")
        db.commit()
        db.close()
        other_version = json.loads(run("report", *args).stdout)
        assert not any(i.get("activation_class") == "KNOWN_DEVIATION" for i in other_version["routing_activation_audit"])
    print("PASS: workspace exclusion and bounded known compaction deviation")


if __name__ == "__main__":
    main()
