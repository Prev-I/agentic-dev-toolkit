#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
v2_probe_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-run.sh disable=SC1091 # path built from the script's own directory at run time
source "$v2_probe_root/v2-run.sh"

# Breakglass probe (OpenCode 2): the emergency agent must resolve as a primary
# agent with the manifest's model, and no other agent may be able to dispatch it.
#
#   probe_breakglass_v2 --server URL --credentials FILE --targets FILE \
#     --outdir DIR --cwd DIR [--call]
#
# Writes DIR/breakglass.json:
#   {resolved_primary, model, non_exposure: {<agent>: deny|EXPOSED|UNRESOLVED},
#    called?, status}
# Exit 0 on PASS, 1 on FAIL, 2 on usage or credentials (incl. HTTP 401/403).
# UNRESOLVED (an agent that cannot be read) is a FAIL, never a skip. So is an
# agent list that could not be read at all: the probe could not enumerate the
# agents, so it cannot claim breakglass is unreachable.
#
# "Every other agent" is every agent the server lists for --cwd
# (GET /api/agent?directory=...) plus every manifest role, so built-in and user
# agents are covered. Each is looked up by name (polled: agents load lazily).
# An agent is `deny` when the LAST effective permission entry whose action is
# `subagent` or `*` and whose resource glob-matches the breakglass agent is a
# deny; `EXPOSED` otherwise (including no matching entry); `UNRESOLVED` when it
# cannot be read, which also fails the probe. The agent name and the expected
# model come from the manifest's `breakglass.agent` and `agents.<name>`.
#
# --call additionally runs breakglass once through `$OPENCODE_BIN` (default
# `opencode`) with a read probe and compares the agent, model and variant the
# session actually used with the expected ones. The password goes only into the
# child's environment. A stale breakglass.json is removed before collecting.

_pb_usage() {
  printf 'usage: probe_breakglass_v2 --server URL --credentials FILE --targets FILE --outdir DIR --cwd DIR [--call]\n' >&2
}

probe_breakglass_v2() {
  local server='' creds='' targets='' outdir='' cwd='' call=0
  while (( $# )); do
    case "$1" in
      --server|--credentials|--targets|--outdir|--cwd)
        (( $# >= 2 )) || { printf 'probe_breakglass_v2: %s needs a value\n' "$1" >&2; return 2; }
        case "$1" in
          --server) server=$2 ;;
          --credentials) creds=$2 ;;
          --targets) targets=$2 ;;
          --outdir) outdir=$2 ;;
          --cwd) cwd=$2 ;;
        esac
        shift 2 ;;
      --call) call=1; shift ;;
      *) printf 'probe_breakglass_v2: unknown argument: %s\n' "$1" >&2; _pb_usage; return 2 ;;
    esac
  done
  if [[ -z "$server" || -z "$creds" || -z "$targets" || -z "$outdir" || -z "$cwd" ]]; then
    _pb_usage
    return 2
  fi
  mkdir -p "$outdir"
  rm -f "${outdir:?}/breakglass.json"
  [[ -f "$targets" ]] || { printf 'probe_breakglass_v2: no such targets file: %s\n' "$targets" >&2; return 2; }
  v2_load_credentials "$creds" || return 2
  server=${server%/}

  v2_run_isolated _pb_collect "$server" "$targets" "$outdir" "$cwd" "$call"
}

_pb_refused() {
  printf 'probe_breakglass_v2: the server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
}

# _pb_list_agents URL CWD MANIFEST_ROLES OUTFILE -> agent ids to OUTFILE, one per
# line (called directly, not in $(...), so V2_LAST_STATUS stays visible).
# Polls until the list holds every manifest role, bounded by
# V2_AGENT_POLL_TIMEOUT; the last list read is used even if still short. Returns
# 1 (empty OUTFILE) when no read ever returned a `.data` array, 2 when the
# server refused the credentials. The last status is left in V2_LAST_STATUS.
_pb_list_agents() {
  local base=$1 dir=$2 roles=$3 out=$4 encoded deadline ids='' rc have=0 want
  encoded=$(jq -rn --arg d "$dir" '$d|@uri')
  want=$(jq -Rn '[inputs]' <<<"$roles")
  deadline=$(( SECONDS + ${V2_AGENT_POLL_TIMEOUT:-30} ))
  while :; do
    rc=0
    v2_api_get "$base" "/api/agent?directory=$encoded" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && jq -e '(.data | type) == "array"' <<<"$V2_LAST_BODY" >/dev/null 2>&1; then
      have=1
      ids=$(jq -r '.data[] | select(type == "object") | .id // empty | strings' <<<"$V2_LAST_BODY" 2>/dev/null || true)
      if jq -e --argjson want "$want" '. as $have | $want | all(. as $r | $have | index($r) != null)' \
        <<<"$(jq -Rn '[inputs]' <<<"$ids")" >/dev/null 2>&1; then
        break
      fi
    fi
    case $V2_LAST_STATUS in
      401|403) return 2 ;;
    esac
    (( SECONDS < deadline )) || break
    sleep 0.25
  done
  (( have )) || return 1
  [[ -z "$ids" ]] || printf '%s\n' "$ids" >"$out"
}

