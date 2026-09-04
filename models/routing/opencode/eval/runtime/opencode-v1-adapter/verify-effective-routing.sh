#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

verify_effective_routing() {
  local targets="" outdir="" neutral_cwd="" project_cwd="" bin=${OPENCODE_BIN:-opencode}
  while (( $# )); do
    case "$1" in
      --targets) targets=$2; shift 2 ;;
      --outdir) outdir=$2; shift 2 ;;
      --neutral-cwd) neutral_cwd=$2; shift 2 ;;
      --project-cwd) project_cwd=$2; shift 2 ;;
      *) printf 'verify_effective_routing: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$targets" && -n "$outdir" && -n "$neutral_cwd" ]] || return 2

  mkdir -p "$outdir/neutral" "$outdir/project"
  local version
  version=$("$bin" --version 2>/dev/null </dev/null || printf unknown)

  # Drain the role list into an array before looping so that none of the
  # per-role "$bin debug agent" invocations can ever consume from a shared
  # stdin pipe and truncate the loop early. Each invocation is additionally
  # redirected from /dev/null as a second, independent guard.
  local roles=()
  mapfile -t roles < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["agents"]))' "$targets")

  local role
  for role in "${roles[@]}"; do
    ( cd "$neutral_cwd" && "$bin" debug agent "$role" ) </dev/null >"$outdir/neutral/$role.json" 2>/dev/null || true
    if [[ -n "$project_cwd" ]]; then
      ( cd "$project_cwd" && "$bin" debug agent "$role" ) </dev/null >"$outdir/project/$role.json" 2>/dev/null || true
    fi
  done

  VERSION="$version" NEUTRAL="$outdir/neutral" PROJECT="$outdir/project" \
    python3 - "$targets" "$outdir/effective-routing.json" <<'PY'
import datetime
import json
import os
import sys

targets_path, output = sys.argv[1:]
targets = json.load(open(targets_path, encoding="utf-8"))
declared = targets["agents"]

def resolve(directory, role):
    path = os.path.join(directory, f"{role}.json")
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    model = data.get("model", {})
    task_rules = [rule for rule in data.get("permission", [])
                  if rule.get("permission") == "task"]
    breakglass = [rule.get("action") for rule in task_rules
                  if rule.get("pattern") == "breakglass"]
    return {
        "name": data.get("name"),
        "mode": data.get("mode"),
        "model": f'{model.get("providerID")}/{model.get("modelID")}',
        "variant": data.get("variant"),
        "breakglass_task_action": breakglass[-1] if breakglass else None,
    }

roles = []
mismatches = []
overrides = []
for role, target in declared.items():
    neutral = resolve(os.environ["NEUTRAL"], role)
    project = resolve(os.environ["PROJECT"], role) if os.path.isdir(os.environ["PROJECT"]) else None
    row = {"role": role, "expected": target, "neutral": neutral, "project": project}
    roles.append(row)
    if neutral is None:
        mismatches.append(f"{role}: could not resolve")
        continue
    if neutral["model"] != target["model"]:
        mismatches.append(f"{role}: model {neutral['model']} != {target['model']}")
    if neutral["variant"] != target["variant"]:
        mismatches.append(f"{role}: variant {neutral['variant']} != {target['variant']}")
    if target["mode"] is not None and neutral["mode"] != target["mode"]:
        mismatches.append(f"{role}: mode {neutral['mode']} != {target['mode']}")
    if project is not None and project != neutral:
        overrides.append(f"{role}: project resolution differs from neutral resolution")

lookup = {row["role"]: (row["neutral"] or {}) for row in roles}
forbidden = targets["forbidden_effective_state"]
if (lookup.get("reviewer", {}).get("model") == forbidden["reviewer"]["model"]
        and lookup.get("reviewer", {}).get("variant") == forbidden["reviewer"]["variant"]
        and lookup.get("expert", {}).get("model") == forbidden["expert"]["model"]
        and lookup.get("expert", {}).get("variant") == forbidden["expert"]["variant"]):
    mismatches.append("forbidden effective state: Reviewer Sol high together with Expert Sol high")

breakglass = lookup.get("breakglass", {})
if breakglass.get("mode") != "primary":
    mismatches.append(f"breakglass mode {breakglass.get('mode')} != primary")
for role in ("plan", "build", "general"):
    if lookup.get(role, {}).get("breakglass_task_action") != "deny":
        mismatches.append(f"{role}: effective Task permission does not deny breakglass")

status = "PASS"
if overrides:
    status = "PROJECT_OVERRIDE"
elif mismatches:
    status = "MISMATCH"
document = {
    "captured_at": datetime.datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "evidence_mechanism": "opencode debug agent, neutral and project working directories",
    "prompt_behavior_used_as_oracle": False,
    "status": status,
    "mismatches": mismatches,
    "project_overrides": overrides,
    "roles": roles,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if status == "PASS" else 1)
PY
}
