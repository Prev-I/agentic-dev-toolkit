#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/activate-profile.sh"
source "$root/runtime/opencode-v1-adapter/activate-profile.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
config_root="$workspace/config"
backup_root="$workspace/backups"
mkdir -p "$config_root"

cat >"$config_root/opencode.jsonc" <<'JSONC'
{
  // a user comment that will not survive the rewrite
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".opencode/model-routing.md", "docs/house-style.md"],
  "model": "github-copilot/claude-opus-4.6",
  "permission": { "websearch": "allow" },
  "agent": {
    "plan": { "mode": "primary", "model": "github-copilot/claude-opus-4.6", "variant": "max" },
    "scout": { "model": "github-copilot/gpt-5.3-codex", "variant": "high" },
    "custom-agent": { "model": "some-vendor/some-model", "note": "not one of the eleven declared roles" }
  },
  "plugin": ["superpowers@git+https://github.com/obra/superpowers.git#v6.3.0"],
  "mcp": { "example": { "type": "remote", "url": "https://example.invalid/mcp" } },
  "theme": "opencode"
}
JSONC

activate_profile --repo-profile "$root/../opencode.jsonc" \
                 --targets "$root/manifests/phase-r-routing-targets.json" \
                 --config-root "$config_root" --backup-root "$backup_root" >"$workspace/out.txt"

assert_contains "$(<"$workspace/out.txt")" "$config_root/opencode.jsonc"
backup_dir=$(grep '^backup_dir=' "$workspace/out.txt" | cut -d= -f2-)
assert_file "$backup_dir/opencode.jsonc"
assert_file "$backup_dir/manifest.json"
assert_contains "$(basename "$backup_dir")" 'phase-r-'

python3 - "$config_root/opencode.jsonc" "$root/manifests/phase-r-routing-targets.json" \
         "$backup_dir/opencode.jsonc" "$root/runtime/opencode-v1-adapter/load-routing-profile.sh" <<'PY'
import json
import re
import subprocess
import sys

activated_path, targets_path, backup_path, loader = sys.argv[1:]

def load(path):
    out = subprocess.run(["bash", "-c", f'source "{loader}"; load_routing_profile "{path}"'],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)

activated = load(activated_path)
targets = json.load(open(targets_path, encoding="utf-8"))

# Routing-owned keys are replaced.
assert activated["model"] == targets["default_model"], activated["model"]
for role, target in targets["agents"].items():
    row = activated["agent"][role]
    assert row["model"] == target["model"], (role, row)
    assert row["variant"] == target["variant"], (role, row)
assert activated["permission"]["task"]["breakglass"] == "deny", activated["permission"]

# Everything unrelated is preserved verbatim.
assert activated["plugin"] == ["superpowers@git+https://github.com/obra/superpowers.git#v6.3.0"]
assert activated["mcp"]["example"]["url"] == "https://example.invalid/mcp"
assert activated["theme"] == "opencode"
assert activated["permission"]["websearch"] == "allow"
assert activated["instructions"] == [".opencode/model-routing.md", "docs/house-style.md"]

# An agent row NOT among the eleven declared roles survives byte-for-byte.
assert activated["agent"]["custom-agent"] == {
    "model": "some-vendor/some-model",
    "note": "not one of the eleven declared roles",
}, activated["agent"]["custom-agent"]

# Forbidden references are gone from the activated file.
serialized = json.dumps(activated)
for forbidden in targets["forbidden_model_references"]:
    assert forbidden not in serialized, forbidden

# The backup retains the original text verbatim, comment included.
original = open(backup_path, encoding="utf-8").read()
assert "a user comment that will not survive the rewrite" in original
assert "claude-opus-4.6" in original

# A provenance header is written into the activated file.
activated_text = open(activated_path, encoding="utf-8").read()
assert re.search(r"//\s*profile_id:\s*v1-restored-2026-09", activated_text), activated_text[:400]
PY

