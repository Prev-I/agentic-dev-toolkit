#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
activate_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$activate_root/select-activation-target.sh"
source "$activate_root/load-routing-profile.sh"

activate_profile() {
  local repo_profile="" targets="" config_root="" backup_root="" dry_run=0
  while (( $# )); do
    case "$1" in
      --repo-profile) repo_profile=$2; shift 2 ;;
      --targets) targets=$2; shift 2 ;;
      --config-root) config_root=$2; shift 2 ;;
      --backup-root) backup_root=$2; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) printf 'activate_profile: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$repo_profile" && -n "$targets" && -n "$config_root" && -n "$backup_root" ]] || return 2

  local target stamp backup_dir before_hash after_hash commit
  target=$(select_activation_target "$config_root") || {
    printf 'activate_profile: ambiguous activation root — both opencode.json and opencode.jsonc exist\n' >&2
    return 1
  }
  [[ -f "$target" ]] || { printf 'activate_profile: no existing global config at %s\n' "$target" >&2; return 1; }

  stamp=$(date +%Y%m%dT%H%M%S%z)
  backup_dir="$backup_root/phase-r-$stamp"
  before_hash=$(sha256sum "$target" | cut -d' ' -f1)
  commit=$(git -C "$(dirname "$repo_profile")" rev-parse HEAD 2>/dev/null || printf unknown)

  if (( dry_run )); then
    printf 'dry_run=1\ntarget=%s\nbefore_sha256=%s\n' "$target" "$before_hash"
    return 0
  fi

  mkdir -p "$backup_dir"
  cp "$target" "$backup_dir/$(basename "$target")"
  printf '%s  %s\n' "$before_hash" "$(basename "$target")" >"$backup_dir/SHA256SUMS"

  local merged
  merged=$(mktemp "$(dirname "$target")/.activate-profile.XXXXXX")
  if ! REPO_JSON=$(load_routing_profile "$repo_profile") \
  GLOBAL_JSON=$(load_routing_profile "$target") \
  TARGETS="$targets" COMMIT="$commit" STAMP="$stamp" \
    python3 - "$merged" <<'PY'
import datetime
import json
import os
import sys

repo = json.loads(os.environ["REPO_JSON"])
document = json.loads(os.environ["GLOBAL_JSON"])
targets = json.load(open(os.environ["TARGETS"], encoding="utf-8"))
roles = list(targets["agents"])

# Routing-owned keys, and only these.
document["model"] = repo["model"]
document.setdefault("permission", {})
document["permission"]["task"] = repo["permission"]["task"]
document.setdefault("agent", {})
for role in roles:
    document["agent"][role] = repo["agent"][role]

undeclared = sorted(set(document["agent"]) - set(roles))
header = [
    "// OpenCode V1 routing — ACTIVATED BY PHASE R. Generated file.",
    "//",
    f"// profile_id: {targets['profile_id']}",
    f"// source_commit: {os.environ['COMMIT']}",
    f"// activated_at: {datetime.datetime.now().astimezone().isoformat()}",
    f"// activation_stamp: {os.environ['STAMP']}",
    "//",
    "// Routing-owned keys (model, permission.task, and the eleven agent rows)",
    "// come from the repository profile. Every other setting was preserved from",
    "// the previous user-global configuration. The pre-activation file, with its",
    "// original comments, is retained verbatim in the Phase-R backup directory.",
]
if undeclared:
    header += ["//", f"// NOTE: undeclared agent rows preserved unchanged: {', '.join(undeclared)}"]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("\n".join(header) + "\n")
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  then
    rm -f "$merged"
    printf 'activate_profile: merge failed; %s left unchanged\n' "$target" >&2
    return 1
  fi

  mv "$merged" "$target"
  after_hash=$(sha256sum "$target" | cut -d' ' -f1)

  BACKUP_DIR="$backup_dir" TARGET="$target" BEFORE="$before_hash" AFTER="$after_hash" \
    COMMIT="$commit" python3 - "$backup_dir/manifest.json" <<'PY'
import datetime
import json
import os
import sys

document = {
    "created_at": datetime.datetime.now().astimezone().isoformat(),
    "purpose": "Phase R operational safety copy — not a supported rollback strategy",
    "backup_dir": os.environ["BACKUP_DIR"],
    "activation_target": os.environ["TARGET"],
    "pre_activation_sha256": os.environ["BEFORE"],
    "post_activation_sha256": os.environ["AFTER"],
    "source_commit": os.environ["COMMIT"],
    "committed_to_repository": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  printf 'backup_dir=%s\ntarget=%s\nbefore_sha256=%s\nafter_sha256=%s\n' \
    "$backup_dir" "$target" "$before_hash" "$after_hash"
}
