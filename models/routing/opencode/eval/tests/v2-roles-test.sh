#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
repo=$(cd "$root/../../../.." && pwd)
roles="$root/runtime/opencode-v2-adapter/roles"

# The role definitions the screening runner consumes, the reviewer normaliser
# and the build scorer.

work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
trap 'rm -rf "${work:?}"' EXIT

resolve() { # expand the placeholders a role file may carry in a path
  local p=${1//\{eval\}/$root}
  p=${p//\{repo\}/$repo}
  p=${p//\{fixture\}/$fixture}
  [[ "$p" == /* ]] || p="$repo/$p"
  printf '%s' "$p"
}

# role_files_valid
fixture="$repo/$(jq -r .fixture "$roles/reviewer.json")"
oracle="$fixture/oracle.json"
jq -e . "$roles/reviewer.json" >/dev/null || fail "reviewer.json does not parse"
jq -e . "$roles/build.json" >/dev/null || fail "build.json does not parse"
assert_eq "$(jq -c '["clean"] + .expected_ids' "$oracle")" "$(jq -c '[.workloads[].id]' "$roles/reviewer.json")"
for role in reviewer build; do
  fixture="$repo/$(jq -r '.fixture // ""' "$roles/$role.json")"
  while IFS= read -r p; do
    [[ -e "$(resolve "$p")" ]] || fail "$role.json names a missing path: $p"
  done < <(jq -r '.workloads[] | .base, .prompt, .overlay[]' "$roles/$role.json";  jq -r '.frozen[]' "$roles/$role.json")
done
fixture="$repo/$(jq -r .fixture "$roles/reviewer.json")"
for id in $(jq -r '.expected_ids[]' "$oracle"); do
  overrides=$(jq -r '.overrides[]' "$fixture/cases/$id/ground-truth.json")
  overlays=$(jq -r --arg id "$id" '.workloads[] | select(.id == $id) | .overlay[] | split("/") | last' "$roles/reviewer.json")
  assert_eq "$overrides" "$overlays"
done
cmp "$roles/reviewer/request.txt" "$root/records/reviewer-cross-family-screening/reviewer-request.txt" || fail "reviewer prompt drifted"
for f in coding-prompt.txt gate-prompt.txt; do
  cmp "$roles/build/$f" "$root/records/opus55-gpt61-build-quality-screening/$f" || fail "$f drifted"
done

# normalise_and_score_reviewer
rec="$work/record"
for id in clean $(jq -r '.expected_ids[]' "$oracle"); do
  d="$rec/runs/01-$id-r1-fakep"
  mkdir -p "$d"
  if [[ "$id" == clean ]]; then
    printf '{"findings":[]}\n' >"$d/reported.json"
  else
    file=$(jq -r '.overrides[0]' "$fixture/cases/$id/ground-truth.json")
    witness=$(jq -r '.witness // "x"' "$fixture/cases/$id/ground-truth.json")
    jq -n --arg f "$file" --arg w "$witness" \
      '{findings:[{file:$f,severity:"material",summary:"defect",evidence:$w}]}' >"$d/reported.json"
  fi
done
norm() { python3 -I -B "$root/scoring/reviewer-normalise-oc2.py" "$rec" "$fixture" fakep 1; }
score() { python3 -I -B "$root/scoring/reviewer-v2.py" "$fixture" "$rec/findings-fakep-r1.json"; }
norm || fail "normaliser failed"
assert_eq pass "$(score | jq -r .gate)"
assert_eq "eval/scoring/reviewer-v2.py" "$(jq -r .scorer "$rec/findings-fakep-r1.json")"
rm -r "$rec/runs/01-R-API-r1-fakep"
norm || fail "normaliser failed on a missing report"
out=$(score)
assert_eq missed "$(jq -r '.attribution["R-API"]' <<<"$out")"
assert_eq block "$(jq -r .gate <<<"$out")"
assert_eq '["R-API"]' "$(jq -c .missing_runs "$rec/findings-fakep-r1.json")"

# normaliser_refuses_missing_clean_and_malformed
rec2="$work/record2"
cp -r "$rec" "$rec2"
rm -r "$rec2/runs/01-clean-r1-fakep" "$rec2/findings-fakep-r1.json"
rc=0; err=$(python3 -I -B "$root/scoring/reviewer-normalise-oc2.py" "$rec2" "$fixture" fakep 1 2>&1) || rc=$?
assert_eq 3 "$rc"
assert_contains "$err" "clean control missing"
[[ ! -e "$rec2/findings-fakep-r1.json" ]] || fail "findings written without the clean control"
mkdir -p "$rec2/runs/01-clean-r1-fakep"
printf '{"findings":"nope"}\n' >"$rec2/runs/01-clean-r1-fakep/reported.json"
rc=0; python3 -I -B "$root/scoring/reviewer-normalise-oc2.py" "$rec2" "$fixture" fakep 1 2>/dev/null || rc=$?
(( rc != 0 )) || fail "non-list findings accepted"
printf '{"findings":[]}\n' >"$rec2/runs/01-clean-r1-fakep/reported.json"
mkdir -p "$rec2/runs/02-clean-r1-fakep"
printf '{"findings":[]}\n' >"$rec2/runs/02-clean-r1-fakep/reported.json"
rc=0; python3 -I -B "$root/scoring/reviewer-normalise-oc2.py" "$rec2" "$fixture" fakep 1 2>/dev/null || rc=$?
(( rc != 0 )) || fail "ambiguous run match accepted"

# build_scorer_missing_commit_fails_closed
git init -q "$work/empty-repo"
mkdir -p "$work/brec/runs/01-gate-r1-k/dispatch"
rc=0
err=$(/usr/bin/python3 -I -B "$root/scoring/build-quality-oc2.py" --record "$work/brec" --repo "$work/empty-repo" 2>&1 >/dev/null) || rc=$?
assert_eq 1 "$rc"
assert_contains "$err" "reference commit not available"
[[ ! -e "$work/brec/scores" ]] || fail "scores written despite a missing commit"

# build_scorer_run_handling: plan_runs is exercised directly, so the controls do not run
plan() { # record
  python3 -I -B - "$root/scoring/build-quality-oc2.py" "$1" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('bq', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(json.dumps([[d.name, k, c] for d, k, c in module.plan_runs(Path(sys.argv[2]))], separators=(",", ":")))
PY
}
mkrun() { # record name classification
  mkdir -p "$1/runs/$2/dispatch"
  printf '{"classification":"%s"}\n' "$3" >"$1/runs/$2/dispatch/dispatch.json"
}
b1="$work/b1"; mkrun "$b1" 01-gate-r1-k OK
printf 'x' >"$b1/runs/01-gate-r1-k/dispatch/response.txt"
rc=0; plan "$b1" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"   # OK gate run without a patch
b2="$work/b2"; mkrun "$b2" 01-gate-r1-k TIMEOUT
assert_eq '[["01-gate-r1-k","gate","TIMEOUT"]]' "$(plan "$b2")"
b3="$work/b3"; mkrun "$b3" 01-coding-r1-gate-x OK; : >"$b3/runs/01-coding-r1-gate-x/work-product.patch"
assert_eq '[["01-coding-r1-gate-x","coding","OK"]]' "$(plan "$b3")"
b4="$work/b4"; mkdir -p "$b4/runs/stray"
rc=0; plan "$b4" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"   # unrecognised entry
b5="$work/b5"; mkdir -p "$b5/runs/01-gate-r1-k"
rc=0; plan "$b5" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"   # no dispatch record
rc=0; plan "$work/none" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"   # empty run set

# build_gate_classifier
gate_verdict() { # response patch-content
  local d="$work/gate"
  rm -rf "$d"; mkdir -p "$d/dispatch"
  printf '%s' "$1" >"$d/dispatch/response.txt"
  printf '%s' "$2" >"$d/work-product.patch"
  python3 -I -B - "$root/scoring/build-quality-oc2.py" "$d" <<'PY'
import importlib.util
import sys
spec = importlib.util.spec_from_file_location('bq', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.classify_gate(sys.argv[2]))
PY
}
assert_eq ADHERENT "$(gate_verdict "Should I proceed with this design?" "")"
assert_eq NON_ADHERENT "$(gate_verdict "Should I proceed with this design?" "diff --git a/x b/x")"

printf 'v2-roles-test: PASS\n'
