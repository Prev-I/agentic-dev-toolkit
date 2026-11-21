#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh
source "$root/tests/test-lib.sh"
adapter="$root/runtime/opencode-v2-adapter"
helper="$adapter/v2config.py"
profile="$root/../v2/opencode.jsonc"
targets="$root/../v2/manifests/current-routing-targets.json"
assert_file "$adapter/activate-profile.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/activate-profile.sh
source "$adapter/activate-profile.sh"

# activate-profile.sh (V2) rewrites a user's real OpenCode 2 config. The
# properties pinned here: only routing-owned keys change, everything else
# survives, V1-shaped and ambiguous targets are refused untouched, undeclared
# variants on declared providers are refused, and the write is atomic, backed
# up and provenance-stamped.

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
routing_md="$workspace/installed/model-routing.md"
profile_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile_id"])' "$targets")
profile_sha=$(sha256sum "$profile" | cut -d' ' -f1)

# Every mv the script runs is logged, so the test can see where the temp file
# lived. The shim execs the real mv.
real_mv=$(command -v mv)
shim="$workspace/shim"
mkdir -p "$shim"
cat >"$shim/mv" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$workspace/mv.log"
exec "$real_mv" "\$@"
SH
chmod +x "$shim/mv"

activate() {   # activate CONFIG_ROOT BACKUP_ROOT [PROFILE] [extra args...]
  local config_root=$1 backup_root=$2 source_profile=${3:-$profile}
  shift 3 2>/dev/null || shift $#
  PATH="$shim:$PATH" activate_profile_v2 --profile "$source_profile" --targets "$targets" \
    --config-root "$config_root" --backup-root "$backup_root" \
    --model-routing "$routing_md" "$@"
}

# --- Main merge onto a V2 config carrying user state -----------------------
main_root="$workspace/main/config"
mkdir -p "$main_root"
cat >"$main_root/opencode.jsonc" <<'JSONC'
{
  // a user comment that will not survive the rewrite
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["docs/house-style.md", ".opencode/model-routing.md"],
  "model": {"providerID": "some-vendor", "model": "old-model"},
  "providers": {
    "gewiss": {
      "name": "Gewiss gateway",
      "options": {"baseURL": "https://gateway.example.invalid/v1"},
      "models": {
        "gpt-sol": {
          "name": "GPT Sol",
          "variants": [
            {"id": "low", "settings": {"reasoningEffort": "low"}},
            {"id": "medium", "settings": {"reasoningEffort": "medium"}},
            {"id": "high", "settings": {"reasoningEffort": "high"}},
          ],
        },
      },
    },
  },
  "plugins": ["superpowers@git+https://github.com/obra/superpowers.git#v7.0.1"],
  "mcp": {"servers": {"example": {"type": "remote", "url": "https://example.invalid/mcp"}}},
  "permissions": [
    {"action": "websearch", "resource": "*", "effect": "allow"},
    {"action": "subagent", "resource": "breakglass", "effect": "allow"}
  ],
  "agents": {
    "build": {"model": {"providerID": "some-vendor", "model": "old-model"}, "note": "stale"},
    "custom-agent": {"model": {"providerID": "some-vendor", "model": "some-model"}, "note": "user-owned"}
  }
}
JSONC
chmod 640 "$main_root/opencode.jsonc"   # not mktemp's 600
cp "$main_root/opencode.jsonc" "$workspace/main-original.jsonc"
inode_before=$(stat -c %i "$main_root/opencode.jsonc")

rm -f "$workspace/mv.log"
activate "$main_root" "$workspace/main/backups" >"$workspace/out.txt"
out=$(<"$workspace/out.txt")
assert_contains "$out" "target=$main_root/opencode.jsonc"
assert_contains "$out" "before_sha256=$(sha256sum "$workspace/main-original.jsonc" | cut -d' ' -f1)"
assert_contains "$out" "after_sha256=$(sha256sum "$main_root/opencode.jsonc" | cut -d' ' -f1)"
backup_dir=$(grep '^backup_dir=' "$workspace/out.txt" | cut -d= -f2-)
assert_contains "$(basename "$backup_dir")" 'routing-'