_pb_collect() {
  local work=$1 server=$2 targets=$3 outdir=$4 cwd=$5 call=$6
  local breakglass roles listed names name i=0 rc list_error=''
  mkdir -p "$work/agents" "$work/calls" "$outdir"
  breakglass=$(jq -r '.breakglass.agent' "$targets")
  roles=$(jq -r '.agents | keys_unsorted[]' "$targets")

  rc=0
  : >"$work/listed.txt"
  _pb_list_agents "$server" "$cwd" "$roles" "$work/listed.txt" || rc=$?
  listed=$(<"$work/listed.txt")
  if (( rc == 2 )) || v2_auth_refused; then
    _pb_refused
    return 2
  fi
  if (( rc != 0 )); then
    list_error="agent list for $cwd could not be read (last status ${V2_LAST_STATUS:-none})"
  fi
  # Every listed agent plus every manifest role, once each, breakglass included.
  names=$(printf '%s\n%s\n' "$roles" "$listed" | awk 'NF && !seen[$0]++')

  : >"$work/names.tsv"
  while IFS= read -r name; do
    i=$((i + 1))
    printf '%s\t%s\n' "$i" "$name" >>"$work/names.tsv"
    if [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      v2_agent_get "$server" "$name" "$cwd" >"$work/agents/$i.json" 2>"$work/agents/$i.err" \
        || rm -f "$work/agents/$i.json"
    else
      printf 'agent name %s cannot be looked up safely\n' "$name" >"$work/agents/$i.err"
    fi
    if v2_auth_refused; then
      _pb_refused
      return 2
    fi
  done <<<"$names"
  if (( call )); then
    v2_call_role "$server" "$breakglass" "$work"
  fi

  python3 -I - "$work" "$targets" "$outdir/breakglass.json" "$call" "$v2_probe_root" "$list_error" <<'PY'
import json, os, sys

work, targets_path, out_path, call, adapter, list_error = sys.argv[1:7]
call = call == "1"
sys.dont_write_bytecode = True
sys.path.insert(0, adapter)
from v2config import breakglass_decision  # noqa: E402

targets = json.load(open(targets_path))
name = targets["breakglass"]["agent"]
expected = targets["agents"][name]


def load(path):
    if not os.path.isfile(path):
        return None
    try:
        return json.load(open(path))
    except ValueError:
        return None


problems = [list_error] if list_error else []
agents = []
for line in open(os.path.join(work, "names.tsv")).read().splitlines():
    idx, agent = line.split("\t", 1)
    agents.append((agent, load(os.path.join(work, "agents", idx + ".json")),
                   os.path.join(work, "agents", idx + ".err")))

record = {"resolved_primary": False, "model": None, "non_exposure": {}}
non_exposure = record["non_exposure"]
for agent, data, err in agents:
    if agent == name:
        if data is None:
            reason = open(err).read().strip() if os.path.isfile(err) else "no response"
            problems.append(f"{name}: did not resolve: {reason}")
            continue
        m = data.get("model") or {}
        record["model"] = f"{m.get('providerID')}/{m.get('id')}#{m.get('variant')}"
        want = f"{expected['providerID']}/{expected['model']}#{expected['variant']}"
        mode_ok = data.get("mode") == "primary"
        model_ok = record["model"] == want
        record["resolved_primary"] = mode_ok and model_ok
        if not mode_ok:
            problems.append(f"{name}: mode is {data.get('mode')!r}, expected 'primary'")
        if not model_ok:
            problems.append(f"{name}: model is {record['model']}, expected {want}")
        continue
    if data is None:
        non_exposure[agent] = "UNRESOLVED"
        problems.append(f"{agent}: did not resolve, so its access to {name} is unknown")
        continue
    deciding = breakglass_decision(data.get("permissions"), name)
    if deciding and deciding.get("effect") == "deny":
        non_exposure[agent] = "deny"
    else:
        non_exposure[agent] = "EXPOSED"
        problems.append(f"{agent}: can dispatch {name} (deciding entry: {json.dumps(deciding)})")

if call:
    base = load(os.path.join(work, "calls", name + ".json")) or {}
    assistant = load(os.path.join(work, "calls", name + ".assistant.json"))
    rec = {"used": None, "tool_called": base.get("tool_called", False),
           "cost": base.get("cost", 0), "exit_code": base.get("exit_code"),
           "session": base.get("session")}
    if base.get("exit_code") not in (0, None):
        problems.append(f"call: opencode run exited {base.get('exit_code')}")
    if not isinstance(assistant, dict):
        problems.append("call: no assistant message with a model could be read back")
    else:
        model = assistant.get("model") if isinstance(assistant.get("model"), dict) else {}
        rec["used"] = (f"{assistant.get('agent')}@{model.get('providerID')}/"
                       f"{model.get('id')}#{model.get('variant')}")
        want = f"{name}@{expected['providerID']}/{expected['model']}#{expected['variant']}"
        if rec["used"] != want:
            problems.append(f"call: used {rec['used']}, expected {want}")
    record["called"] = rec

record["status"] = "FAIL" if problems else "PASS"
with open(out_path, "w") as f:
    json.dump(record, f, indent=2)
    f.write("\n")
print(f"{record['status']:<8} {name}  resolved_primary={str(record['resolved_primary']).lower()}"
      f" model={record['model']}")
for agent, state in non_exposure.items():
    print(f"{state:<10} {agent}" if state == "deny" else f"{state:<8} {agent}")
for p in problems:
    print(f"  - {p}")
sys.exit(1 if problems else 0)
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then probe_breakglass_v2 "$@"; fi
