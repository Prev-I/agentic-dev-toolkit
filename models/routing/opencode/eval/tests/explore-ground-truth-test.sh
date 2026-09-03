#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/scoring/explore.sh"
oracle="$root/fixtures/explore-dependency-chain/oracle.json"
w=$(mktemp); trap 'rm -f "$w"' EXIT
cat >"$w" <<'JSON'
{"ordered_path":["entry","facade","service","adapter","protocol"],"reported_hops":4,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}
JSON
assert_eq pass "$(explore_gate "$oracle" "$w")"
for mutation in missing order hops symbol value; do
  python3 - "$w" "$mutation" <<'PY'
import json,sys
p,m=sys.argv[1:]
d={"ordered_path":["entry","facade","service","adapter","protocol"],"reported_hops":4,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}
if m=="missing": d["ordered_path"].remove("service")
elif m=="order": d["ordered_path"][1:3]=reversed(d["ordered_path"][1:3])
elif m=="hops": d["reported_hops"]=3
elif m=="symbol": d["terminal_symbol"]="API_VERSION"
else: d["terminal_value"]="v2"
json.dump(d,open(p,"w"))
PY
  assert_eq block "$(explore_gate "$oracle" "$w")"
done
printf 'PASS: Explore ground truth\n'