# Backup: the original verbatim, its digest, and a manifest.
assert_file "$backup_dir/opencode.jsonc"
assert_file "$backup_dir/SHA256SUMS"
assert_file "$backup_dir/manifest.json"
cmp -s "$backup_dir/opencode.jsonc" "$workspace/main-original.jsonc" || fail "backup is not the original"
(cd "$backup_dir" && sha256sum -c --quiet SHA256SUMS) || fail "SHA256SUMS does not verify"

# Atomic write: the only mv moved a temp file from the target directory onto
# the target, the inode changed (rename, not rewrite) and nothing was left.
assert_eq 2 "$(wc -l <"$workspace/mv.log")"
mv_source=$(sed -n 1p "$workspace/mv.log")
assert_eq "$main_root" "$(dirname "$mv_source")"
assert_eq "$main_root/opencode.jsonc" "$(sed -n 2p "$workspace/mv.log")"
[[ ! -e "$mv_source" ]] || fail "temp file left behind: $mv_source"
assert_eq "opencode.jsonc" "$(ls -A "$main_root")"
[[ "$inode_before" != "$(stat -c %i "$main_root/opencode.jsonc")" ]] || fail "target rewritten in place"
assert_eq 640 "$(stat -c %a "$main_root/opencode.jsonc")"

# Header: leading // lines naming the profile id and the source digest.
head -n1 "$main_root/opencode.jsonc" | grep -q '^//' || fail "no // header"
header=$(sed -n '/^\/\//p' "$main_root/opencode.jsonc")
assert_contains "$header" "profile_id: $profile_id"
assert_contains "$header" "$profile_sha"
assert_contains "$header" "activation_stamp: ${backup_dir##*/routing-}"
assert_contains "$header" "Routing-owned keys"
assert_contains "$(tail -c1 "$main_root/opencode.jsonc" | od -An -c)" '\n'

python3 "$helper" load "$main_root/opencode.jsonc" >"$workspace/after.json"
python3 "$helper" load "$workspace/main-original.jsonc" >"$workspace/before.json"
python3 "$helper" load "$profile" >"$workspace/profile.json"
python3 - "$workspace/before.json" "$workspace/after.json" "$workspace/profile.json" \
          "$targets" "$routing_md" "$backup_dir/manifest.json" <<'PY'
import json
import sys

before, after, profile, targets = (json.load(open(p)) for p in sys.argv[1:5])
routing_md = sys.argv[5]
manifest = json.load(open(sys.argv[6]))
roles = list(targets["agents"])

def canon(value):
    return json.dumps(value, sort_keys=True)

# User-owned sections survive unchanged.
for key in ("providers", "plugins", "mcp", "$schema"):
    assert canon(after[key]) == canon(before[key]), key
assert canon(after["agents"]["custom-agent"]) == canon(before["agents"]["custom-agent"])

# Routing-owned: model and every declared role row, whole.
assert after["model"] == profile["model"], after["model"]
for role in roles:
    assert canon(after["agents"][role]) == canon(profile["agents"][role]), role
assert set(after["agents"]) == set(roles) | {"custom-agent"}, sorted(after["agents"])
assert "note" not in after["agents"]["build"]

# permissions: user entries first, then the profile's subagent entries in
# profile order. The stale subagent allow is gone, and so is every non-subagent
# profile entry beyond what the user already had.
profile_subagent = [e for e in profile["permissions"] if e["action"] == "subagent"]
assert profile_subagent, "profile declares no subagent entries"
expected = [{"action": "websearch", "resource": "*", "effect": "allow"}] + profile_subagent
assert after["permissions"] == expected, after["permissions"]
assert after["permissions"][-1] == {"action": "subagent", "resource": "breakglass", "effect": "deny"}

# instructions: the user entry, plus exactly one absolute routing path; the
# stale relative V1 entry is gone.
assert "docs/house-style.md" in after["instructions"], after["instructions"]
assert after["instructions"].count(routing_md) == 1, after["instructions"]
assert ".opencode/model-routing.md" not in after["instructions"], after["instructions"]
assert len(after["instructions"]) == 2, after["instructions"]

# No mixed shapes.
for key in ("agent", "provider", "permission", "plugin", "disabled_providers",
            "autoupdate", "server"):
    assert key not in after, key

