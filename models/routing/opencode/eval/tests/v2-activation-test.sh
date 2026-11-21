#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
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
    "custom-agent": {"model": {"providerID": "some-vendor", "model": "some-model"}, "note": "user-owned",
                     "system": "Rispondi in italiano — perché sì ✓"}
  }
}
JSONC
chmod 640 "$main_root/opencode.jsonc"   # not mktemp's 600
cp "$main_root/opencode.jsonc" "$workspace/main-original.jsonc"
inode_before=$(stat -c %i "$main_root/opencode.jsonc")

rm -f "$workspace/mv.log"
activate "$main_root" "$workspace/main/backups" >"$workspace/out.txt" 2>"$workspace/main.err"
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

# Non-ASCII user text survives byte-equal, not as \u escapes.
grep -qF '"system": "Rispondi in italiano — perché sì ✓"' "$main_root/opencode.jsonc" \
  || fail "non-ASCII user text not preserved byte-equal"

# The dropped user comment is reported once, naming the backup.
assert_contains "$(<"$workspace/main.err")" "user comments in $main_root/opencode.jsonc were dropped"
assert_contains "$(<"$workspace/main.err")" "$backup_dir"

# Re-activation is idempotent on content (header aside), and a file whose only
# comments are the generated header reports no dropped comments.
activate "$main_root" "$workspace/main/backups" >/dev/null 2>"$workspace/main2.err"
[[ "$(<"$workspace/main2.err")" != *"comments"* ]] || fail "generated header reported as user comments: $(<"$workspace/main2.err")"

# The same with CRLF line endings (an editor on Windows): still no note.
crlf_root="$workspace/crlf/config"
mkdir -p "$crlf_root"
sed 's/$/\r/' "$main_root/opencode.jsonc" >"$crlf_root/opencode.jsonc"
grep -q $'^// profile_id: .*\r$' "$crlf_root/opencode.jsonc" || fail "CRLF fixture not CRLF"
activate "$crlf_root" "$workspace/crlf/backups" >/dev/null 2>"$workspace/crlf.err"
[[ "$(<"$workspace/crlf.err")" != *"comments"* ]] || fail "CRLF generated header reported as user comments: $(<"$workspace/crlf.err")"

python3 "$helper" load "$main_root/opencode.jsonc" >"$workspace/after2.json"
cmp -s "$workspace/after.json" "$workspace/after2.json" || fail "second activation changed content"

# The header convert-v1-config.sh writes for .jsonc output is not a user comment.
# The prefix is pinned against the converter so the two cannot drift.
for emitted in "printf '// Converted from the OpenCode 1.x config %s" "printf '// source sha256: %s" \
  "printf '// converted at: %s" "printf '// OpenCode version: %s" \
  "printf \"// converted with OpenCode 2's own translation (GET /api/config, document layer info)"; do
  grep -qF -- "$emitted" "$adapter/convert-v1-config.sh" \
    || fail "convert-v1-config.sh no longer emits a header line activation recognises: $emitted"
done
conv_body="{\"\$schema\":\"https://opencode.ai/config.json\"}"
conv_root="$workspace/conv/config"
mkdir -p "$conv_root"
conv_header() {
  printf '%s\n' '// Converted from the OpenCode 1.x config /tmp/old/opencode.jsonc' \
    '// source sha256: abc123' '// converted at: 2026-11-21T00:00:00Z' '// OpenCode version: 2.0.0' \
    "// converted with OpenCode 2's own translation (GET /api/config, document layer info)"
}
{ conv_header; printf '%s\n' "$conv_body"; } >"$conv_root/opencode.jsonc"
activate "$conv_root" "$workspace/conv/backups" >/dev/null 2>"$workspace/conv.err"
[[ "$(<"$workspace/conv.err")" != *"comments"* ]] || fail "converter header reported as user comments: $(<"$workspace/conv.err")"
conv2_root="$workspace/conv2/config"
mkdir -p "$conv2_root"
{ conv_header; printf '// my own note\n%s\n' "$conv_body"; } >"$conv2_root/opencode.jsonc"
activate "$conv2_root" "$workspace/conv2/backups" >/dev/null 2>"$workspace/conv2.err"
assert_contains "$(<"$workspace/conv2.err")" "user comments in $conv2_root/opencode.jsonc were dropped"
conv3_root="$workspace/conv3/config"
mkdir -p "$conv3_root"
{ conv_header; printf '// OpenCode version: pinned because of a regression\n%s\n' "$conv_body"; } >"$conv3_root/opencode.jsonc"
activate "$conv3_root" "$workspace/conv3/backups" >/dev/null 2>"$workspace/conv3.err"
assert_contains "$(<"$workspace/conv3.err")" "user comments in $conv3_root/opencode.jsonc were dropped"

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

