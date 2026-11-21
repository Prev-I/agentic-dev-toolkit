#!/usr/bin/env bash
# Activate the OpenCode 2 routing profile onto a global config. Source this
# file, or run it directly with the same arguments.
#
#   activate_profile_v2 --profile FILE --targets FILE --config-root DIR \
#     --backup-root DIR --model-routing ABSOLUTE_PATH [--dry-run]
#
# Exit 0 on success, 1 on refusal or conflict, 2 on usage.
#
# Only routing-owned keys change: `model`; `agents.<role>` for every role the
# targets manifest declares (each row replaced whole); the top-level
# `permissions` entries whose action is `subagent` (removed, then the profile's
# appended last, because the list is ordered and the last match wins); and the
# single `instructions` entry naming model-routing.md. Everything else is
# preserved. A V1-shaped target is refused untouched.
set -Eeuo pipefail
IFS=$'\n\t'
v2_activate_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

activate_profile_v2() {
  local profile="" targets="" config_root="" backup_root="" model_routing="" dry_run=0
  while (( $# )); do
    case "$1" in
      --profile|--targets|--config-root|--backup-root|--model-routing)
        (( $# >= 2 )) || { printf 'activate_profile_v2: %s needs a value\n' "$1" >&2; return 2; }
        case "$1" in
          --profile) profile=$2 ;;
          --targets) targets=$2 ;;
          --config-root) config_root=$2 ;;
          --backup-root) backup_root=$2 ;;
          --model-routing) model_routing=$2 ;;
        esac
        shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) printf 'activate_profile_v2: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  if [[ -z "$profile" || -z "$targets" || -z "$config_root" || -z "$backup_root" || -z "$model_routing" ]]; then
    printf 'usage: activate_profile_v2 --profile FILE --targets FILE --config-root DIR --backup-root DIR --model-routing ABSOLUTE_PATH [--dry-run]\n' >&2
    return 2
  fi
  [[ "$model_routing" == /* ]] || {
    printf 'activate_profile_v2: --model-routing must be an absolute path: %s\n' "$model_routing" >&2
    return 2
  }
  [[ -f "$profile" ]] || { printf 'activate_profile_v2: no such profile: %s\n' "$profile" >&2; return 2; }
  [[ -f "$targets" ]] || { printf 'activate_profile_v2: no such targets manifest: %s\n' "$targets" >&2; return 2; }

  local helper="$v2_activate_root/v2config.py"
  local target shape profile_shape
  if [[ -e "$config_root/opencode.json" && -e "$config_root/opencode.jsonc" ]]; then
    printf 'activate_profile_v2: ambiguous activation root — both opencode.json and opencode.jsonc exist in %s\n' \
      "$config_root" >&2
    return 1
  elif [[ -e "$config_root/opencode.json" ]]; then
    target="$config_root/opencode.json"
  else
    target="$config_root/opencode.jsonc"
  fi
  if [[ -e "$target" && ! -f "$target" ]]; then
    printf 'activate_profile_v2: target is not a regular file: %s\n' "$target" >&2
    return 1
  fi

  profile_shape=$(python3 "$helper" shape "$profile") || profile_shape=invalid
  [[ "$profile_shape" == v2 ]] || {
    printf 'activate_profile_v2: profile is not a V2 config (%s): %s\n' "$profile_shape" "$profile" >&2
    return 1
  }
  shape=$(python3 "$helper" shape "$target") || shape=invalid
  case "$shape" in
    v2|empty) ;;
    v1)
      printf 'activate_profile_v2: %s is a V1-shaped config; convert it first with convert-v1-config, then re-run. Nothing was changed.\n' \
        "$target" >&2
      return 1 ;;
    *)
      printf 'activate_profile_v2: %s is not parseable JSON/JSONC; nothing was changed.\n' "$target" >&2
      return 1 ;;
  esac

  local stamp before_hash source_hash commit format
  stamp=$(date +%Y%m%dT%H%M%S%z)
  if [[ -e "$target" ]]; then before_hash=$(sha256sum "$target" | cut -d' ' -f1); else before_hash=none; fi
  source_hash=$(sha256sum "$profile" | cut -d' ' -f1)
  commit=$(git -C "$(dirname "$profile")" rev-parse HEAD 2>/dev/null || printf unknown)
  if [[ "$target" == *.jsonc ]]; then format=jsonc; else format=json; fi

  # The merge runs in every mode, so a dry run also reports refusals. A dry run
  # writes its result nowhere.
  #
  # Every mutating step below checks its own status: a caller that runs this
  # function under `||` or `if` suspends errexit, and a failed backup must
  # never be followed by the replace.
  local merged=/dev/null
  if (( ! dry_run )); then
    if ! mkdir -p "$config_root" || ! merged=$(mktemp "$config_root/.activate-profile-v2.XXXXXX"); then
      printf 'activate_profile_v2: cannot create a temp file in %s\n' "$config_root" >&2
      return 1
    fi
  fi
  if ! PROFILE="$profile" TARGETS="$targets" TARGET="$target" MODEL_ROUTING="$model_routing" \
       FORMAT="$format" STAMP="$stamp" SOURCE_HASH="$source_hash" COMMIT="$commit" \
       HELPER_DIR="$v2_activate_root" \
       python3 -B - "$merged" <<'PY'
import datetime
import json
import os
import sys

sys.path.insert(0, os.environ["HELPER_DIR"])
import v2config  # noqa: E402  (run with -B: no __pycache__ in the bundle)


def refuse(message):
    sys.stderr.write("activate_profile_v2: %s\n" % message)
    sys.exit(1)


profile = v2config.load(os.environ["PROFILE"])
with open(os.environ["TARGETS"], encoding="utf-8") as handle:
    targets = json.load(handle)
if targets.get("format") != "opencode-v2-routing-targets/1":
    refuse("unsupported targets format: %r" % targets.get("format"))
roles = list(targets["agents"])

target_path = os.environ["TARGET"]
if os.path.exists(target_path) and os.path.getsize(target_path) > 0:
    document = v2config.load(target_path)
else:
    document = {"$schema": "https://opencode.ai/config.json"}

# Fail closed on any structure this tool would otherwise have to guess about.
if not isinstance(profile.get("model"), dict):
    refuse("profile has no model object")
if not isinstance(profile.get("agents"), dict):
    refuse("profile has no agents object")
missing = [role for role in roles if not isinstance(profile["agents"].get(role), dict)]
if missing:
    refuse("profile lacks declared roles: %s" % ", ".join(missing))
profile_permissions = profile.get("permissions", [])
if not isinstance(profile_permissions, list) or not all(isinstance(e, dict) for e in profile_permissions):
    refuse("profile permissions is not a list of objects")
for key, kind in (("agents", dict), ("permissions", list), ("instructions", list), ("providers", dict)):
    if key in document and not isinstance(document[key], kind):
        refuse("target %s is not a JSON %s" % (key, kind.__name__))
if not all(isinstance(e, dict) for e in document.get("permissions", [])):
    refuse("target permissions holds a non-object entry")

# Variants: 2.x silently ignores an undeclared variant on a declared provider,
# so it is an error here. Built-in providers need no declaration and are not
# checked statically.
providers = document.get("providers", {})
assignments = [("model", profile["model"])] + [
    ("agents.%s" % role, profile["agents"][role].get("model")) for role in roles]
for where, model in assignments:
    if not isinstance(model, dict):
        continue
    provider_id, model_id, variant = model.get("providerID"), model.get("model"), model.get("variant")
    if provider_id not in providers:
        continue
    declared_models = providers[provider_id].get("models") if isinstance(providers[provider_id], dict) else None
    entry = declared_models.get(model_id) if isinstance(declared_models, dict) else None
    if not isinstance(entry, dict):
        refuse("%s assigns %s/%s, but provider %s declares no model %s"
               % (where, provider_id, model_id, provider_id, model_id))
    if variant is None:
        continue
    declared = [v.get("id") for v in entry.get("variants", []) if isinstance(v, dict)]
    if variant not in declared:
        refuse("%s assigns %s/%s#%s, but variant %s is not declared for %s/%s (declared: %s)"
               % (where, provider_id, model_id, variant, variant, provider_id, model_id,
                  ", ".join(str(v) for v in declared) or "none"))

# Routing-owned keys, and only these.
document["model"] = profile["model"]
agents = document.setdefault("agents", {})
for role in roles:
    agents[role] = profile["agents"][role]

document["permissions"] = (
    [e for e in document.get("permissions", []) if e.get("action") != "subagent"]
    + [e for e in profile_permissions if e.get("action") == "subagent"])

routing_md = os.environ["MODEL_ROUTING"]
instructions = document.get("instructions", [])
kept, slot = [], None
for item in instructions:
    if isinstance(item, str) and os.path.basename(item) == "model-routing.md":
        if slot is None:
            slot = len(kept)
        continue
    kept.append(item)
kept.insert(len(kept) if slot is None else slot, routing_md)
document["instructions"] = kept

for key in v2config.V1_KEYS:
    if key in document:
        refuse("refusing to write a mixed-shape config (V1 key %s)" % key)

undeclared = sorted(set(agents) - set(roles))
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    if os.environ["FORMAT"] == "jsonc":
        header = [
            "// OpenCode 2 routing - activated profile. Generated file.",
            "//",
            "// profile_id: %s" % targets["profile_id"],
            "// source_profile_sha256: %s" % os.environ["SOURCE_HASH"],
            "// source_commit: %s" % os.environ["COMMIT"],
            "// source_commit is context only; the digest identifies possibly uncommitted source.",
            "// activated_at: %s" % datetime.datetime.now().astimezone().isoformat(),
            "// activation_stamp: %s" % os.environ["STAMP"],
            "//",
            "// Routing-owned keys (model, the declared agents rows, the subagent",
            "// permissions entries and the model-routing.md instructions entry)",
            "// come from the repository profile. Every other setting was preserved.",
            "// The pre-activation file, with its original comments, is retained verbatim",
            "// in the routing backup directory.",
        ]
        if undeclared:
            header += ["//", "// NOTE: undeclared agent rows preserved unchanged: %s" % ", ".join(undeclared)]
        handle.write("\n".join(header) + "\n")
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  then
    [[ "$merged" == /dev/null ]] || rm -f "$merged"
    printf 'activate_profile_v2: activation refused; %s left unchanged\n' "$target" >&2
    return 1
  fi

  if (( dry_run )); then
    printf 'dry_run=1\ntarget=%s\nbefore_sha256=%s\n' "$target" "$before_hash"
    return 0
  fi

  local after_hash backup_dir suffix=0
  # Preserve the target's mode; a new target gets the umask default for a file.
  if [[ -e "$target" ]]; then
    chmod --reference="$target" "$merged" || { rm -f "$merged"; return 1; }
  else
    chmod "$(printf '%o' $(( 0666 & ~$(umask) )))" "$merged" || { rm -f "$merged"; return 1; }
  fi
  after_hash=$(sha256sum "$merged" | cut -d' ' -f1) && [[ -n "$after_hash" ]] || { rm -f "$merged"; return 1; }

  # The backup is complete, and verified against the digest the merge read,
  # before the target changes.
  if ! mkdir -p "$backup_root"; then
    rm -f "$merged"
    printf 'activate_profile_v2: cannot create %s; %s left unchanged\n' "$backup_root" "$target" >&2
    return 1
  fi
  backup_dir="$backup_root/routing-$stamp"
  while ! mkdir "$backup_dir" 2>/dev/null; do
    suffix=$((suffix + 1))
    (( suffix < 100 )) || { rm -f "$merged"; printf 'activate_profile_v2: cannot create a backup directory under %s\n' "$backup_root" >&2; return 1; }
    backup_dir="$backup_root/routing-$stamp-$suffix"
  done
  if [[ -e "$target" ]]; then
    if ! cp -p "$target" "$backup_dir/$(basename "$target")" \
       || [[ "$(sha256sum "$backup_dir/$(basename "$target")" | cut -d' ' -f1)" != "$before_hash" ]] \
       || ! printf '%s  %s\n' "$before_hash" "$(basename "$target")" >"$backup_dir/SHA256SUMS"; then
      rm -f "$merged"
      printf 'activate_profile_v2: backup failed or the target changed during activation; %s left unchanged\n' "$target" >&2
      return 1
    fi
  elif ! : >"$backup_dir/SHA256SUMS"; then
    rm -f "$merged"
    return 1
  fi
  if ! BACKUP_DIR="$backup_dir" TARGET="$target" BEFORE="$before_hash" AFTER="$after_hash" \
       COMMIT="$commit" SOURCE_HASH="$source_hash" STAMP="$stamp" TARGETS="$targets" \
       PROFILE="$profile" FORMAT="$format" python3 - "$backup_dir/manifest.json" <<'PY'
import datetime
import json
import os
import sys

with open(os.environ["TARGETS"], encoding="utf-8") as handle:
    profile_id = json.load(handle)["profile_id"]
document = {
    "created_at": datetime.datetime.now().astimezone().isoformat(),
    "purpose": "Routing activation safety copy - not a supported rollback strategy",
    "backup_dir": os.environ["BACKUP_DIR"],
    "activation_target": os.environ["TARGET"],
    "activation_target_format": os.environ["FORMAT"],
    "header_written": os.environ["FORMAT"] == "jsonc",
    "target_existed": os.environ["BEFORE"] != "none",
    "pre_activation_sha256": os.environ["BEFORE"],
    "post_activation_sha256": os.environ["AFTER"],
    "profile_id": profile_id,
    "source_profile": os.path.abspath(os.environ["PROFILE"]),
    "source_profile_sha256": os.environ["SOURCE_HASH"],
    "source_commit": os.environ["COMMIT"],
    "source_commit_is_complete_provenance": False,
    "activation_stamp": os.environ["STAMP"],
    "routing_owned_keys": "model, the declared agents rows, the subagent permissions entries "
                          "and the model-routing.md instructions entry come from the repository profile",
    "committed_to_repository": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  then
    rm -f "$merged"
    printf 'activate_profile_v2: could not write the backup manifest; %s left unchanged\n' "$target" >&2
    return 1
  fi

  if ! mv "$merged" "$target"; then
    rm -f "$merged"
    printf 'activate_profile_v2: replace failed; %s left unchanged\n' "$target" >&2
    return 1
  fi
  printf 'backup_dir=%s\ntarget=%s\nbefore_sha256=%s\nafter_sha256=%s\n' \
    "$backup_dir" "$target" "$before_hash" "$after_hash"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  activate_profile_v2 "$@"
fi
