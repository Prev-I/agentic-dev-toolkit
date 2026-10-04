#!/usr/bin/env python3
"""Regression for population isolation, preauthorization and distinct children."""
import json
from pathlib import Path
import sqlite3
import tempfile

from test_observe import (CANARY, EPOCH, MANIFEST, add_edit, add_message,
                          add_session, add_skill, add_task, add_text, build_fixture, run)


def main():
    with tempfile.TemporaryDirectory(prefix="observe-populations-") as tmp:
        base = Path(tmp)
        db_path, logs, records = build_fixture(base)
        repo = base / "work/repo"
        db = sqlite3.connect(db_path)
        # Repeated/resumed Task calls must not inflate distinct child counts.
        add_message(db, "ses_parent", "resume", 8200, "assistant")
        add_task(db, "ses_parent", "resume", 8200, "reviewer", "ses_child")
        add_session(db, "ses_authorized", repo, start=12000)
        add_message(db, "ses_authorized", "pa_u", 12001, "user")
        add_text(db, "ses_authorized", "pa_u", 12001,
                 "The design is approved. You are explicitly authorized to implement now. " + CANARY)
        add_message(db, "ses_authorized", "pa_a", 12002, "assistant")
        add_skill(db, "ses_authorized", "pa_a", 12002, "brainstorming")
        add_edit(db, "ses_authorized", "pa_a", 12003, "src/preauthorized.py")
        add_session(db, "ses_denied_authorization", repo, start=13000)
        add_message(db, "ses_denied_authorization", "na_u", 13001, "user")
        add_text(db, "ses_denied_authorization", "na_u", 13001,
                 "The design is not approved. Do not implement yet.")
        add_message(db, "ses_denied_authorization", "na_a", 13002, "assistant")
        add_skill(db, "ses_denied_authorization", "na_a", 13002, "brainstorming")
        add_edit(db, "ses_denied_authorization", "na_a", 13003, "src/not-authorized.py")
        add_session(db, "ses_historical", repo, start=14000)
        add_message(db, "ses_historical", "h_a", 14001, "assistant", model="old-model")
        # Historical activity retained only as session count.
        old = EPOCH - 7 * 86400000
        db.execute("UPDATE session SET time_created=?,time_updated=? WHERE id='ses_historical'", (old, old + 100))
        db.execute("UPDATE message SET time_created=? WHERE session_id='ses_historical'", (old + 1,))
        # An old tree resumed now must not recount its historical requests/gates.
        add_session(db, "ses_resumed", repo, start=15000)
        add_message(db, "ses_resumed", "res_old", 15001, "assistant", model="historical-resumed-model")
        add_skill(db, "ses_resumed", "res_old", 15001, "brainstorming")
        add_edit(db, "ses_resumed", "res_old", 15002, "src/historical.py")
        db.execute("UPDATE session SET time_created=? WHERE id='ses_resumed'", (old,))
        db.execute("UPDATE message SET time_created=? WHERE id='res_old'", (old + 1,))
        db.execute("UPDATE part SET time_created=? WHERE message_id='res_old'", (old + 1,))
        add_message(db, "ses_resumed", "res_new", 15003, "assistant")
        db.commit()
        db.close()
        args = ("--db", str(db_path), "--log-dir", str(logs), "--eval-records", str(records),
                "--state-dir", str(base / "state"), "--manifest", str(MANIFEST), "--format", "json")
        result = run("report", "--since", "1970-01-01", *args)
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        assert set(report["populations"]) == {"production", "eval_dispatcher", "pre_profile"}
        production = report["populations"]["production"]
        assert production["escalations"]["reviewer"] == 1
        assert production["gate_outcomes"]["PRE_AUTHORIZED"] == 1
        assert production["gate_outcomes"]["NON_ADHERENT"] == 3
        assert not any("src/preauthorized.py" in flag.get("paths", []) for flag in report["review"])
        assert all(flag["population"] == "production" for flag in report["review"])
        assert report["populations"]["pre_profile"] == {"sessions": 1}
        assert report["populations"]["eval_dispatcher"]["sessions"] == 1
        assert report["populations"]["eval_dispatcher"]["signals"]["routing"] > 0
        assert report["informational"] and all(flag["status"] == "informational" for flag in report["informational"])
        assert "old-model" not in result.stdout
        assert "historical-resumed-model" not in result.stdout
        assert not any("src/historical.py" in flag.get("paths", []) for flag in report["review"])
        default = run("report", *args)
        assert default.returncode == 0, default.stderr
        default_report = json.loads(default.stdout)
        assert default_report["since"] == "2026-10-03T00:00:00Z"
        assert default_report["profile_boundary"]["source"] == "alignment_record_date"
        assert default_report["populations"]["pre_profile"]["sessions"] == 0
        empty = run("report", "--since", "2099-01-01", *args)
        assert empty.returncode == 0, empty.stderr
        assert all(population["sessions"] == 0 for population in json.loads(empty.stdout)["populations"].values())
        text_args = args[:-2]
        text = run("report", "--since", "1970-01-01", *text_args)
        assert all(category in text.stdout for category in ("production", "eval_dispatcher", "pre_profile"))
        assert "Informational (no review):" in text.stdout
        assert CANARY not in result.stdout + default.stdout
    print("PASS: populations, distinct Task children and explicit preauthorization")


if __name__ == "__main__":
    main()