# --- Symlinked targets are refused, dangling ones included ----------------
link_root="$workspace/link/config"
mkdir -p "$link_root" "$workspace/link/dotfiles"
cp "$workspace/main-original.jsonc" "$workspace/link/dotfiles/opencode.jsonc"
ln -s "$workspace/link/dotfiles/opencode.jsonc" "$link_root/opencode.jsonc"
link_before=$(sha256sum "$workspace/link/dotfiles/opencode.jsonc")
rc=0
activate "$link_root" "$workspace/link/backups" >/dev/null 2>"$workspace/link.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/link.err")" "$link_root/opencode.jsonc is a symlink"
[[ -L "$link_root/opencode.jsonc" ]] || fail "symlink replaced"
assert_eq "$link_before" "$(sha256sum "$workspace/link/dotfiles/opencode.jsonc")"
[[ ! -e "$workspace/link/backups" ]] || fail "refused activation left a backup"

dangle_root="$workspace/dangle/config"
mkdir -p "$dangle_root"
cp "$workspace/main-original.jsonc" "$dangle_root/opencode.jsonc"
ln -s "$workspace/nowhere/opencode.json" "$dangle_root/opencode.json"
dangle_before=$(sha256sum "$dangle_root/opencode.jsonc")
rc=0
activate "$dangle_root" "$workspace/dangle/backups" >/dev/null 2>"$workspace/dangle.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/dangle.err")" "$dangle_root/opencode.json is a symlink"
[[ -L "$dangle_root/opencode.json" ]] || fail "dangling symlink removed"
assert_eq "$dangle_before" "$(sha256sum "$dangle_root/opencode.jsonc")"

# --- Backup-integrity refusals ----------------------------------------------
# A backup root that cannot be created: refused, nothing left behind.
broot="$workspace/broot/config"
mkdir -p "$broot"
cp "$workspace/main-original.jsonc" "$broot/opencode.jsonc"
: >"$workspace/broot/not-a-dir"
broot_before=$(sha256sum "$broot/opencode.jsonc")
rc=0
activate "$broot" "$workspace/broot/not-a-dir" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"
assert_eq "$broot_before" "$(sha256sum "$broot/opencode.jsonc")"
assert_eq "opencode.jsonc" "$(ls -A "$broot")"

# The target changes between the merge's read and the backup copy: a cp shim
# edits the target first. The copy no longer matches the digest, so the
# activation is refused, the edited target is left as it is, and the fresh
# backup directory is removed.
race_shim="$workspace/race-shim"
mkdir -p "$race_shim"
real_cp=$(command -v cp)
cat >"$race_shim/cp" <<SH
#!/usr/bin/env bash
for arg in "\$@"; do
  [[ "\$arg" != */race/config/opencode.jsonc ]] || printf '// concurrent edit\n' >>"\$arg"
done
exec "$real_cp" "\$@"
SH
chmod +x "$race_shim/cp"
race_root="$workspace/race/config"
mkdir -p "$race_root"
"$real_cp" "$workspace/main-original.jsonc" "$race_root/opencode.jsonc"
rc=0
PATH="$race_shim:$PATH" activate "$race_root" "$workspace/race/backups" >/dev/null 2>"$workspace/race.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/race.err")" "the backup copy does not match the target the merge read"
assert_eq "$(sha256sum <"$workspace/main-original.jsonc")" "$(head -c -19 "$race_root/opencode.jsonc" | sha256sum)"
assert_eq '// concurrent edit' "$(tail -n1 "$race_root/opencode.jsonc")"
assert_eq "opencode.jsonc" "$(ls -A "$race_root")"
assert_eq "" "$(ls -A "$workspace/race/backups")"

