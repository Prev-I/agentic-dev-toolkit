#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
v2_verify_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./v2-http.sh
source "$v2_verify_root/v2-http.sh"

# Effective-routing verifier (OpenCode 2): ask the RUNNING server what each role
# resolves to. It never runs `opencode debug ...` and never reads the database.
#
#   verify_effective_routing_v2 --server URL --credentials FILE --targets FILE \
#     --outdir DIR --neutral-cwd DIR [--project-cwd DIR] [--call]
#
# Writes DIR/effective-routing.json:
#   {runtime_version, server, roles: {<role>: {neutral, project, status}}, overall}
# status is PASS, PROJECT_OVERRIDE or MISMATCH. Exit 0 for PASS or
# PROJECT_OVERRIDE, 1 for MISMATCH (or a server that cannot answer), 2 for
# usage or credentials.
#
# Per role: providerID, model, variant and (when the manifest names one) mode;
# the variant is offered by /api/model for that model; unless the role is the
# breakglass agent, the LAST effective permission entry whose action is
# `subagent` or `*` and whose resource glob-matches `breakglass` is a deny (a
# later `subagent * allow`, `* * allow` or `break* allow` would re-open it); no
# forbidden model reference; and not the manifest's forbidden effective state.
#
# With --project-cwd the same role is resolved in the project directory. The
# project answer is a MISMATCH if it does not resolve or fails any check other
# than "equals the manifest's fields" (breakglass reachable, forbidden reference
# or state, variant not offered). It is PROJECT_OVERRIDE only when it differs
# from the neutral answer on providerID/model/variant/mode and passes every
# other check; a neutral MISMATCH stays MISMATCH. A server that refuses the
# credentials (HTTP 401/403) exits 2. A stale effective-routing.json is removed
# before collecting, so a failed run never leaves an earlier PASS behind.
#
# --call additionally runs each role once through `$OPENCODE_BIN` (default
# `opencode`) with a read probe, and compares the agent, model and variant the
# session actually used (read back from /api/session/<id>/message) with the
# expected ones. The password goes only into the child's environment.

_vr_usage() {
  printf 'usage: verify_effective_routing_v2 --server URL --credentials FILE --targets FILE --outdir DIR --neutral-cwd DIR [--project-cwd DIR] [--call]\n' >&2
}

# Temp directories to remove on exit and on INT/TERM.
_VR_TMPDIRS=()
_vr_cleanup() {
  local d
  for d in "${_VR_TMPDIRS[@]}"; do
    [[ -z "$d" ]] || rm -rf "${d:?}"
  done
  _VR_TMPDIRS=()
}

# The one predicate that picks the assistant message a session used: an object
# (taken from .info when that is an object) with role assistant and a non-empty
# model object. Last match wins.
_VR_PICK_ASSISTANT='[(.data // [])[] | select(type == "object")
  | (if (.info | type) == "object" then .info else . end)
  | select(.role == "assistant" and (.model | type) == "object" and (.model | length) > 0)] | last // empty'

