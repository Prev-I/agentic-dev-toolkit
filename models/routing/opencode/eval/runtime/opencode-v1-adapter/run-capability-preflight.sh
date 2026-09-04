#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
preflight_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$preflight_root/probe.sh"
source "$preflight_root/classify-capability-failure.sh"
source "$preflight_root/budget-ledger.sh"

preflight_targets() {
  python3 - "$1" <<'PY'
import json
import sys

ORDER = ["plan", "build", "general", "explore", "scout", "reviewer",
         "compaction", "title", "summary", "expert", "breakglass"]
agents = json.load(open(sys.argv[1], encoding="utf-8"))["agents"]
for role in ORDER:
    row = agents[role]
    print(role, row["model"], row["variant"])
PY
}

run_capability_preflight() {
  local output_dir=$1 manifest=$2 ledger=$3 targets=$4
  mkdir -p "$output_dir"
  local role model variant record status classification stop_class credits cost line
  # Read every target line into an array up front, fully draining and closing
  # the process-substitution pipe before the loop body runs anything. Feeding
  # a `while read` loop directly from `< <(process substitution)` shares fd 0
  # with every command the loop body invokes; probe_model_variant ultimately
  # execs the opencode CLI without redirecting its stdin, and if that CLI
  # reads/peeks at stdin at all, it silently steals bytes from this same pipe,
  # causing the loop to see EOF early and stop with no error. Draining to an
  # array up front removes the shared-fd hazard entirely.
  local lines=()
  mapfile -t lines < <(preflight_targets "$targets")
  for line in "${lines[@]}"; do
    IFS=' ' read -r role model variant <<<"$line"
    [[ -n "${role:-}" ]] || continue
    record="$output_dir/${role}.json"
    # Skip re-probing roles that already have USABLE records to avoid double-charging.
    if [[ -f "$record" ]] && python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if data.get("phase_r_classification") == "USABLE" else 1)
' "$record"; then
      continue
    fi
    # Run probe in a subshell to isolate the probe.sh RETURN trap, preventing it from
    # leaking into subsequent command substitutions in this loop (e.g., ledger_credits_from_cost).
    set +e
    ( probe_model_variant "$model" "$variant" "$record" )
    status=$?
    set -e
    if (( status == 0 )); then
      classification=USABLE
      stop_class=NONE
    else
      classification=$(classify_capability_failure "$record")
      stop_class=$(capability_stop_class "$classification")
    fi
    cost=$(python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))["observed_cost"]
print("null" if value is None else value)
' "$record")
    credits=$(ledger_credits_from_cost "${model%%/*}" "$cost")
    [[ "$credits" == null ]] || ledger_append "$ledger" evaluation "preflight-$role" "${model%%/*}" "$credits"
    ROLE="$role" CLASSIFICATION="$classification" STOP_CLASS="$stop_class" CREDITS="$credits" \
      python3 - "$record" <<'PY'
import json
import os
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
record["role"] = os.environ["ROLE"]
record["phase_r_classification"] = os.environ["CLASSIFICATION"]
record["phase_r_stop_class"] = os.environ["STOP_CLASS"]
record["derived_credits"] = None if os.environ["CREDITS"] == "null" else float(os.environ["CREDITS"])
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
  done

  python3 - "$manifest" "$output_dir" "$targets" <<'PY'
import datetime
import glob
import json
import os
import sys

manifest_path, output_dir, targets_path = sys.argv[1:]
declared = json.load(open(targets_path, encoding="utf-8"))["agents"]
rows = []
for path in sorted(glob.glob(os.path.join(output_dir, "*.json"))):
    record = json.load(open(path, encoding="utf-8"))
    rows.append({
        "role": record["role"],
        "provider": record["provider"],
        "model": record["model"],
        "variant": record["variant"],
        "classification": record["phase_r_classification"],
        "stop_class": record["phase_r_stop_class"],
        "pricing_regime": record["pricing_regime"],
        "observed_cost": record["observed_cost"],
        "derived_credits": record["derived_credits"],
        "wall_clock_ms": record["wall_clock_ms"],
        "runtime_version": record["runtime_version"],
        "exact_invocation": record["exact_invocation"],
    })
covered = {row["role"] for row in rows}
missing = sorted(set(declared) - covered)
regressions = [row for row in rows if row["stop_class"] == "CAPABILITY_REGRESSION"]
transient = [row for row in rows if row["stop_class"] == "TRANSIENT_OR_EXTERNAL"]
if missing:
    status = "INCOMPLETE"
elif regressions:
    status = "CAPABILITY_REGRESSION"
elif transient:
    status = "BLOCKED_TRANSIENT"
else:
    status = "PASS"
document = {
    "captured_at": datetime.datetime.now().astimezone().isoformat(),
    "phase": "R-capability-preflight",
    "probe_mechanism": "eval/runtime/opencode-v1-adapter/probe.sh",
    "second_probe_system_created": False,
    "status": status,
    "missing_roles": missing,
    "targets": rows,
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if status == "PASS" else 1)
PY
}
