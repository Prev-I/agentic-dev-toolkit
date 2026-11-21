#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh
source "$root/tests/test-lib.sh"
adapter="$root/runtime/opencode-v2-adapter"
bundle_dir=$(cd "$root/../v2" && pwd)
profile="$bundle_dir/opencode.jsonc"
targets="$bundle_dir/manifests/current-routing-targets.json"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/activate-profile.sh
source "$adapter/activate-profile.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/check-alignment.sh
source "$adapter/check-alignment.sh"

# check_alignment_v2 compares the installed OpenCode 2 config with the V2
# bundle. Pinned: routing-owned drift is DRIFT (including a missing
# breakglass deny and agent frontmatter), prose is STALE, user-owned keys are
# never reported, and a V1-shaped config is DRIFT with a pointer to the
# converter.

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
live="$workdir/xdg/opencode"
cfg="$live/opencode.jsonc"

setup_aligned() {
  rm -rf "$workdir/xdg" "$workdir/backup"
  mkdir -p "$live/agents"
  activate_profile_v2 --profile "$profile" --targets "$targets" --config-root "$live" \
    --backup-root "$workdir/backup" --model-routing "$live/model-routing.md" >/dev/null
  cp "$bundle_dir"/.opencode/agents/*.md "$live/agents/"
  cp "$bundle_dir/.opencode/model-routing.md" "$live/model-routing.md"
}

run_check() {
  set +e
  check_alignment_v2 --profile "$profile" --targets "$targets" \
    --bundle-root "$bundle_dir/.opencode" --live-config "$cfg" \
    --live-support-root "$live" --json "$workdir/report.json" >"$workdir/out.txt" 2>&1
  local rc=$?
  set -e
  return $rc
}

report_status() {
  python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$workdir/report.json"
}

# edit_config PYTHON_STATEMENTS: mutate the live config as a dict `d`, rewrite it as plain JSON.
edit_config() {
  python3 -B - "$cfg" "$1" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["ADAPTER"])
import v2config
d = v2config.load(sys.argv[1])
exec(sys.argv[2])
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
PY
}
export ADAPTER="$adapter"

setup_aligned
run_check || { cat "$workdir/out.txt"; fail "an activated install with the bundle copied must be ALIGNED"; }
[[ "$(report_status)" == ALIGNED ]] || fail "expected ALIGNED, got $(report_status)"

# --- routing-owned config keys --------------------------------------------
setup_aligned
edit_config 'd["agents"]["reviewer"]["model"]["variant"] = "low"'
run_check && fail "a changed role variant must be DRIFT"
[[ "$(report_status)" == DRIFT ]] || fail "expected DRIFT, got $(report_status)"
grep -q 'agents.reviewer' "$workdir/out.txt" || fail "drift must name the role"

setup_aligned
edit_config 'd["agents"].pop("expert")'
run_check && fail "a missing declared role must be DRIFT"
grep -q 'agents.expert' "$workdir/out.txt" || fail "drift must name the missing role"

setup_aligned
edit_config 'd["model"]["model"] = "other"'
run_check && fail "a changed default model must be DRIFT"

setup_aligned
edit_config 'd["permissions"] = [e for e in d["permissions"] if not (e["action"] == "subagent" and e.get("resource") == "breakglass")]'
run_check && fail "a removed subagent breakglass deny must be DRIFT"
grep -q 'subagent' "$workdir/out.txt" || fail "drift must name the subagent rules"

# The subagent list is order-sensitive: the last match wins.
setup_aligned
edit_config 'sub = [e for e in d["permissions"] if e["action"] == "subagent"]; rest = [e for e in d["permissions"] if e["action"] != "subagent"]; d["permissions"] = rest + sub[::-1]'
run_check && fail "reordered subagent rules must be DRIFT"

setup_aligned
edit_config 'd["instructions"] = []'
run_check && fail "a removed model-routing.md instruction must be DRIFT"
grep -q 'instructions' "$workdir/out.txt" || fail "drift must name instructions"

# --- agent markdown --------------------------------------------------------
setup_aligned
sed -i '$a An extra sentence in the body only.' "$live/agents/reviewer.md"
run_check || fail "a body-only markdown change must be STALE and exit 0"
[[ "$(report_status)" == STALE ]] || fail "expected STALE, got $(report_status)"

setup_aligned
sed -i '0,/effect: deny/s//effect: allow/' "$live/agents/reviewer.md"
run_check && fail "a changed markdown permissions entry must be DRIFT"
grep -q 'agents/reviewer.md' "$workdir/out.txt" || fail "drift must name the file"

setup_aligned
sed -i 's/^description: .*/description: something else/' "$live/agents/scout.md"
run_check && fail "a changed markdown description must be DRIFT"

setup_aligned
rm "$live/agents/scout.md"
run_check && fail "a missing installed agent file must be DRIFT"
grep -q 'agents/scout.md' "$workdir/out.txt" || fail "drift must name the missing file"

setup_aligned
sed -i 's/^permissions:/permission:/' "$live/agents/expert.md"
run_check && fail "V1-shaped installed frontmatter must be DRIFT"
[[ "$(report_status)" == DRIFT ]] || fail "expected DRIFT, got $(report_status)"

setup_aligned
printf -- '---\nmodel: x/y\n---\nbody\n' >"$live/agents/expert.md"
run_check && fail "a model: key in installed frontmatter must be DRIFT"

setup_aligned
printf 'no frontmatter at all\n' >"$live/agents/expert.md"
run_check && fail "an unparseable installed agent file must be DRIFT, not a crash"
grep -q 'agents/expert.md' "$workdir/out.txt" || fail "drift must name the unparseable file"
grep -qi 'Traceback' "$workdir/out.txt" && fail "an unparseable file must not crash the check"

# --- model-routing.md ------------------------------------------------------
setup_aligned
rm "$live/model-routing.md"
run_check && fail "a missing model-routing.md must be DRIFT"

setup_aligned
printf 'stale policy prose\n' >"$live/model-routing.md"
run_check || fail "differing model-routing.md prose must be STALE"
[[ "$(report_status)" == STALE ]] || fail "expected STALE, got $(report_status)"

# --- V1-shaped live config -------------------------------------------------
setup_aligned
printf '{"model": "p/m", "agent": {}, "permission": {}}\n' >"$cfg"
run_check && fail "a V1-shaped live config must be DRIFT"
grep -q 'live config is OpenCode 1.x-shaped; run convert-v1-config' "$workdir/out.txt" \
  || fail "V1 drift must carry the conversion message"

# --- user-owned keys are never reported ------------------------------------
setup_aligned
edit_config 'd["providers"] = {"mine": {"name": "x"}}; d["agents"]["my-own"] = {"model": {"providerID": "a", "model": "b"}}; d["permissions"].insert(0, {"action": "websearch", "resource": "*", "effect": "deny"}); d["websearch"] = {"x": 1}'
run_check || { cat "$workdir/out.txt"; fail "user-owned changes must not be drift"; }
[[ "$(report_status)" == ALIGNED ]] || fail "user-owned changes must leave ALIGNED, got $(report_status)"

# --- usage and absence -----------------------------------------------------
setup_aligned
rm "$cfg"
run_check && fail "an absent configuration must fail"
set +e; check_alignment_v2 --profile "$profile" --targets "$targets" --bundle-root "$bundle_dir/.opencode" \
  --live-config "$cfg" >/dev/null 2>&1; rc=$?; set -e
[[ $rc == 2 ]] || fail "an absent configuration must exit 2, got $rc"
set +e; check_alignment_v2 --bogus >/dev/null 2>&1; rc=$?; set -e
[[ $rc == 2 ]] || fail "an unknown option must exit 2, got $rc"

# --- never repairs ---------------------------------------------------------
setup_aligned
edit_config 'd["model"]["model"] = "other"'
before=$(sha256sum "$cfg" | cut -d' ' -f1)
run_check || true
[[ "$before" == "$(sha256sum "$cfg" | cut -d' ' -f1)" ]] || fail "the check must never modify the installed config"

# --- the entry point reports against v2/ -----------------------------------
setup_aligned
set +e
XDG_CONFIG_HOME="$workdir/xdg" bash "$root/check-alignment.sh" --json "$workdir/entry.json" >"$workdir/entry.txt" 2>&1
rc=$?
set -e
[[ $rc == 0 ]] || { cat "$workdir/entry.txt"; fail "the entry point on an aligned fixture must exit 0, got $rc"; }
grep -q 'v2/opencode.jsonc' "$workdir/entry.json" || fail "the entry point JSON must name v2/opencode.jsonc"
touch "$live/opencode.json"
set +e
XDG_CONFIG_HOME="$workdir/xdg" bash "$root/check-alignment.sh" >/dev/null 2>&1
rc=$?
set -e
[[ $rc == 2 ]] || fail "an ambiguous config root must exit 2, got $rc"

printf 'PASS: V2 alignment check (drift vs stale, user-owned keys never flagged)\n'