assert manifest["profile_id"] == targets["profile_id"]
assert manifest["pre_activation_sha256"] and manifest["post_activation_sha256"]
PY
python3 -c 'import json,sys,hashlib; m=json.load(open(sys.argv[1])); assert m["source_profile_sha256"]==sys.argv[2], m' \
  "$backup_dir/manifest.json" "$profile_sha" || fail "manifest digest"

# Re-activation is idempotent on content (header aside).
activate "$main_root" "$workspace/main/backups" >/dev/null
python3 "$helper" load "$main_root/opencode.jsonc" >"$workspace/after2.json"
cmp -s "$workspace/after.json" "$workspace/after2.json" || fail "second activation changed content"

# --- V1-shaped target is refused and left untouched ------------------------
v1_root="$workspace/v1/config"
mkdir -p "$v1_root"
printf '{"agent":{}}' >"$v1_root/opencode.json"
v1_before=$(sha256sum "$v1_root/opencode.json")
rc=0
activate "$v1_root" "$workspace/v1/backups" >/dev/null 2>"$workspace/v1.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/v1.err")" convert-v1-config
assert_eq "$v1_before" "$(sha256sum "$v1_root/opencode.json")"
[[ ! -e "$workspace/v1/backups" ]] || fail "refused activation left a backup"
assert_eq "opencode.json" "$(ls -A "$v1_root")"

# --- Unparseable target is refused and left untouched ----------------------
bad_root="$workspace/bad/config"
mkdir -p "$bad_root"
printf '{ this is not valid JSON or JSONC at all' >"$bad_root/opencode.jsonc"
bad_before=$(sha256sum "$bad_root/opencode.jsonc")
rc=0
activate "$bad_root" "$workspace/bad/backups" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
assert_eq "$bad_before" "$(sha256sum "$bad_root/opencode.jsonc")"
assert_eq "opencode.jsonc" "$(ls -A "$bad_root")"

# --- Both opencode.json and opencode.jsonc: ambiguous ----------------------
both_root="$workspace/both/config"
mkdir -p "$both_root"
printf '{}\n' >"$both_root/opencode.json"
printf '{}\n' >"$both_root/opencode.jsonc"
rc=0
activate "$both_root" "$workspace/both/backups" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
assert_eq '{}' "$(<"$both_root/opencode.json")"
assert_eq '{}' "$(<"$both_root/opencode.jsonc")"

# --- Usage errors ---------------------------------------------------------
rc=0
PATH="$shim:$PATH" activate_profile_v2 --profile "$profile" --targets "$targets" \
  --config-root "$main_root" --backup-root "$workspace/x" \
  --model-routing relative/model-routing.md >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0
activate_profile_v2 --profile "$profile" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
rc=0
activate "$main_root" "$workspace/x" "$profile" --bogus >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"

# --- Dry run changes nothing ----------------------------------------------
dry_before=$(sha256sum "$main_root/opencode.jsonc")
activate "$main_root" "$workspace/dry/backups" "$profile" --dry-run >"$workspace/dry.txt"
assert_contains "$(<"$workspace/dry.txt")" 'dry_run=1'
assert_contains "$(<"$workspace/dry.txt")" "target=$main_root/opencode.jsonc"
assert_eq "$dry_before" "$(sha256sum "$main_root/opencode.jsonc")"
[[ ! -e "$workspace/dry/backups" ]] || fail "dry run created a backup"
assert_eq "opencode.jsonc" "$(ls -A "$main_root")"
dry_missing="$workspace/dry-missing/config"
mkdir -p "$dry_missing"
activate "$dry_missing" "$workspace/dry-missing/backups" "$profile" --dry-run >/dev/null
assert_eq "" "$(ls -A "$dry_missing")"

# --- Variant check against declared providers -----------------------------
python3 - "$workspace/profile.json" "$workspace/xhigh-profile.json" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1]))
document["agents"]["build"]["model"] = {"providerID": "gewiss", "model": "gpt-sol", "variant": "xhigh"}
json.dump(document, open(sys.argv[2], "w"), indent=2)
PY
var_root="$workspace/variant/config"
mkdir -p "$var_root"
cp "$workspace/main-original.jsonc" "$var_root/opencode.jsonc"
var_before=$(sha256sum "$var_root/opencode.jsonc")
rc=0
activate "$var_root" "$workspace/variant/backups" "$workspace/xhigh-profile.json" \
  >/dev/null 2>"$workspace/variant.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/variant.err")" xhigh