# The target changes after the backup is complete (a python3 shim edits it
# when the manifest is written): the last check before the replace refuses.
real_python=$(command -v python3)
late_shim="$workspace/late-shim"
mkdir -p "$late_shim"
cat >"$late_shim/python3" <<SH
#!/usr/bin/env bash
if [[ "\${!#}" == */late/backups/*/manifest.json ]]; then
  printf '// late edit\n' >>"$workspace/late/config/opencode.jsonc"
fi
exec "$real_python" "\$@"
SH
chmod +x "$late_shim/python3"
late_root="$workspace/late/config"
mkdir -p "$late_root"
cp "$workspace/main-original.jsonc" "$late_root/opencode.jsonc"
rc=0
PATH="$late_shim:$PATH" activate "$late_root" "$workspace/late/backups" >/dev/null 2>"$workspace/late.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/late.err")" "the target changed after it was backed up"
assert_eq '// late edit' "$(tail -n1 "$late_root/opencode.jsonc")"
assert_eq "opencode.jsonc" "$(ls -A "$late_root")"
assert_eq "" "$(ls -A "$workspace/late/backups")"

# An interrupt mid-activation removes the temp file, leaves the target alone
# and re-raises the signal: a python3 shim sends TERM to the activating shell
# while the manifest is written.
term_shim="$workspace/term-shim"
mkdir -p "$term_shim"
cat >"$term_shim/python3" <<SH
#!/usr/bin/env bash
if [[ "\${!#}" == */term*/backups/*/manifest.json ]]; then
  kill -TERM "\$PPID"
fi
exec "$real_python" "\$@"
SH
chmod +x "$term_shim/python3"
term_root="$workspace/term/config"
mkdir -p "$term_root"
cp "$workspace/main-original.jsonc" "$term_root/opencode.jsonc"
# The outer subshell absorbs bash's "Terminated" job report.
rc=$( (PATH="$term_shim:$PATH" bash -c 'source "$1"; shift; activate_profile_v2 "$@"' _ \
  "$adapter/activate-profile.sh" --profile "$profile" --targets "$targets" \
  --config-root "$term_root" --backup-root "$workspace/term/backups" \
  --model-routing "$routing_md" >/dev/null 2>&1; printf '%s' "$?") 2>/dev/null )
assert_eq 143 "$rc"
cmp -s "$term_root/opencode.jsonc" "$workspace/main-original.jsonc" || fail "interrupted activation changed the target"
assert_eq "opencode.jsonc" "$(ls -A "$term_root")"

# The same interrupt when the activation runs sourced in a subshell of this
# shell: the signal must be re-raised on the subshell, not on this shell
# ($$ would name this shell; $BASHPID names the subshell). The shim's parent
# is the subshell, so TERM goes to the subshell only.
sub_root="$workspace/term-sub/config"
mkdir -p "$sub_root"
cp "$workspace/main-original.jsonc" "$sub_root/opencode.jsonc"
(
  PATH="$term_shim:$PATH" activate_profile_v2 --profile "$profile" --targets "$targets" \
    --config-root "$sub_root" --backup-root "$workspace/term-sub/backups" \
    --model-routing "$routing_md" >/dev/null 2>&1
  printf 'survived\n' >"$workspace/term-sub/after-call"
) &
sub_pid=$!
rc=0
wait "$sub_pid" 2>/dev/null || rc=$?
# Reaching this line at all means this shell was not signalled.
assert_eq 143 "$rc"
[[ ! -e "$workspace/term-sub/after-call" ]] || fail "subshell kept running after TERM"
cmp -s "$sub_root/opencode.jsonc" "$workspace/main-original.jsonc" || fail "interrupted subshell activation changed the target"
assert_eq "opencode.jsonc" "$(ls -A "$sub_root")"

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

# Declared provider, no entry for the model: not checked statically (the
# verifier checks it against /api/model); activation proceeds with a note.
python3 - "$workspace/profile.json" "$workspace/undeclared-model-profile.json" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1]))
document["agents"]["scout"]["model"] = {"providerID": "gewiss", "model": "not-declared", "variant": "low"}
json.dump(document, open(sys.argv[2], "w"), indent=2)
PY
undeclared_root="$workspace/undeclared/config"
mkdir -p "$undeclared_root"
cp "$workspace/main-original.jsonc" "$undeclared_root/opencode.jsonc"
activate "$undeclared_root" "$workspace/undeclared/backups" "$workspace/undeclared-model-profile.json" \
  >/dev/null 2>"$workspace/model.err" || fail "undeclared model refused: $(<"$workspace/model.err")"
assert_contains "$(<"$workspace/model.err")" "agents.scout assigns gewiss/not-declared; provider gewiss declares no entry"

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

# A declared provider with no entry for the model (the converter's filter-only
# block for a built-in provider, e.g. `"openai": {}`) is not checked
# statically: the bundle profile activates, with one note per such assignment.
filter_root="$workspace/filter/config"
mkdir -p "$filter_root"
printf '{"providers": {"openai": {}, "github-copilot": {"models": {}}}}\n' >"$filter_root/opencode.jsonc"
activate "$filter_root" "$workspace/filter/backups" >/dev/null 2>"$workspace/filter.err" \
  || fail "filter-only provider refused: $(<"$workspace/filter.err")"
assert_contains "$(<"$workspace/filter.err")" "agents.expert assigns openai/gpt-6-astra; provider openai declares no entry"
assert_contains "$(<"$workspace/filter.err")" "checks it against /api/model"
python3 "$helper" load "$filter_root/opencode.jsonc" | jq -e '.providers.openai == {} and .agents.expert.model.variant == "xhigh"' >/dev/null \
  || fail "filter-only provider activation did not write the routing rows"
# ...but a model entry that exists and lacks the variant is still refused.
python3 - "$workspace/profile.json" "$workspace/max-profile.json" <<'PY2'
import json
import sys
document = json.load(open(sys.argv[1]))
document["agents"]["build"]["model"] = {"providerID": "openai", "model": "gpt-6.1-sol", "variant": "max"}
json.dump(document, open(sys.argv[2], "w"), indent=2)
PY2
printf '{"providers": {"openai": {"models": {"gpt-6.1-sol": {"variants": [{"id": "high"}]}}}}}\n' \
  >"$filter_root/opencode.jsonc"
filter_before=$(sha256sum "$filter_root/opencode.jsonc")
rc=0
activate "$filter_root" "$workspace/filter/backups" "$workspace/max-profile.json" \
  >/dev/null 2>"$workspace/filter2.err" || rc=$?
assert_eq 1 "$rc"
assert_contains "$(<"$workspace/filter2.err")" "variant max is not declared for openai/gpt-6.1-sol"
assert_eq "$filter_before" "$(sha256sum "$filter_root/opencode.jsonc")"

# --- --model-routing is normalised; a non-canonical location warns ---------
mr_root="$workspace/mr/config"
mkdir -p "$mr_root"
: >"$mr_root/model-routing.md"
PATH="$shim:$PATH" activate_profile_v2 --profile "$profile" --targets "$targets" \
  --config-root "$mr_root" --backup-root "$workspace/mr/backups" \
  --model-routing "$mr_root//./model-routing.md" >/dev/null 2>"$workspace/mr.err"
[[ "$(<"$workspace/mr.err")" != *warning* ]] || fail "canonical model-routing path warned: $(<"$workspace/mr.err")"
python3 "$helper" load "$mr_root/opencode.jsonc" | jq -e --arg md "$mr_root/model-routing.md" \
  '.instructions == [$md]' >/dev/null || fail "--model-routing not normalised"
# elsewhere (the test default): written, with a warning naming the expected path.
activate "$mr_root" "$workspace/mr/backups" >/dev/null 2>"$workspace/mr2.err"
assert_contains "$(<"$workspace/mr2.err")" "warning: --model-routing $routing_md is not that path"
assert_contains "$(<"$workspace/mr2.err")" "$mr_root/model-routing.md"
# the expected path, but the file is absent: warns that it does not exist.
rm "$mr_root/model-routing.md"
PATH="$shim:$PATH" activate_profile_v2 --profile "$profile" --targets "$targets" \
  --config-root "$mr_root" --backup-root "$workspace/mr/backups" \
  --model-routing "$mr_root/model-routing.md" >/dev/null 2>"$workspace/mr3.err"
assert_contains "$(<"$workspace/mr3.err")" "does not exist"

# --- the final mixed-shape guard covers `mcp` without `servers` -----------
# An `mcp` object without `servers` is V1 per v2config.shape, so it is refused
# before the merge; the shared helper also rejects it on the merged document.
python3 -I -B - "$adapter" <<'PY2'
import sys
sys.path.insert(0, sys.argv[1])
import v2config
assert v2config.mixed_shape_keys({"mcp": {"x": {}}}) == ["mcp without servers"]
assert v2config.mixed_shape_keys({"mcp": {"servers": {}}, "plugins": []}) == []
assert v2config.mixed_shape_keys({"agent": {}, "mcp": {}}) == ["agent", "mcp without servers"]
PY2
grep -q 'v2config.mixed_shape_keys(document)' "$adapter/activate-profile.sh" \
  || fail "activation's final guard does not use the shared shape logic"
mcp_root="$workspace/mcp/config"
mkdir -p "$mcp_root"
printf '{"mcp": {"example": {"type": "remote"}}}\n' >"$mcp_root/opencode.jsonc"
rc=0
activate "$mcp_root" "$workspace/mcp/backups" >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc"

# --- no import from the current directory (python3 -I) --------------------
plant="$workspace/plant"
mkdir -p "$plant"
printf 'open(%s, "w").write("imported")\n' "'$plant/MARKER'" >"$plant/json.py"
new_root_plant="$workspace/plant-config"
mkdir -p "$new_root_plant"
(cd "$plant" && activate "$main_root" "$workspace/plant-backups" "$profile" --dry-run >/dev/null 2>&1) \
  || fail "dry run from a planted directory failed"
(cd "$plant" && activate "$new_root_plant" "$workspace/plant-backups" >/dev/null 2>&1) \
  || fail "activation from a planted directory failed"
[[ ! -e "$plant/MARKER" ]] || fail "activation imported json.py from the current directory"

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
