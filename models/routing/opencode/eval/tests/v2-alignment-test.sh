#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
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

setup_aligned() {   # setup_aligned [MODEL_ROUTING_ARG]
  rm -rf "$workdir/xdg" "$workdir/backup"
  mkdir -p "$live/agents"
  cp "$bundle_dir"/.opencode/agents/*.md "$live/agents/"
  cp "$bundle_dir/.opencode/model-routing.md" "$live/model-routing.md"
  activate_profile_v2 --profile "$profile" --targets "$targets" --config-root "$live" \
    --backup-root "$workdir/backup" --model-routing "${1:-$live/model-routing.md}" >/dev/null
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
rc=0; run_check || rc=$?
[[ $rc == 1 ]] || fail "a changed role variant must exit 1, got $rc"
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

# A later top-level `*` allow re-opens breakglass even though the subagent
# entries still match: DRIFT naming the deciding entry.
setup_aligned
edit_config 'd["permissions"].append({"action": "*", "resource": "*", "effect": "allow"})'
rc=0; run_check || rc=$?
[[ $rc == 1 ]] || fail "a trailing * allow must exit 1, got $rc"
[[ "$(report_status)" == DRIFT ]] || fail "expected DRIFT, got $(report_status)"
grep -q 'permissions\[breakglass\]' "$workdir/out.txt" || fail "drift must name permissions[breakglass]"
grep -qF 'the deciding top-level entry for a subagent call to breakglass is {"action": "*", "resource": "*", "effect": "allow"}, not a deny' \
  "$workdir/out.txt" || { cat "$workdir/out.txt"; fail "drift must name the deciding entry"; }

# The subagent list is order-sensitive: the last match wins.
setup_aligned
edit_config 'sub = [e for e in d["permissions"] if e["action"] == "subagent"]; rest = [e for e in d["permissions"] if e["action"] != "subagent"]; d["permissions"] = rest + sub[::-1]'
run_check && fail "reordered subagent rules must be DRIFT"

setup_aligned
edit_config 'd["instructions"] = []'
run_check && fail "a removed model-routing.md instruction must be DRIFT"
grep -q 'instructions' "$workdir/out.txt" || fail "drift must name instructions"

setup_aligned
edit_config 'd["instructions"].append("/elsewhere/model-routing.md")'
run_check && fail "an extra model-routing.md instruction must be DRIFT"
grep -q 'extra model-routing.md entry' "$workdir/out.txt" || fail "drift must say the entry is extra"

setup_aligned
edit_config 'd["instructions"] = [e + "/" for e in d["instructions"]]'
run_check && fail "a trailing-slash instruction is user-owned, so the expected entry is missing: DRIFT"
grep -q 'expected model-routing.md entry missing' "$workdir/out.txt" || fail "drift must say the entry is missing"

setup_aligned
edit_config 'd["instructions"].append("docs/model-routing.md/")'
run_check || fail "a trailing-slash instruction beside the exact entry is user-owned and must be ignored"

# A non-normalised --model-routing (double slash) is normalised by activation,
# so the result is ALIGNED.
setup_aligned "$live//model-routing.md"
run_check || { cat "$workdir/out.txt"; fail "a double-slash --model-routing must activate ALIGNED"; }
[[ "$(report_status)" == ALIGNED ]] || fail "expected ALIGNED, got $(report_status)"

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
printf -- '---\ndescription: d\npermission:\n  edit: deny\n---\nbody\n' >"$live/agents/expert.md"
run_check && fail "V1-shaped installed frontmatter must be DRIFT"
[[ "$(report_status)" == DRIFT ]] || fail "expected DRIFT, got $(report_status)"
grep -q '1.x-shaped frontmatter' "$workdir/out.txt" || fail "the permission: branch must say 1.x-shaped"

setup_aligned
printf -- '---\nmodel: x/y\n---\nbody\n' >"$live/agents/expert.md"
run_check && fail "a model: key in installed frontmatter must be DRIFT"
grep -q 'keeps model routing in opencode.jsonc' "$workdir/out.txt" || fail "the model: branch must say where routing lives"

# Invalid UTF-8 is DRIFT naming the file, never a crash.
setup_aligned
printf -- '---\ndescription: \x97\n---\nbody\n' >"$live/agents/expert.md"
rc=0; run_check || rc=$?
[[ $rc == 1 ]] || fail "undecodable agent file must exit 1, got $rc"
grep -q 'agents/expert.md' "$workdir/out.txt" || fail "drift must name the undecodable file"
grep -q 'not valid UTF-8' "$workdir/out.txt" || fail "drift must say not valid UTF-8"
grep -q Traceback "$workdir/out.txt" && fail "undecodable file must not crash"
setup_aligned
printf 'bad \x97 byte\n' >"$live/model-routing.md"
rc=0; run_check || rc=$?
[[ $rc == 1 ]] || fail "undecodable model-routing.md must exit 1, got $rc"
grep -q 'not valid UTF-8' "$workdir/out.txt" || fail "drift must say not valid UTF-8"
grep -q Traceback "$workdir/out.txt" && fail "undecodable model-routing.md must not crash"

# A BOM on an otherwise matching installed agent file is not drift.
setup_aligned
{ printf '\xef\xbb\xbf'; cat "$bundle_dir/.opencode/agents/expert.md"; } >"$live/agents/expert.md"
run_check || { cat "$workdir/out.txt"; fail "a BOM-only difference must not be DRIFT"; }
[[ "$(report_status)" == ALIGNED ]] || fail "BOM-only difference must be ALIGNED, got $(report_status)"

# Installed-only agent files for a routed role can shadow its row.
setup_aligned
printf -- '---\ndescription: x\npermissions:\n  - action: edit\n    resource: "*"\n    effect: allow\n---\n' >"$live/agents/build.md"
rc=0; run_check || rc=$?
[[ $rc == 1 ]] || fail "shadowing installed-only agent must exit 1, got $rc"
grep -q 'agents/build.md' "$workdir/out.txt" || fail "drift must name build.md"
grep -q 'installed-only agent file' "$workdir/out.txt" || fail "drift must use the shadow wording"
setup_aligned
printf -- '---\ndescription: x\nmode: primary\n---\nbody\n' >"$live/agents/build.md"
run_check || fail "installed-only agent with only description/mode must not be DRIFT"
setup_aligned
printf 'no frontmatter\n' >"$live/agents/build.md"
run_check && fail "an unparseable installed-only routed agent must be DRIFT"
setup_aligned
ln -s "$workdir/nowhere.md" "$live/agents/build.md"
run_check && fail "an unreadable installed-only routed agent must be DRIFT"
grep -q 'cannot be read' "$workdir/out.txt" || fail "drift must say cannot be read"
grep -q 'not valid UTF-8' "$workdir/out.txt" && fail "unreadable must not be reported as invalid UTF-8"
setup_aligned
mkdir "$live/agents/build.md"
run_check && fail "a directory named build.md must be DRIFT"
grep -q 'cannot be read' "$workdir/out.txt" || fail "directory case must say cannot be read"
setup_aligned
printf -- '---\ndescription: x\npermissions:\n  - action: edit\n    resource: "*"\n    effect: allow\n---\n' >"$live/agents/my-helper.md"
run_check || fail "a non-role installed-only agent must not be reported"
grep -q 'my-helper' "$workdir/out.txt" && fail "non-role agent must not appear in the report"

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
# A failed run (here: no installed config) removes an earlier --json report.
setup_aligned
run_check || fail "aligned fixture must pass"
[[ -f "$workdir/report.json" ]] || fail "no report written"
rm "$cfg"
rc=0; run_check || rc=$?
[[ $rc == 2 ]] || fail "an absent configuration must exit 2, got $rc"
[[ ! -e "$workdir/report.json" ]] || fail "a failed run left the earlier ALIGNED report behind"
set +e; check_alignment_v2 --profile "$profile" --targets "$targets" --bundle-root "$bundle_dir/.opencode" \
  --live-config "$cfg" >/dev/null 2>&1; rc=$?; set -e
[[ $rc == 2 ]] || fail "an absent configuration must exit 2, got $rc"
set +e; check_alignment_v2 --bogus >/dev/null 2>&1; rc=$?; set -e
[[ $rc == 2 ]] || fail "an unknown option must exit 2, got $rc"

# --- no import from the current directory (python3 -I) --------------------
# A json.py planted in the working directory must never be imported.
setup_aligned
plant="$workdir/plant"
mkdir -p "$plant"
printf 'open(%s, "w").write("imported")\nfrom importlib import import_module as _i\n' \
  "'$plant/MARKER'" >"$plant/json.py"
(cd "$plant" && run_check) || { cat "$workdir/out.txt"; fail "alignment from a planted directory must pass"; }
[[ ! -e "$plant/MARKER" ]] || fail "check_alignment_v2 imported json.py from the current directory"

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
XDG_CONFIG_HOME="$workdir/xdg" bash "$root/check-alignment.sh" >"$workdir/entry.txt" 2>&1
rc=$?
set -e
[[ $rc == 2 ]] || fail "an ambiguous config root must exit 2, got $rc"
grep -q ambiguous "$workdir/entry.txt" || fail "ambiguity message missing"

# A symlinked config, dangling included, is refused with exit 2.
setup_aligned
mv "$cfg" "$workdir/real.jsonc"; ln -s "$workdir/real.jsonc" "$cfg"
set +e
XDG_CONFIG_HOME="$workdir/xdg" bash "$root/check-alignment.sh" >"$workdir/entry.txt" 2>&1
rc=$?
set -e
[[ $rc == 2 ]] || fail "a symlinked config must exit 2, got $rc"
grep -q 'is a symlink' "$workdir/entry.txt" || fail "symlink message missing"
setup_aligned
ln -s "$workdir/nowhere.json" "$live/opencode.json"
set +e
XDG_CONFIG_HOME="$workdir/xdg" bash "$root/check-alignment.sh" >"$workdir/entry.txt" 2>&1
rc=$?
set -e
[[ $rc == 2 ]] || fail "a dangling symlink beside a config must exit 2, got $rc"
grep -q 'is a symlink' "$workdir/entry.txt" || fail "dangling symlink message missing"

printf 'PASS: V2 alignment check (drift vs stale, user-owned keys never flagged)\n'
