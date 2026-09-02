#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

validate_build_fixture() {
  python3 - "$1" <<'PY'
import json
import sys

required = {
    "known_repository_snapshot",
    "bounded_task",
    "acceptance_tests_initially_failing",
    "regression_command",
    "required_artifacts",
    "required_behavior_tests",
    "forbidden_scope_assertions",
}
data = json.load(open(sys.argv[1], encoding="utf-8"))
missing = sorted(required - data.keys())
if missing:
    raise SystemExit("missing fixture fields: " + ", ".join(missing))
for field in required - {"regression_command"}:
    if data[field] is not True:
        raise SystemExit(f"fixture field must be true: {field}")
if not isinstance(data["regression_command"], str) or not data["regression_command"]:
    raise SystemExit("regression_command must be a non-empty string")
PY
}

build_control_interpretation() {
  local opus_status=$1 sonnet_passes=$2
  [[ "$opus_status" == blocked ]] || { printf 'inadmissible\n'; return; }
  case "$sonnet_passes" in
    2|3) printf 'practically-passable-open-remediation\n' ;;
    1) printf 'ambiguous-fixture-difficulty\n' ;;
    0) printf 'strong-fixture-finding-repair\n' ;;
    *) printf 'inadmissible\n' ;;
  esac
}

phase_evidence_admissible() {
  local fixture=$1 target_phase=$2
  python3 - "$fixture" "$target_phase" <<'PY'
import json
import sys

phase = json.load(open(sys.argv[1], encoding="utf-8"))["phase"]
target = sys.argv[2]
raise SystemExit(0 if (target == "R" and phase.startswith("R-")) or
                 (target == "3" and phase.startswith("3-")) else 1)
PY
}
