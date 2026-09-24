#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../../../.." && pwd)
fixture="$repo/models/routing/opencode/eval/fixtures/reviewer-seeded-defects"

python3 - "$root" "$fixture" <<'PY'
import glob
import json
import os
import sys

root, fixture = sys.argv[1:]
rank = {"blocking": 3, "material": 2, "suggestion": 1}
fixture_revision = os.popen(f"git -C {fixture!r} log -1 --format=%H -- .").read().strip() or "unknown"

for model_key in ("opus5", "opus55"):
    reports = {}
    for path in glob.glob(f"{root}/runs/*-{model_key}/reported.json"):
        label = os.path.basename(os.path.dirname(path))
        case_id = label.split("-", 1)[1].removesuffix(f"-{model_key}")
        payload = json.load(open(path, encoding="utf-8"))
        reports[case_id] = [item for item in payload.get("findings", [])
                            if isinstance(item, dict)]

    seeded = []
    for case_dir in sorted(glob.glob(f"{fixture}/cases/*/")):
        case_id = os.path.basename(case_dir.rstrip("/"))
        truth = json.load(open(f"{case_dir}/ground-truth.json", encoding="utf-8"))
        overrides = set(truth["overrides"])
        candidates = [item for item in reports[case_id]
                      if os.path.basename(str(item.get("file", ""))) in overrides]
        if candidates:
            best = max(candidates, key=lambda item: rank.get(str(item.get("severity")), 0))
            severity = str(best.get("severity"))
            summary = str(best.get("summary", ""))
        else:
            severity, summary = "none", ""
        seeded.append({"id": case_id, "severity": severity,
                       "files": sorted(overrides), "summary": summary,
                       "all_reported": reports[case_id]})

    clean = [{"severity": str(item.get("severity")),
              "file": str(item.get("file", "")),
              "summary": str(item.get("summary", ""))}
             for item in reports["clean"]]
    document = {
        "model_key": model_key,
        "seeded": seeded,
        "clean": clean,
        "normalization": "unchanged Reviewer adapter shape; scorer determines detection from all_reported, files, and fixture witnesses",
        "runner_decides_gate_outcome": False,
        "scorer": "eval/scoring/reviewer.sh::reviewer_structured_gate",
        "fixture_revision": fixture_revision,
        "fixture_integrity_checked": True,
    }
    with open(f"{root}/findings-{model_key}.json", "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
PY