# _vr_call_role URL ROLE WORKDIR -> writes WORKDIR/calls/ROLE.json
_vr_call_role() {
  local url=$1 role=$2 work=$3 probe token out rc=0 sid='' body='' have=0
  probe=$(mktemp -d)
  _VR_TMPDIRS+=("$probe")
  token="probe-$RANDOM-$RANDOM-$$"
  printf '%s\n' "$token" >"$probe/probe.txt"
  out="$work/calls/$role.jsonl"
  (
    cd "$probe"
    OPENCODE_PASSWORD="$V2_PASSWORD" timeout "${V2_CALL_TIMEOUT:-300}" \
      "${OPENCODE_BIN:-opencode}" --server "$url" run --agent "$role" \
      --format json --archived --auto \
      "Read the file probe.txt in the working directory and reply with its exact contents." \
      </dev/null >"$out" 2>"$work/calls/$role.err"
  ) || rc=$?
  rm -rf "$probe"
  sid=$(jq -rs 'map(select(.sessionID != null) | .sessionID) | first // empty' "$out" 2>/dev/null || true)
  if [[ -n "$sid" ]]; then
    for _ in 1 2 3 4 5 6; do
      if body=$(v2_api_get "$url" "/api/session/$sid/message" 2>/dev/null); then
        jq -c "$_VR_PICK_ASSISTANT" <<<"$body" >"$work/calls/$role.assistant.json" 2>/dev/null || true
        if [[ -s "$work/calls/$role.assistant.json" ]]; then
          have=1
          break
        fi
      fi
      sleep 0.5
    done
  fi
  jq -n --argjson rc "$rc" --arg sid "$sid" --argjson have "$have" \
    --slurpfile ev <(jq -c . "$out" 2>/dev/null || true) \
    '{exit_code: $rc, session: $sid, messages: ($have == 1),
      tool_called: ([$ev[] | select(.type == "tool_use" and .part.tool == "read")] | length > 0),
      cost: ([$ev[] | select(.type == "step_finish") | .part.cost // 0] | add // 0)}' \
    >"$work/calls/$role.json"
}

verify_effective_routing_v2() {
  local server='' creds='' targets='' outdir='' neutral='' project='' call=0
  while (( $# )); do
    case "$1" in
      --server|--credentials|--targets|--outdir|--neutral-cwd|--project-cwd)
        (( $# >= 2 )) || { printf 'verify_effective_routing_v2: %s needs a value\n' "$1" >&2; return 2; }
        case "$1" in
          --server) server=$2 ;;
          --credentials) creds=$2 ;;
          --targets) targets=$2 ;;
          --outdir) outdir=$2 ;;
          --neutral-cwd) neutral=$2 ;;
          --project-cwd) project=$2 ;;
        esac
        shift 2 ;;
      --call) call=1; shift ;;
      *) printf 'verify_effective_routing_v2: unknown argument: %s\n' "$1" >&2; _vr_usage; return 2 ;;
    esac
  done
  if [[ -z "$server" || -z "$creds" || -z "$targets" || -z "$outdir" || -z "$neutral" ]]; then
    _vr_usage
    return 2
  fi
  [[ -f "$targets" ]] || { printf 'verify_effective_routing_v2: no such targets file: %s\n' "$targets" >&2; return 2; }
  v2_load_credentials "$creds" || return 2
  server=${server%/}

  # Never leave an earlier result behind: a failed run must not read as a pass.
  mkdir -p "$outdir"
  rm -f "${outdir:?}/effective-routing.json"

  local work rc=0 old_exit old_int old_term
  old_exit=$(trap -p EXIT) old_int=$(trap -p INT) old_term=$(trap -p TERM)
  work=$(mktemp -d)
  _VR_TMPDIRS+=("$work")
  trap '_vr_cleanup' EXIT
  trap '_vr_cleanup; trap - INT; kill -s INT $$' INT
  trap '_vr_cleanup; trap - TERM; kill -s TERM $$' TERM
  _vr_collect "$server" "$targets" "$outdir" "$neutral" "$project" "$call" "$work" || rc=$?
  _vr_cleanup
  trap - EXIT INT TERM
  [[ -z "$old_exit" ]] || eval "$old_exit"
  [[ -z "$old_int" ]] || eval "$old_int"
  [[ -z "$old_term" ]] || eval "$old_term"
  return "$rc"
}

# True when the last request was refused for its credentials.
_vr_auth_refused() {
  [[ "$V2_LAST_STATUS" == 401 || "$V2_LAST_STATUS" == 403 ]]
}

