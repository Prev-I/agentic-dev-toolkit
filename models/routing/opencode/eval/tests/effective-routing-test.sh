#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/verify-effective-routing.sh"
source "$root/runtime/opencode-v1-adapter/verify-effective-routing.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
targets="$root/manifests/phase-r-routing-targets.json"
mkdir -p "$workspace/neutral" "$workspace/project"

# A fake runtime that resolves each role from a JSON table, optionally with a
# project-local override when invoked from the project directory.
write_fake() {
  local overrides=$1
  cat >"$workspace/opencode" <<FAKE
#!/usr/bin/env bash
if [[ "\${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
TARGETS="$targets" OVERRIDES='$overrides' PROJECT="$workspace/project" \\
  python3 -c '
import json, os, sys
role = sys.argv[1]
targets = json.load(open(os.environ["TARGETS"]))["agents"]
row = dict(targets[role])
overrides = json.loads(os.environ["OVERRIDES"] or "{}")
if os.getcwd() == os.environ["PROJECT"] and role in overrides:
    row.update(overrides[role])
provider, model = row["model"].split("/", 1)
print(json.dumps({"name": role, "mode": row["mode"] or "subagent",
                  "model": {"providerID": provider, "modelID": model},
                  "variant": row["variant"],
                  "permission": [{"permission": "task", "action": "deny", "pattern": "breakglass"}]}))
' "\$3"
FAKE
  chmod +x "$workspace/opencode"
}

write_fake '{}'
good="$workspace/good"
OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
  --outdir "$good" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project" \
  || fail "matching effective routing reported failure"
assert_contains "$(<"$good/effective-routing.json")" '"status": "PASS"'
assert_eq '11' "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["roles"]))' "$good/effective-routing.json")"

# A project override on any role must fail the routing-resolution gate.
write_fake '{"scout": {"variant": "medium"}}'
override="$workspace/override"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$override" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted a project routing override"
fi
assert_contains "$(<"$override/effective-routing.json")" '"status": "PROJECT_OVERRIDE"'

# A wrong effective value anywhere must fail.
write_fake '{}'
sed -i 's/"variant": row\["variant"\]/"variant": ("low" if role == "compaction" else row["variant"])/' "$workspace/opencode"
wrong="$workspace/wrong"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$wrong" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted compaction resolving to the wrong variant"
fi
assert_contains "$(<"$wrong/effective-routing.json")" 'compaction'

# The forbidden Reviewer/Expert state must fail even if each row looks plausible.
write_fake '{}'
sed -i 's/row = dict(targets\[role\])/row = dict(targets[role])\nif role == "expert": row["variant"] = "high"/' "$workspace/opencode"
forbidden="$workspace/forbidden"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$forbidden" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted Reviewer Sol high together with Expert Sol high"
fi

printf 'PASS: effective routing verification\n'
