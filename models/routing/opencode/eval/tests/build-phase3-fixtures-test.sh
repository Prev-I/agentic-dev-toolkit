#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"

# Phase-3 Build A/B preflight (docs/decisions/2026-09-04-phase3-build-ab-preflight.md):
# build-feature and build-bugfix previously existed only as bare fixture.json
# manifests (committed e347feb, 2026-09-02) with no snapshot, oracle, task, or
# regression content -- their own declared properties
# (known_repository_snapshot, acceptance_tests_initially_failing, etc.) were
# unverified claims, not evidence. This test mechanically proves the newly
# authored content actually satisfies what the manifest claims, for both
# fixtures, before any live dispatch is proposed against them.

fixtures="$root/fixtures/build-workloads"

check_fixture() {
  local id=$1 apply_fix=$2 touch_forbidden=$3
  local dir="$fixtures/$id"
  assert_file "$dir/task.md"
  assert_file "$dir/oracle.sh"
  assert_file "$dir/snapshot/README.md"
  assert_file "$dir/snapshot/tests/acceptance.sh"
  assert_file "$dir/snapshot/tests/regression.sh"

  # acceptance_tests_initially_failing: true -- must genuinely fail as-shipped.
  if bash "$dir/snapshot/tests/acceptance.sh" >/dev/null 2>&1; then
    fail "$id: acceptance.sh must fail against the unmodified starting snapshot"
  fi

  # regression.sh must PASS as-shipped -- it tests pre-existing behavior,
  # not the thing the task asks for.
  bash "$dir/snapshot/tests/regression.sh" >/dev/null 2>&1 \
    || fail "$id: regression.sh must pass against the unmodified starting snapshot"

  local ws
  ws=$(mktemp -d)

  # oracle.sh must FAIL against the unmodified starting snapshot (the task
  # is not already done).
  cp -r "$dir/snapshot/." "$ws/"
  if bash "$dir/oracle.sh" "$ws" >/dev/null 2>&1; then
    rm -rf "$ws"
    fail "$id: oracle.sh must fail against the unmodified starting snapshot"
  fi

  # oracle.sh must PASS once the task is correctly completed.
  "$apply_fix" "$ws"
  bash "$dir/oracle.sh" "$ws" >/dev/null 2>&1 \
    || { rm -rf "$ws"; fail "$id: oracle.sh must pass once the task is correctly completed"; }

  # oracle.sh must FAIL if forbidden scope is touched, even with the task
  # otherwise correctly completed.
  "$touch_forbidden" "$ws"
  if bash "$dir/oracle.sh" "$ws" >/dev/null 2>&1; then
    rm -rf "$ws"
    fail "$id: oracle.sh must fail when forbidden scope is modified"
  fi
  rm -rf "$ws"
}

fix_feature() {
  cat >> "$1/lib/strings.sh" <<'EOF'

reverse() {
  local s=$1 rev=""
  for (( i=${#s}-1; i>=0; i-- )); do rev+="${s:$i:1}"; done
  printf '%s\n' "$rev"
}
EOF
}
touch_forbidden_feature() { printf 'unauthorized change\n' >> "$1/README.md"; }

check_fixture build-feature fix_feature touch_forbidden_feature

fix_bugfix() {
  python3 -c '
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("(( $1 >= 0 ))", "(( $1 > 0 ))")
open(path, "w", encoding="utf-8").write(text)
' "$1/lib/validate.sh"
}
# Behavior-PRESERVING rewrite: `[[ "${1// }" == "" ]]` accepts exactly the
# same inputs as the original `[[ -z "${1// }" ]]` (both strip spaces, then
# test emptiness) -- verified directly. This isolates what this check
# claims to prove: the oracle's forbidden-scope TEXT comparison must catch
# a semantically-equivalent rewrite of is_blank, not merely a behavior
# change regression.sh would have caught anyway for an unrelated reason.
touch_forbidden_bugfix() {
  python3 -c '
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"is_blank\(\)\s*\{.*?\n\}", "is_blank() {\n  [[ \"${1// }\" == \"\" ]]\n}", text, flags=re.S)
open(path, "w", encoding="utf-8").write(text)
' "$1/lib/validate.sh"
}

check_fixture build-bugfix fix_bugfix touch_forbidden_bugfix

printf 'PASS: Phase-3 Build fixtures (build-feature, build-bugfix) are genuinely dispatchable\n'