assert_contains "$(<"$workspace/variant.err")" gewiss/gpt-sol
assert_eq "$var_before" "$(sha256sum "$var_root/opencode.jsonc")"
assert_eq "opencode.jsonc" "$(ls -A "$var_root")"

# Declared provider, undeclared model: refused too.
python3 - "$workspace/profile.json" "$workspace/undeclared-model-profile.json" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1]))
document["agents"]["scout"]["model"] = {"providerID": "gewiss", "model": "not-declared", "variant": "low"}
json.dump(document, open(sys.argv[2], "w"), indent=2)
PY
rc=0
activate "$var_root" "$workspace/variant/backups" "$workspace/undeclared-model-profile.json" \
  >/dev/null 2>"$workspace/model.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/model.err")" gewiss/not-declared
assert_eq "$var_before" "$(sha256sum "$var_root/opencode.jsonc")"

# The same xhigh assignment on a provider the target does not declare
# (built-in) is not checked statically, and passes.
builtin_root="$workspace/builtin/config"
mkdir -p "$builtin_root"
python3 - "$workspace/before.json" "$builtin_root/opencode.jsonc" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1]))
del document["providers"]
json.dump(document, open(sys.argv[2], "w"), indent=2)
PY
activate "$builtin_root" "$workspace/builtin/backups" "$workspace/xhigh-profile.json" >/dev/null
python3 "$helper" load "$builtin_root/opencode.jsonc" | jq -e '.agents.build.model.variant == "xhigh"' >/dev/null \
  || fail "built-in provider assignment not written"

# --- Review focus 2: strict JSON target stays strict JSON -----------------
json_root="$workspace/json/config"
mkdir -p "$json_root"
# shellcheck disable=SC2016 # literal $schema key
printf '{"$schema": "https://opencode.ai/config.json", "plugins": []}\n' >"$json_root/opencode.json"
activate "$json_root" "$workspace/json/backups" >"$workspace/json.txt"
assert_contains "$(<"$workspace/json.txt")" "target=$json_root/opencode.json"
jq -e '.model and .agents and .permissions and .instructions' "$json_root/opencode.json" >/dev/null \
  || fail "opencode.json is not strict JSON carrying the routing keys"
head -n1 "$json_root/opencode.json" | grep -q '^{' || fail "opencode.json has a header"
assert_eq "opencode.json" "$(ls -A "$json_root")"
json_backup=$(grep '^backup_dir=' "$workspace/json.txt" | cut -d= -f2-)
jq -e --arg id "$profile_id" --arg sha "$profile_sha" \
  '.profile_id == $id and .source_profile_sha256 == $sha and (.activation_stamp | length > 0)' \
  "$json_backup/manifest.json" >/dev/null || fail "manifest lacks header facts"

# --- Review focus 3: minimal V2 target ------------------------------------
min_root="$workspace/min/config"
mkdir -p "$min_root"
# shellcheck disable=SC2016 # literal $schema key
printf '{"$schema":"https://opencode.ai/config.json","update":"disable","plugins":["a@1","b@2"]}' \
  >"$min_root/opencode.jsonc"
activate "$min_root" "$workspace/min/backups" >/dev/null
python3 "$helper" load "$min_root/opencode.jsonc" | jq -e --arg md "$routing_md" '
  .update == "disable" and .plugins == ["a@1","b@2"]
  and .model and .agents and .permissions and .instructions == [$md]
  and ([.permissions[] | select(.action != "subagent")] | length == 0)' >/dev/null \
  || fail "minimal V2 target did not activate as expected"

# --- Missing target is created ---------------------------------------------
new_root="$workspace/new/config"
mkdir -p "$new_root"
activate "$new_root" "$workspace/new/backups" >"$workspace/new.txt"
assert_contains "$(<"$workspace/new.txt")" "target=$new_root/opencode.jsonc"
python3 "$helper" load "$new_root/opencode.jsonc" | jq -e '
  ."$schema" == "https://opencode.ai/config.json" and .model and .agents' >/dev/null \
  || fail "missing target not created"
assert_eq "opencode.jsonc" "$(ls -A "$new_root")"

printf 'PASS: v2 activation\n'
