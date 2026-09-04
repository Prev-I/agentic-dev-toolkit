#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
reviewer_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$reviewer_runner_root/dispatch-fixture.sh"
source "$reviewer_runner_root/../../scoring/fixture-defect-detectors.sh"

reviewer_request() {
  cat <<'PROMPT'
Review every shell script in the current directory as an independent reviewer.

Report your findings and nothing else, as a single JSON object on the final
line, in exactly this form:

{"findings":[{"file":"<file name>","severity":"blocking|material|suggestion","summary":"<one sentence>"}]}

Use "blocking" or "material" only for a defect that would cause incorrect
behavior, data loss, or a security exposure. Use "suggestion" for anything
stylistic or non-consequential. If you find nothing, return {"findings":[]}.
PROMPT
}

run_reviewer_gate() {
  local outdir="" ledger="" timeout_seconds=900 healthy=0
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_reviewer_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture prompt sandbox case_dir case_id
  fixture=$(cd "$reviewer_runner_root/../../fixtures/reviewer-seeded-defects" && pwd)

  # Admission gate (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md):
  # refuse to spend a single live dispatch against a fixture already known to
  # violate its own contract. This is the exact failure mode that let a real
  # defect in clean/pagination.sh go undetected until a live dispatch found
  # it -- fixture-integrity-test.sh proves this mechanically and for free;
  # there is no reason to ever discover it live again.
  local integrity_violations
  if ! integrity_violations=$(fixture_integrity_check "$fixture" 2>&1); then
    printf 'run_reviewer_gate: refusing to dispatch -- fixture integrity check failed:\n%s\n' \
      "$integrity_violations" >&2
    return 1
  fi

  mkdir -p "$outdir"
  prompt="$outdir/prompt.txt"
  reviewer_request >"$prompt"

  # Provenance (docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md,
  # section "Evidence/provenance hardening"): the last commit that touched
  # the fixture tree, so a future fixture defect can mechanically identify
  # exactly which results it invalidates by commit range, rather than by
  # hand-auditing every historical run directory again.
  export REVIEWER_FIXTURE_REVISION
  REVIEWER_FIXTURE_REVISION=$(git -C "$fixture" log -1 --format=%H -- . 2>/dev/null || printf unknown)

  local ledger_args=()
  [[ -n "$ledger" ]] && ledger_args=(--ledger "$ledger")

  run_one() {
    local label=$1 sandbox=$2
    set +e
    dispatch_fixture --outdir "$outdir/$label/dispatch" --label "reviewer-$label" \
      --prompt-file "$prompt" --agent reviewer --workspace "$sandbox" \
      --timeout "$timeout_seconds" "${ledger_args[@]}" --attempt 1
    local status=$?
    set -e
    (( status == 0 )) || healthy=1
    set +e
    dispatch_extract_json "$outdir/$label/dispatch" >"$outdir/$label/reported.json" 2>/dev/null
    if (( $? != 0 )); then printf '{"findings":[]}\n' >"$outdir/$label/reported.json"; healthy=1; fi
    set -e
  }

  # Clean control.
  sandbox="$outdir/clean/sandbox"
  mkdir -p "$sandbox"
  find "$fixture/clean" -maxdepth 1 -name '*.sh' -exec cp {} "$sandbox/" \;
  run_one clean "$sandbox"

  # Seeded cases: clean snapshot plus that case's single override.
  for case_dir in "$fixture"/cases/*/; do
    case_id=$(basename "$case_dir")
    sandbox="$outdir/$case_id/sandbox"
    mkdir -p "$sandbox"
    find "$fixture/clean" -maxdepth 1 -name '*.sh' -exec cp {} "$sandbox/" \;
    python3 - "$case_dir/ground-truth.json" "$case_dir" "$sandbox" <<'PY'
import json
import shutil
import sys

ground_truth_path, case_dir, sandbox = sys.argv[1:]
for override in json.load(open(ground_truth_path, encoding="utf-8"))["overrides"]:
    shutil.copy(f"{case_dir}/{override}", f"{sandbox}/{override}")
PY
    run_one "$case_id" "$sandbox"
  done

  # Normalize into the schema the committed scorer already consumes.
  python3 - "$outdir" "$fixture" <<'PY'
import glob
import json
import os
import sys

outdir, fixture = sys.argv[1:]
RANK = {"blocking": 3, "material": 2, "suggestion": 1}

def reported(label):
    path = f"{outdir}/{label}/reported.json"
    try:
        payload = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    items = payload.get("findings", payload if isinstance(payload, list) else [])
    return [item for item in items if isinstance(item, dict)]

seeded = []
for case_dir in sorted(glob.glob(f"{fixture}/cases/*/")):
    case_id = os.path.basename(case_dir.rstrip("/"))
    overrides = set(json.load(open(f"{case_dir}/ground-truth.json", encoding="utf-8"))["overrides"])
    candidates = [item for item in reported(case_id)
                  if os.path.basename(str(item.get("file", ""))) in overrides]
    if candidates:
        best = max(candidates, key=lambda item: RANK.get(str(item.get("severity")), 0))
        severity = str(best.get("severity"))
        summary = str(best.get("summary", ""))
    else:
        severity, summary = "none", ""
    seeded.append({"id": case_id, "severity": severity, "files": sorted(overrides),
                   "summary": summary, "all_reported": reported(case_id)})

clean = [{"severity": str(item.get("severity")),
          "file": str(item.get("file", "")),
          "summary": str(item.get("summary", ""))}
         for item in reported("clean")]

document = {"seeded": seeded, "clean": clean,
            "normalization": "adapter records every reported finding (all_reported) and the override file set (files) per case; the scorer, not the adapter, decides detection from that evidence -- see eval/scoring/reviewer.sh::reviewer_structured_gate",
            "runner_decides_gate_outcome": False,
            "scorer": "eval/scoring/reviewer.sh::reviewer_structured_gate",
            "fixture_revision": os.environ.get("REVIEWER_FIXTURE_REVISION", "unknown"),
            "fixture_integrity_checked": True}
with open(f"{outdir}/findings.json", "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  return "$healthy"
}
