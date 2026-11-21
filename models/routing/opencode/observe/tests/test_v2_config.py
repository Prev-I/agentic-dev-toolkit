#!/usr/bin/env python3
"""2.x targets manifest, 2.x config and schema detection."""
import json
import os
from pathlib import Path
import runpy
import sqlite3
import tempfile

from test_observe import MANIFEST, OBSERVE, schema

V2_MANIFEST = OBSERVE.parent.parent / "v2/manifests/current-routing-targets.json"


def v2_schema(db):
    db.executescript(
        """
        CREATE TABLE session_v2 (id TEXT, parent_id TEXT, directory TEXT, version TEXT,
          agent TEXT, model TEXT, time_created INTEGER, time_updated INTEGER, extra TEXT);
        CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER,
          time_created INTEGER, time_updated INTEGER, data TEXT);
        """
    )


def make_db(path, kind):
    db = sqlite3.connect(path)
    if kind in ("v1", "v2-stale"):
        schema(db)
    if kind in ("v2", "v2-stale"):
        v2_schema(db)
    if kind == "unknown":
        db.execute("CREATE TABLE other (id TEXT)")
    db.commit()
    db.close()


def main():
    module = runpy.run_path(str(OBSERVE))
    load_manifest, profile_boundary = module["load_manifest"], module["profile_boundary"]
    detect_schema, default_manifest = module["detect_schema"], module["default_manifest"]
    ObserveError = module["ObserveError"]
    with tempfile.TemporaryDirectory(prefix="observe-v2-config-") as tmp:
        base = Path(tmp)

        # Both manifest formats normalise to the same rows.
        v2 = {"format": "opencode-v2-routing-targets/1",
              "agents": {"build": {"providerID": "github-copilot", "model": "gpt-6.1-sol", "variant": "high", "mode": "primary"},
                         "general": {"providerID": "github-copilot", "model": "gpt-6.1-sol", "variant": "medium", "mode": None}}}
        v1 = {"agents": {"build": {"model": "github-copilot/gpt-6.1-sol", "variant": "high", "mode": "primary"},
                         "general": {"model": "github-copilot/gpt-6.1-sol", "variant": "medium", "mode": None}}}
        (base / "m2.json").write_text(json.dumps(v2))
        (base / "m1.json").write_text(json.dumps(v1))
        assert load_manifest(base / "m2.json") == load_manifest(base / "m1.json") == v1["agents"]
        assert load_manifest(V2_MANIFEST)["plan"]["model"] == "github-copilot/claude-opus-5.5"
        load_manifest(MANIFEST)

        # Unknown format raises.
        (base / "bad.json").write_text(json.dumps({"format": "other/9", "agents": {}}))
        try:
            load_manifest(base / "bad.json")
            raise AssertionError("expected unsupported_manifest_format")
        except ObserveError as error:
            assert str(error) == "unsupported_manifest_format"

        # 2.x config aligned with a manifest lacking decision_reference.
        aligned = {"agents": {r: {"model": {"providerID": "github-copilot", "model": "gpt-6.1-sol", "variant": v}}
                              for r, v in (("build", "high"), ("general", "medium"))}}
        config = base / "opencode.jsonc"
        config.write_text("// c\n" + json.dumps(aligned))
        got = profile_boundary(base / "m2.json", None, config)
        assert got["source"] == "aligned_config_mtime", got

        # Unaligned config raises profile_effective_required.
        aligned["agents"]["build"]["model"]["variant"] = "low"
        config.write_text(json.dumps(aligned))
        try:
            profile_boundary(base / "m2.json", None, config)
            raise AssertionError("expected profile_effective_required")
        except ObserveError as error:
            assert str(error) == "profile_effective_required"
        # A missing config behaves the same.
        try:
            profile_boundary(base / "m2.json", None, base / "absent.jsonc")
            raise AssertionError("expected profile_effective_required")
        except ObserveError as error:
            assert str(error) == "profile_effective_required"

        # --profile-effective always wins.
        got = profile_boundary(base / "m2.json", "2026-11-21T00:00:00Z", config)
        assert got["source"] == "explicit_override"

        # Schema detection.
        for kind, expected in (("v1", "v1"), ("v2", "v2"), ("v2-stale", "v2"), ("unknown", None)):
            path = base / f"{kind}.db"
            make_db(path, kind)
            db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
            try:
                if expected:
                    assert detect_schema(db) == expected, kind
                else:
                    try:
                        detect_schema(db)
                        raise AssertionError("expected unsupported_session_schema")
                    except ObserveError as error:
                        assert str(error) == "unsupported_session_schema"
            finally:
                db.close()
        # Missing required columns is not v2.
        partial = base / "partial.db"
        db = sqlite3.connect(partial)
        db.execute("CREATE TABLE session_v2 (id TEXT)")
        db.execute("CREATE TABLE session_message (id TEXT)")
        db.commit()
        db.close()
        db = sqlite3.connect(partial.as_uri() + "?mode=ro", uri=True)
        try:
            detect_schema(db)
            raise AssertionError("expected unsupported_session_schema")
        except ObserveError as error:
            assert str(error) == "unsupported_session_schema"
        finally:
            db.close()

        # session_message without seq is not v2 (seq orders same-millisecond rows).
        noseq = base / "noseq.db"
        db = sqlite3.connect(noseq)
        db.executescript(
            """
            CREATE TABLE session_v2 (id TEXT, parent_id TEXT, directory TEXT, version TEXT,
              agent TEXT, model TEXT, time_created INTEGER, time_updated INTEGER);
            CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT,
              time_created INTEGER, data TEXT);
            """
        )
        db.commit()
        db.close()
        db = sqlite3.connect(noseq.as_uri() + "?mode=ro", uri=True)
        try:
            detect_schema(db)
            raise AssertionError("expected unsupported_session_schema")
        except ObserveError as error:
            assert str(error) == "unsupported_session_schema"
        finally:
            db.close()

        # Default manifest follows the schema; explicit --manifest wins.
        assert Path(default_manifest(base / "v1.db")) == MANIFEST.resolve()
        assert Path(default_manifest(base / "v2.db")) == V2_MANIFEST.resolve()
        assert Path(default_manifest(base / "v2-stale.db")) == V2_MANIFEST.resolve()
        assert Path(default_manifest(base / "missing.db")) == MANIFEST.resolve()
        assert Path(default_manifest(base / "unknown.db")) == MANIFEST.resolve()
        args = module["parser"]().parse_args(["report", "--manifest", "x.json"])
        assert args.manifest == "x.json"
        assert module["parser"]().parse_args(["report"]).manifest is None
    print("PASS: 2.x manifest, config boundary and schema detection")


if __name__ == "__main__":
    main()