# Ambiguous root must block, per the committed activation contract.
touch "$config_root/opencode.json"
if activate_profile --repo-profile "$root/../opencode.jsonc" \
                    --targets "$root/manifests/phase-r-routing-targets.json" \
                    --config-root "$config_root" --backup-root "$backup_root" >/dev/null 2>&1; then
  fail "activated against an ambiguous config root"
fi
rm "$config_root/opencode.json"

# Dry run must not modify anything.
before=$(sha256sum "$config_root/opencode.jsonc" | cut -d' ' -f1)
activate_profile --repo-profile "$root/../opencode.jsonc" \
                 --targets "$root/manifests/phase-r-routing-targets.json" \
                 --config-root "$config_root" --backup-root "$backup_root" --dry-run >/dev/null
assert_eq "$before" "$(sha256sum "$config_root/opencode.jsonc" | cut -d' ' -f1)"

# source_commit resolves relative to the repository owning --repo-profile,
# not the caller's cwd. Prove it by invoking from inside an unrelated git
# repository with absolute paths.
repo_profile_abs=$(cd "$root/.." && pwd)/opencode.jsonc
targets_abs="$root/manifests/phase-r-routing-targets.json"
expected_commit=$(git -C "$(dirname "$repo_profile_abs")" rev-parse HEAD)
[[ -n "$expected_commit" ]] || fail "could not resolve expected repo commit"

unrelated_repo="$workspace/unrelated-repo"
mkdir -p "$unrelated_repo"
(
  cd "$unrelated_repo"
  git init -q
  git config user.email test@example.invalid
  git config user.name test
  printf 'decoy\n' >decoy.txt
  git add decoy.txt
  git commit -q -m decoy
)
unrelated_commit=$(git -C "$unrelated_repo" rev-parse HEAD)

commit_config_root="$workspace/commit-config"
commit_backup_root="$workspace/commit-backups"
mkdir -p "$commit_config_root"
cp "$config_root/opencode.jsonc" "$commit_config_root/opencode.jsonc"

(
  cd "$unrelated_repo"
  activate_profile --repo-profile "$repo_profile_abs" \
                   --targets "$targets_abs" \
                   --config-root "$commit_config_root" --backup-root "$commit_backup_root" >"$workspace/commit-out.txt"
)
commit_backup_dir=$(grep '^backup_dir=' "$workspace/commit-out.txt" | cut -d= -f2-)
recorded_commit=$(python3 -c "import json; print(json.load(open('$commit_backup_dir/manifest.json'))['source_commit'])")
assert_eq "$expected_commit" "$recorded_commit"
[[ "$recorded_commit" != "$unrelated_commit" ]] || fail "source_commit resolved to the caller's unrelated repository"
[[ "$recorded_commit" != "unknown" ]] || fail "source_commit resolved to unknown despite a valid repo-profile repository"

# A merge failure must not corrupt the pre-existing target: seed a malformed
# existing config, call activate_profile via an idiomatic if/then success
# check, and assert both non-zero status and a byte-identical target file.
malformed_config_root="$workspace/malformed-config"
malformed_backup_root="$workspace/malformed-backups"
mkdir -p "$malformed_config_root"
printf '{ this is not valid JSON or JSONC at all' >"$malformed_config_root/opencode.jsonc"
before_malformed=$(sha256sum "$malformed_config_root/opencode.jsonc" | cut -d' ' -f1)

if activate_profile --repo-profile "$root/../opencode.jsonc" \
                    --targets "$root/manifests/phase-r-routing-targets.json" \
                    --config-root "$malformed_config_root" --backup-root "$malformed_backup_root" >/dev/null 2>&1; then
  fail "activate_profile reported success while merging a malformed existing config"
fi
after_malformed=$(sha256sum "$malformed_config_root/opencode.jsonc" | cut -d' ' -f1)
assert_eq "$before_malformed" "$after_malformed"
assert_contains "$(cat "$malformed_config_root/opencode.jsonc")" 'this is not valid JSON'

printf 'PASS: activation routing-owned merge\n'
