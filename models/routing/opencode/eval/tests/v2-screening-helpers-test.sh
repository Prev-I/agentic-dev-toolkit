#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
adapter="$root/runtime/opencode-v2-adapter"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/budget-ledger.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/budget-ledger.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/provenance.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/provenance.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/classify-capability-failure.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/classify-capability-failure.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/verify-freeze-manifest.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/verify-freeze-manifest.sh"

# The server-free helpers the screening runner builds on: ledger, run record,
# freeze manifest, failure classifier and tree-patch capture.

workdir=$(mktemp -d)
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

# ledger
mkdir "$workdir/ldir"
ledger="$workdir/ldir/ledger.json"
ledger_init "$ledger" '{"candidate_a": 10}'
ledger_append "$ledger" candidate_a call1 fakep 4.5
assert_eq 4.5 "$(ledger_spent "$ledger" candidate_a)"
ledger_admit "$ledger" candidate_a 5 || fail "admit 5 should succeed"
if ledger_admit "$ledger" candidate_a 6; then fail "admit 6 should fail"; fi
ledger_init "$ledger" '{"candidate_a": 99}'
assert_eq 4.5 "$(ledger_spent "$ledger" candidate_a)"
ledger_admit "$ledger" candidate_a 5.5 || fail "admit 5.5 should succeed at the cap"
rc=0; ledger_admit "$ledger" candidate_a 6 || rc=$?
assert_eq 1 "$rc"
rc=0; ledger_admit "$ledger" nobody 1 || rc=$?
assert_eq 2 "$rc"
rc=0; ledger_admit "$ledger" candidate_a abc || rc=$?
assert_eq 2 "$rc"
rc=0; ledger_admit "$workdir/missing.json" candidate_a 1 || rc=$?
assert_eq 2 "$rc"
assert_eq ledger.json "$(ls -A "$workdir/ldir")"
assert_eq 2.6 "$(ledger_credits_from_cost 0.026)"
assert_eq 7.0 "$(ledger_credits_from_cost 0.07)"
assert_eq null "$(ledger_credits_from_cost null)"
assert_eq null "$(ledger_credits_from_cost '')"

# run record
record=$(emit_run_record prof d1 abc 2.3.0 runner fakep model variant)
assert_eq d1 "$(jq -r .profile_digest <<<"$record")"
assert_eq opencode_reported "$(jq -r .pricing_regime <<<"$record")"
assert_eq fakep "$(jq -r .provider <<<"$record")"

# freeze manifest
repo="$workdir/repo"
recdir="$workdir/rec"
mkdir -p "$repo" "$recdir"
printf 'one\n' >"$repo/a.txt"
printf 'two\n' >"$recdir/b.txt"
manifest="$workdir/manifest.json"
write_freeze_manifest "$repo" "$recdir" exp-1 "$manifest" "$repo/a.txt" "$recdir/b.txt"
assert_eq PRE_DISPATCH_FREEZE "$(jq -r .status "$manifest")"
assert_eq record:b.txt "$(jq -r '.files[1].path' "$manifest")"
assert_eq a.txt "$(jq -r '.files[0].path' "$manifest")"
verify_freeze_manifest "$repo" "$manifest" "$recdir" || fail "verify should pass"
printf 'twX\n' >"$recdir/b.txt"
out=$(verify_freeze_manifest "$repo" "$manifest" "$recdir" 2>&1) && fail "tampered record should fail"
assert_contains "$out" "freeze digest mismatch: record:"
printf '%s' '{"files":[{"path":"../outside","sha256":"x"}]}' >"$workdir/bad.json"
out=$(verify_freeze_manifest "$repo" "$workdir/bad.json" "$recdir" 2>&1) && fail "escaping path should fail"
assert_contains "$out" "invalid freeze path"

# classifier
printf '%s' '{"error_text":"Model not found: x"}' >"$workdir/fail.json"
assert_eq MODEL_UNRESOLVABLE "$(classify_capability_failure "$workdir/fail.json")"
assert_eq CAPABILITY_REGRESSION "$(capability_stop_class MODEL_UNRESOLVABLE)"

# tree patch
mkdir -p "$workdir/before" "$workdir/after"
printf 'x\n' >"$workdir/before/f.txt"
printf 'y\n' >"$workdir/after/f.txt"
bash "$adapter/capture-tree-patch.sh" "$workdir/before" "$workdir/after" "$workdir/p.patch"
cp -R "$workdir/before" "$workdir/copy"
(cd "$workdir/copy" && patch -p1 -s <"$workdir/p.patch")
assert_eq y "$(cat "$workdir/copy/f.txt")"

printf 'v2 screening helpers: ok\n'
