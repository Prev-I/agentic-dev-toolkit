#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
fixture="$root/fixtures/build-workloads/build-restoration-gate"
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
cp -R "$fixture/snapshot/." "$workspace/"

if bash "$workspace/tests/acceptance.sh"; then fail "acceptance test was not initially failing"; fi
bash "$workspace/tests/regression.sh"

cat >>"$workspace/lib/math.sh" <<'SOLUTION'
double() {
  printf '%s\n' "$(( $1 * 2 ))"
}
SOLUTION
bash "$fixture/oracle.sh" "$workspace"

printf 'changed\n' >>"$workspace/README.md"
if bash "$fixture/oracle.sh" "$workspace"; then fail "forbidden-scope modification accepted"; fi
printf 'PASS: deterministic Build fixture oracle\n'
