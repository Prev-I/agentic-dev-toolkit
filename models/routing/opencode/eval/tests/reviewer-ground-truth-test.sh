#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/reviewer.sh"
fixture="$root/fixtures/reviewer-seeded-defects"

python3 - "$fixture/oracle.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["expected_ids"] == ["R-CONCURRENCY","R-AUTH","R-API","R-BOUNDARY","R-ERROR"]
assert d["required_seeded_detections"] == 5
assert d["allowed_clean_material_findings"] == 0
PY
python3 - "$fixture" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
fixture = json.load(open(root / "fixture.json"))
oracle = json.load(open(root / "oracle.json"))
filesystem_ids = sorted(path.name for path in (root / "cases").iterdir() if path.is_dir())
assert filesystem_ids == sorted(fixture["seeded_cases"]) == sorted(oracle["expected_ids"])
assert len(filesystem_ids) == oracle["required_seeded_detections"] == 5
for case_id in filesystem_ids:
    ground_truth = json.load(open(root / "cases" / case_id / "ground-truth.json"))
    assert ground_truth["expected_material_defect"]["id"] == case_id
PY
for id in R-CONCURRENCY R-AUTH R-API R-BOUNDARY R-ERROR; do
  assert_file "$fixture/cases/$id/ground-truth.json"
  python3 - "$fixture" "$id" <<'PY'
import json, pathlib, sys
root, case_id = pathlib.Path(sys.argv[1]), sys.argv[2]
data = json.load(open(root / "cases" / case_id / "ground-truth.json"))
assert len(data["overrides"]) == 1
override = data["overrides"][0]
assert (root / "clean" / override).is_file()
assert (root / "cases" / case_id / override).is_file()
PY
done
assert_file "$fixture/clean/ground-truth.json"

cat >"$fixture/.test-findings.json" <<'JSON'
{"seeded":[{"id":"R-CONCURRENCY","severity":"material"},{"id":"R-AUTH","severity":"blocking"},{"id":"R-API","severity":"material"},{"id":"R-BOUNDARY","severity":"material"},{"id":"R-ERROR","severity":"material"}],"clean":[{"id":"STYLE-1","severity":"suggestion"}]}
JSON
trap 'rm -f "$fixture/.test-findings.json"' EXIT
assert_eq pass "$(reviewer_structured_gate "$fixture/oracle.json" "$fixture/.test-findings.json")"
python3 - "$fixture/.test-findings.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["seeded"].pop(); json.dump(d,open(p,"w"))
PY
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$fixture/.test-findings.json")"
python3 - "$fixture/.test-findings.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["seeded"].append({"id":"R-ERROR","severity":"material"}); d["clean"].append({"id":"UNEXPECTED","severity":"material"}); json.dump(d,open(p,"w"))
PY
assert_eq block "$(reviewer_structured_gate "$fixture/oracle.json" "$fixture/.test-findings.json")"
printf 'PASS: Reviewer ground truth\n'
