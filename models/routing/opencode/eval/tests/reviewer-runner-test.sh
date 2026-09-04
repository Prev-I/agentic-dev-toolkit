#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/reviewer.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"

# A fake reviewer that flags the overridden file in every seeded sandbox and
# stays silent on the clean control. It has no identity marker to read — it
# infers which file (if any) was overridden the same way a real reviewer
# would: by inspecting the content actually present in its own sandbox.
cat >"$workspace/opencode-detects" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$*" >>"${REVIEWER_ARGS_SINK:-/dev/null}"
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
file=""
if [[ -f counter.sh ]] && ! grep -q flock counter.sh; then file=counter.sh
elif [[ -f authorization.sh ]] && ! grep -q 'return 3' authorization.sh; then file=authorization.sh
elif [[ -f api.sh ]] && ! grep -q displayName api.sh; then file=api.sh
elif [[ -f pagination.sh ]] && ! grep -q '>= 1' pagination.sh; then file=pagination.sh
elif [[ -f storage.sh ]] && grep -q '2>/dev/null' storage.sh; then file=storage.sh
fi
if [[ -z "$file" ]]; then
  printf '%s\n' '{"type":"text","part":{"text":"{\"findings\":[]}"}}'
  exit 0
fi
python3 -c '
import json, sys
inner = json.dumps({"findings": [{"file": sys.argv[1], "severity": "material", "summary": "seeded defect"}]})
print(json.dumps({"type": "text", "part": {"text": inner}}))
' "$file"
FAKE
chmod +x "$workspace/opencode-detects"

out="$workspace/run"
REVIEWER_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-detects" \
  run_reviewer_gate --outdir "$out" --ledger "$ledger" \
  || fail "healthy reviewer dispatch reported failure"

assert_contains "$(<"$workspace/args.txt")" '--agent reviewer'
assert_file "$out/findings.json"

python3 - "$out/findings.json" <<'PY'
import json
import sys

findings = json.load(open(sys.argv[1], encoding="utf-8"))
seeded = {item["id"]: item for item in findings["seeded"]}
expected = {"R-CONCURRENCY", "R-AUTH", "R-API", "R-BOUNDARY", "R-ERROR"}
assert set(seeded) == expected, f"seeded ids {sorted(seeded)} != {sorted(expected)}"
assert all(item["severity"] == "material" for item in seeded.values()), seeded
assert all(item.get("summary") for item in seeded.values()), "verbatim summaries not preserved"
assert findings["clean"] == [], f"clean control should be empty, got {findings['clean']}"
PY

# The committed scorer — not the adapter — decides the outcome.
assert_eq 'pass' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$out/findings.json")"

# A reviewer that misses one defect (authorization.sh) still yields a healthy
# run; the scorer blocks it. Same content-inspection approach, no marker file.
cat >"$workspace/opencode-misses" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
file=""
if [[ -f counter.sh ]] && ! grep -q flock counter.sh; then file=counter.sh
elif [[ -f authorization.sh ]] && ! grep -q 'return 3' authorization.sh; then file=authorization.sh
elif [[ -f api.sh ]] && ! grep -q displayName api.sh; then file=api.sh
elif [[ -f pagination.sh ]] && ! grep -q '>= 1' pagination.sh; then file=pagination.sh
elif [[ -f storage.sh ]] && grep -q '2>/dev/null' storage.sh; then file=storage.sh
fi
if [[ -z "$file" || "$file" == authorization.sh ]]; then
  printf '%s\n' '{"type":"text","part":{"text":"{\"findings\":[]}"}}'
  exit 0
fi
python3 -c '
import json, sys
inner = json.dumps({"findings": [{"file": sys.argv[1], "severity": "blocking", "summary": "seeded defect"}]})
print(json.dumps({"type": "text", "part": {"text": inner}}))
' "$file"
FAKE
chmod +x "$workspace/opencode-misses"

miss="$workspace/miss"
OPENCODE_BIN="$workspace/opencode-misses" run_reviewer_gate --outdir "$miss" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
assert_eq 'block' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$miss/findings.json")"

# A false positive on the clean control is recorded faithfully.
cat >"$workspace/opencode-noisy" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
printf '%s\n' '{"type":"text","part":{"text":"{\"findings\":[{\"file\":\"counter.sh\",\"severity\":\"material\",\"summary\":\"imagined\"}]}"}}'
FAKE
chmod +x "$workspace/opencode-noisy"
noisy="$workspace/noisy"
OPENCODE_BIN="$workspace/opencode-noisy" run_reviewer_gate --outdir "$noisy" --ledger "$ledger" || true
assert_eq 'block' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$noisy/findings.json")"

# The adapter must never write an identity marker into a sandbox that a real
# reviewer dispatch would see — it must look exactly like the fixture content.
for run_dir in "$out" "$miss" "$noisy"; do
  leaked=$(find "$run_dir" -name '.case' 2>/dev/null || true)
  [[ -z "$leaked" ]] || fail "adapter leaked a sandbox identity marker: $leaked"
done

# The adapter must not embed the gate thresholds or the expected id list.
runner="$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
for forbidden in 'required_seeded_detections' 'allowed_clean_material_findings' 'R-CONCURRENCY' 'material_severities'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "reviewer runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: reviewer gate runner\n'
