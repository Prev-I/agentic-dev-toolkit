#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import test_observe

from test_observe import (CANARY, EPOCH, MANIFEST, add_edit, add_message,
                          add_session, add_skill, add_text, run, schema)


def main():
    global EPOCH
    EPOCH = 1791056198000
    test_observe.EPOCH = EPOCH
    with tempfile.TemporaryDirectory(prefix="observe-activation-") as tmp:
        base = Path(tmp)
        config = base / "active.jsonc"
        targets = json.loads(MANIFEST.read_text())["agents"]
        config.write_text("// active configuration\n" + json.dumps({"agent": targets}))
        os.utime(config, ns=(EPOCH * 1000000, EPOCH * 1000000))
        db_path = base / "db.sqlite"
        db = sqlite3.connect(db_path)
        schema(db)
        toolkit = base / "agentic-dev-toolkit"
        product = base / "private-product"
        for repo in (toolkit, product):
            repo.mkdir()
            (repo / ".git").mkdir()
        add_session(db, "ses_span", product, start=1000)
        db.execute("UPDATE session SET time_created=? WHERE id='ses_span'", (EPOCH - 10000,))
        add_message(db, "ses_span", "before", 1000, "assistant", model="before-model")
        db.execute("UPDATE message SET time_created=? WHERE id='before'", (EPOCH - 1000,))
        add_message(db, "ses_span", "after", 2000, "assistant", model="spanning-model")
        for sid, repo in (("ses_toolkit", toolkit), ("ses_product", product)):
            add_session(db, sid, repo, start=3000)
            add_message(db, sid, sid + "_u", 3001, "user")
            add_text(db, sid, sid + "_u", 3001, "The design is approved. Implement now. " + CANARY)
            add_message(db, sid, sid + "_a", 3002, "assistant", model="post-model")
            add_skill(db, sid, sid + "_a", 3002, "brainstorming")
            add_edit(db, sid, sid + "_a", 3003, "src/work.py")
        packet = "\n".join(f"{i}. {heading}: {CANARY}" for i, heading in enumerate([
            "Problem statement", "Context", "Options considered", "Arguments for each option",
            "Risks identified", "Requesting agent", "Desired output"], 1))
        for i, prompt in enumerate((packet, "Unstructured " + CANARY)):
            child = f"ses_expert{i}"
            add_session(db, child, product, agent="expert", model="openai/gpt-6-astra", parent="ses_product", start=4000+i)
            for j in range(2):
                mid = f"task{i}_{j}"
                add_message(db, "ses_product", mid, 4001+i+j, "assistant")
                data = {"type": "tool", "tool": "task", "state": {"status": "completed",
                    "input": {"subagent_type": "expert", "prompt": prompt},
                    "metadata": {"sessionId": child}, "output": CANARY}}
                db.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", (mid, mid, "ses_product", EPOCH+4001+i+j, EPOCH+4001+i+j, json.dumps(data)))
        db.commit()
        db.close()
        args = ("--db", str(db_path), "--log-dir", str(base / "no-logs"),
                "--state-dir", str(base / "state"), "--eval-records", "",
                "--activation-config", str(config), "--format", "json")
        result = run("report", "--since", "2026-10-03", *args)
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        assert report["profile_boundary"]["source"] == "aligned_config_mtime"
        assert report["profile_boundary"]["timestamp"] == "2026-10-03T19:36:38Z"
        flags = report["routing_activation_audit"]
        assert {flag["activation_class"] for flag in flags} == {"PRE_ACTIVATION", "SESSION_SPANNING_ACTIVATION", "POST_ACTIVATION"}
        before = next(flag for flag in flags if flag.get("model") == "before-model")
        assert before["timestamp"] == "2026-10-03T19:36:37Z"
        assert before["expected_model"] == "github-copilot/gpt-6.1-sol"
        assert before["observed_model"] == "github-copilot/before-model"
        assert before not in report["review"]
        assert all(item.get("activation_class") in (None, "POST_ACTIVATION") for item in report["review"])
        spanning = next(item for item in report["informational"] if item.get("activation_class") == "SESSION_SPANNING_ACTIVATION")
        confirmed = run("review", "confirm", spanning["session"], spanning["signal"], spanning["reason"],
                        "--state-dir", str(base / "state"))
        assert confirmed.returncode == 0
        rerun = json.loads(run("report", "--since", "2026-10-03", *args).stdout)
        assert rerun["triggers"]["routing_mismatch"] is False
        repos = report["production_repositories"]
        assert repos["toolkit"]["sessions"] == 1 and repos["product"]["sessions"] == 2
        assert report["checkpoint"]["build_sessions_with_gate"] == 1
        experts = report["expert_escalations"]
        assert len(experts) == 2
        assert {item["decision_packet"] for item in experts} == {True, False}
        assert all(set(item) == {"parent", "repository", "decision_packet"} for item in experts)
        default = json.loads(run("report", *args).stdout)
        assert default["since"] == report["profile_boundary"]["timestamp"]
        invalid = json.loads(run("report", "--activation-config", str(base / "missing"),
                                 *[v for v in args if v not in ("--activation-config", str(config))]).stdout)
        assert invalid["profile_boundary"]["source"] == "alignment_record_date"
        serialized = result.stdout + result.stderr + "".join(p.read_text(errors="replace") for p in (base / "state").iterdir() if p.is_file())
        assert CANARY not in serialized and str(base) not in serialized
    print("PASS: activation timestamps, repository checkpoint and Expert packet metadata")


if __name__ == "__main__":
    main()