_vr_collect() {
  local server=$1 targets=$2 outdir=$3 neutral=$4 project=$5 call=$6 work=$7
  local role breakglass roles
  mkdir -p "$work/neutral" "$work/project" "$work/calls" "$outdir"

  v2_api_get "$server" /api/info >"$work/info.json" 2>/dev/null || {
    if _vr_auth_refused; then
      printf 'verify_effective_routing_v2: the server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
      return 2
    fi
    printf 'verify_effective_routing_v2: cannot read /api/info from %s (%s)\n' "$server" "$V2_LAST_STATUS" >&2
    return 1
  }
  v2_api_get "$server" /api/model >"$work/models.json" 2>/dev/null || {
    if _vr_auth_refused; then
      printf 'verify_effective_routing_v2: the server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
      return 2
    fi
    printf 'verify_effective_routing_v2: cannot read /api/model from %s (%s)\n' "$server" "$V2_LAST_STATUS" >&2
    return 1
  }

  breakglass=$(jq -r '.breakglass.agent' "$targets")
  roles=$(jq -r '.agents | keys_unsorted[]' "$targets")
  for role in $roles; do
    v2_agent_get "$server" "$role" "$neutral" >"$work/neutral/$role.json" 2>"$work/neutral/$role.err" \
      || rm -f "$work/neutral/$role.json"
    if _vr_auth_refused; then
      printf 'verify_effective_routing_v2: the server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
      return 2
    fi
    if [[ -n "$project" ]]; then
      v2_agent_get "$server" "$role" "$project" >"$work/project/$role.json" 2>"$work/project/$role.err" \
        || rm -f "$work/project/$role.json"
      if _vr_auth_refused; then
        printf 'verify_effective_routing_v2: the server refused the credentials (HTTP %s)\n' "$V2_LAST_STATUS" >&2
        return 2
      fi
    fi
    if (( call )); then
      _vr_call_role "$server" "$role" "$work"
    fi
  done

  python3 -I - "$work" "$targets" "$outdir/effective-routing.json" "$server" \
    "$breakglass" "$([[ -n "$project" ]] && echo 1 || echo 0)" "$call" <<'PY'
import fnmatch, json, os, sys

work, targets_path, out_path, server, breakglass, has_project, call = sys.argv[1:8]
has_project = has_project == "1"
call = call == "1"
targets = json.load(open(targets_path))
models = json.load(open(os.path.join(work, "models.json"))).get("data", [])
info = json.load(open(os.path.join(work, "info.json")))
FIELDS = ("providerID", "model", "variant", "mode")


def load(path):
    """Parsed JSON, or None when the file is absent, empty or not JSON."""
    if not os.path.isfile(path):
        return None
    try:
        return json.load(open(path))
    except ValueError:
        return None


def read_err(path):
    return open(path).read().strip() if os.path.isfile(path) else "no response"


def resolve(data):
    m = data.get("model") or {}
    return {"providerID": m.get("providerID"), "model": m.get("id"),
            "variant": m.get("variant"), "mode": data.get("mode")}


def breakglass_decision(data):
    """The last effective entry that can decide a subagent call to breakglass."""
    deciding = None
    for e in data.get("permissions") or []:
        if (e.get("action") in ("subagent", "*")
                and fnmatch.fnmatchcase("breakglass", str(e.get("resource", "")))):
            deciding = e
    return deciding


def check(role, data):
    """field_mismatches: the resolved fields differ from the manifest.
    other_mismatches: every other check (a project cannot trade these away)."""
    expected = targets["agents"][role]
    got = resolve(data)
    fields, other = [], []
    for f in FIELDS:
        if f == "mode" and expected.get(f) is None:
            continue
        if got[f] != expected.get(f):
            fields.append(f"{f}: expected {expected.get(f)!r}, got {got[f]!r}")
    entry = next((m for m in models
                  if m.get("providerID") == got["providerID"] and m.get("id") == got["model"]), None)
    if entry is None:
        other.append(f"model: {got['providerID']}/{got['model']} is not listed by /api/model")
    else:
        offered = [v.get("id") if isinstance(v, dict) else v for v in entry.get("variants") or []]
        if got["variant"] not in offered:
            other.append(f"variant: {got['variant']!r} is not offered for "
                         f"{got['providerID']}/{got['model']} (offered: {offered})")
    for ref in targets.get("forbidden_model_references", []):
        if got["model"] and ref in got["model"]:
            other.append(f"model: {got['model']!r} contains forbidden reference {ref!r}")
    forbidden = targets.get("forbidden_effective_state", {}).get(role)
    if isinstance(forbidden, dict) and all(
            got[k] == forbidden.get(k) for k in ("providerID", "model", "variant")):
        other.append("forbidden_effective_state: role resolves to the forbidden "
                     f"{forbidden['providerID']}/{forbidden['model']}#{forbidden['variant']}")
    record = {"resolved": got}
    if role != breakglass:
        deciding = breakglass_decision(data)
        record["subagent_breakglass"] = deciding
        if not (deciding and deciding.get("effect") == "deny"):
            other.append("permissions: the last subagent/* entry matching breakglass is "
                         f"{json.dumps(deciding)}, not a deny")
    record["field_mismatches"] = fields
    record["other_mismatches"] = other
    record["mismatches"] = fields + other
    record["status"] = "MISMATCH" if record["mismatches"] else "PASS"
    return record


def lookup(kind, role):
    data = load(os.path.join(work, kind, role + ".json"))
    if data is None:
        msg = f"agent did not resolve: {read_err(os.path.join(work, kind, role + '.err'))}"
        return {"resolved": None, "field_mismatches": [], "other_mismatches": [msg],
                "mismatches": [msg], "status": "MISMATCH"}
    return check(role, data)


def called(role):
    base = load(os.path.join(work, "calls", role + ".json")) or {}
    assistant = load(os.path.join(work, "calls", role + ".assistant.json"))
    rec = {"used": None, "tool_called": base.get("tool_called", False), "cost": base.get("cost", 0),
           "exit_code": base.get("exit_code"), "session": base.get("session")}
    problems = []
    if base.get("exit_code") not in (0, None):
        problems.append(f"call: opencode run exited {base.get('exit_code')}")
    if not isinstance(assistant, dict):
        problems.append("call: no assistant message with a model could be read back")
        return rec, problems
    model = assistant.get("model") if isinstance(assistant.get("model"), dict) else {}
    rec["used"] = (f"{assistant.get('agent')}@{model.get('providerID')}/"
                   f"{model.get('id')}#{model.get('variant')}")
    e = targets["agents"][role]
    want = f"{role}@{e['providerID']}/{e['model']}#{e['variant']}"
    if rec["used"] != want:
        problems.append(f"call: used {rec['used']}, expected {want}")
    return rec, problems


roles = {}
for role in targets["agents"]:
    n = lookup("neutral", role)
    entry = {"neutral": n}
    status = n["status"]
    if has_project:
        p = lookup("project", role)
        if p["other_mismatches"]:
            p["status"] = "MISMATCH"
        elif p["resolved"] != n["resolved"]:
            p["differs"] = [f for f in FIELDS if (p["resolved"] or {}).get(f) != (n["resolved"] or {}).get(f)]
            p["status"] = "PROJECT_OVERRIDE"
        else:
            p["status"] = "PASS"
        entry["project"] = p
        if status == "PASS":
            status = p["status"]
    if call:
        rec, problems = called(role)
        entry["called"] = rec
        if problems:
            entry["called_mismatches"] = problems
            status = "MISMATCH"
    entry["status"] = status
    roles[role] = entry

statuses = {r["status"] for r in roles.values()}
overall = "MISMATCH" if "MISMATCH" in statuses else ("PROJECT_OVERRIDE" if "PROJECT_OVERRIDE" in statuses else "PASS")
doc = {"runtime_version": info.get("version"), "server": server, "roles": roles, "overall": overall}
with open(out_path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
for role, r in roles.items():
    detail = list(r["neutral"]["mismatches"])
    p = r.get("project")
    if p and p["status"] == "MISMATCH":
        detail += ["project: " + m for m in p["mismatches"]]
    elif p and p["status"] == "PROJECT_OVERRIDE":
        detail.append("project differs on: " + ", ".join(p["differs"]))
    detail += r.get("called_mismatches", [])
    print(f"{r['status']:<16} {role}" + (f"  ({'; '.join(detail)})" if detail else ""))
print(f"overall: {overall}")
sys.exit(1 if overall == "MISMATCH" else 0)
PY
}
