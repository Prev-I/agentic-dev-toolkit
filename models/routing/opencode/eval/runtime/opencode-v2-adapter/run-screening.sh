#!/usr/bin/env bash
# The per-role screening runner for OpenCode 2. Three phases, with the
# operator's approval between the first two:
#
#   run-screening.sh prepare --role ROLE --out DIR --candidate KEY=SPEC [--candidate KEY=SPEC]...
#       --runs N --budget CREDITS --providers FILE --credentials FILE
#       [--profile FILE --profile-id ID] [--opencode-dir DIR] [--timeout S]
#   run-screening.sh dispatch --out DIR --providers FILE --credentials FILE [--profile FILE]
#   run-screening.sh score --out DIR
#
# ROLE names roles/ROLE.json. SPEC is model:PROVIDER/MODEL#VARIANT, or
# agent:NAME (an agent of --profile, which it requires). KEY matches
# ^[a-z0-9][a-z0-9-]{0,23}$ and is unique. DIR must not exist, its basename
# starts with v2-, and it may not resolve inside a real OpenCode directory
# (v2config.py real-dirs). --opencode-dir defaults to
# models/routing/opencode/v2/.opencode; --timeout to the role's.
#
# prepare writes DIR/protocol.json, DIR/catalog-snapshot.json (GET /api/model
# of one sandboxed server, no model call) and DIR/freeze-manifest.json, and
# prints on stdout the approval.json the operator must write into DIR. It
# refuses (1) a model the catalog does not list, a variant it does not offer,
# and a model whose cost is [] (no cap could hold); DIR is then removed. The
# freeze also covers --opencode-dir's model-routing.md and agents/*.md: in place
# when the directory is inside the toolkit (protocol opencode_dir is then
# toolkit-relative), else as a copy in DIR/opencode-dir/ that dispatch uses
# (opencode_dir is then absolute).
#
# dispatch exits 3 unless DIR/approval.json is exactly that object and the
# providers, credentials and profile digests match the protocol, and when the
# OpenCode runtime differs from protocol runtime_version (measured as prepare
# does: GET /api/info of one sandboxed server, no model call; nothing is then
# written); 2 when runs/ or capability/ exist; 1 on a freeze mismatch (verified
# before every call). Each candidate is probed into capability/KEY/, then for
# rep 1..N and each workload in definition order the live candidates run,
# forward when (rep + workload_index) % 2 == 1 (workload_index from 0), else
# reversed. A run is runs/NN-WORKLOAD-rREP-KEY/: dispatch/, reported.json or
# extract-error.txt (extract: json) and work-product.patch (capture_patch). A
# model candidate runs as the role's agent with its model; an agent candidate
# runs the profile alone. Either way every call is checked against the
# candidate's protocol `expect` (AGENT@P/M#V, frozen at prepare). Stops
# (Ruling 5): a failed probe (STOPPED_CAPABILITY) or CAPABILITY_REGRESSION
# stops the candidate; BUDGET_STOP, a refused admission, an unknown cost
# (UNKNOWN_COST), a call cut off mid-step (cost_complete false: INCOMPLETE_COST),
# an exposed credential (CREDENTIAL_EXPOSED), a probe classified
# INVALID_ENVIRONMENT, or no live candidate after the probes halts the
# screening, as does an unexpected error (halted reason ERROR).
#
# The model's tools run with the operator's uid, so after every call (probes
# included) each string value of 12 or more characters in the credentials file
# and in the provider fragment is searched for in the call's output directory
# and, for the build role, in the workspace copy and work-product.patch. Every
# occurrence is replaced in place with [REDACTED], the call's dispatch.json is
# classified CREDENTIAL_EXPOSED, and the screening halts. Nothing found is
# printed except the names of the files changed.
# status.json is {state: COMPLETE|INCOMPLETE, stopped: {KEY: REASON}, halted};
# exit 0 when COMPLETE, 1 when INCOMPLETE. The budget (Ruling 6) is one account
# candidate_KEY per candidate with cap = budget / candidates, admission per call
# cap / (runs * workloads + 1), and the in-flight stop the account's remainder.
#
# A workspace is the workload's base with every overlay file copied to its root
# under its own name; oracle files (ground-truth.json, oracle.json) are never
# copied in. The patch compares that workspace with what the call left.
#
# score verifies the freeze manifest, and that its sha256 is approval.json's
# freeze_manifest_sha256, first (1 on a mismatch, nothing written), then runs the role's normalise and score argv (placeholders {eval} {repo}
# {record} {fixture} {key} {rep}) and writes DIR/result.md. A candidate-run
# whose normaliser reports "clean control missing" (exit 3) is NOT_SCORABLE;
# any other scorer failure is listed in result.md and makes score exit 1. Its
# Spend total is marked a lower bound when any call's cost is unknown or
# incomplete; a per-run score row shows the findings' missing_runs count, and a
# role scored per record names its score.file in every row. It never writes
# adjudication.json.
#
# The runner's own TMPDIR is DIR/.work and sandboxes live under it; an EXIT,
# INT, TERM and HUP trap removes it, after stopping by recorded pid any sandbox
# server still running there. Calls run one at a time, each in its own session,
# and a signal stops the running call's process group before the runner exits.
# A .work that an abnormal end (SIGKILL, OOM, a shutdown) left behind is
# removed when dispatch or score starts, before any refusal, after stopping each
# recorded pid that is alive and whose working directory is its sandbox's work/;
# one line on stderr says so. The runner's files are created under umask 077.
# The record holds only the sha256 of the provider fragment, credentials and
# profile.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
adapter=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
eval_root=$(cd "$adapter/../.." && pwd)
repo=$(cd "$eval_root/../../../.." && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-sandbox.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/v2-sandbox.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/dispatch-fixture.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/dispatch-fixture.sh"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/verify-freeze-manifest.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/verify-freeze-manifest.sh"

out=''
work=''
catalog_sb=''
child=''
created_out=false
prepared=false
phase=''
status_written=false
declare -A stopped=()
halted_reason=''
halted_label=''

err() {
  printf 'run-screening: %s\n' "$*" >&2
}

die() {
  local code=$1
  shift
  err "$@"
  exit "$code"
}

sha256() {
  sha256sum -- "$1" | cut -d' ' -f1
}

# Stop the running call's process group and wait until all of it is gone.
stop_child() {
  local pid=$child i
  [[ -n "$pid" ]] || return 0
  child=''
  kill -s TERM -- "-$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  for ((i = 0; i < 300; i++)); do
    kill -0 -- "-$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -s KILL -- "-$pid" 2>/dev/null || true
}

# Stop every sandbox server under .work that is still running, by the pid its
# sandbox recorded: covers a call whose own cleanup never ran.
stop_sandbox_servers() {
  local f pid
  [[ -n "$work" && -d "$work" ]] || return 0
  for f in "$work"/sandbox.*/pid; do
    [[ -f "$f" ]] || continue
    pid=$(<"$f")
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      v2_stop_pid "$pid"
    fi
  done
}

# A .work an abnormal end left in the record: it may hold sandbox credentials,
# databases and configs with the provider fragment. Only a recorded pid that is
# alive and runs in its sandbox's work/ is stopped; any other is left alone.
clear_stale_work() {
  local stale f pid sb
  [[ -n "$out" && -f "$out/protocol.json" ]] || return 0
  stale="$out/.work"
  [[ -d "$stale" && ! -L "$stale" ]] || return 0
  for f in "$stale"/sandbox.*/pid; do
    [[ -f "$f" ]] || continue
    pid=$(<"$f")
    sb=$(dirname -- "$f")
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    kill -0 "$pid" 2>/dev/null || continue
    [[ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" == "$(realpath -m -- "$sb/work")" ]] || continue
    v2_stop_pid "$pid"
  done
  rm -rf -- "$stale"
  err "removed a stale scratch area left by an earlier run: $stale"
}

on_exit() {
  local rc=$?
  stop_child
  if [[ "$phase" == dispatch && "$rc" != 0 && "$status_written" == false ]]; then
    halted_reason=ERROR
    write_status || true
  fi
  stop_sandbox_servers
  if [[ -n "$catalog_sb" ]]; then
    v2_sandbox_destroy "$catalog_sb" || true
    catalog_sb=''
  fi
  [[ -z "$work" ]] || rm -rf -- "$work"
  if [[ "$created_out" == true && "$prepared" == false ]]; then
    rm -rf -- "$out"
  fi
  exit "$rc"
}

on_signal() {
  trap - INT TERM HUP
  stop_child
  if [[ "$phase" == dispatch ]]; then
    halted_reason=INTERRUPTED
    write_status || true
  fi
  exit "$1"
}

trap on_exit EXIT
trap 'on_signal 143' TERM
trap 'on_signal 130' INT
trap 'on_signal 129' HUP

# Run "$@" in a new session (its pid leads the group) and wait for it in a way a
# trapped signal interrupts; the status is the command's.
run_child() {
  local rc=0
  setsid "$@" &
  child=$!
  wait "$child" || rc=$?
  child=''
  return "$rc"
}

# A role file's string with its placeholders replaced.
expand() {
  local s=$1 key=${2:-} rep=${3:-}
  # Quoted replacements: bash 5.2's patsub_replacement would otherwise expand
  # an & in a path to the matched placeholder.
  s=${s//\{eval\}/"$eval_root"}
  s=${s//\{repo\}/"$repo"}
  s=${s//\{record\}/"$out"}
  s=${s//\{fixture\}/"$fixture"}
  s=${s//\{key\}/"$key"}
  s=${s//\{rep\}/"$rep"}
  printf '%s' "$s"
}

# A role file's path: expanded, and toolkit-root-relative unless absolute.
resolve_path() {
  local p
  p=$(expand "$@")
  [[ "$p" == /* ]] || p="$repo/$p"
  printf '%s' "$p"
}

load_role() {
  local file=$1 f
  role_file=$file
  jq -e 'type == "object" and (.agent | type == "object") and (.workloads | type == "array" and length > 0)' \
    "$role_file" >/dev/null 2>&1 || die 2 "not a role definition: $role_file"
  f=$(jq -r '.fixture // ""' "$role_file")
  fixture=''
  [[ -z "$f" ]] || fixture=$(resolve_path "$f")
  agent_name=$(jq -r '.agent.name' "$role_file")
}

check_out() {
  local resolved dir real dirs
  [[ "$(basename -- "$out")" == v2-* ]] || die 2 "the record's name must start with v2-: $out"
  resolved=$(realpath -m -- "$out")
  dirs=$(python3 -I -B "$adapter/v2config.py" real-dirs) || die 2 "cannot list the real OpenCode directories"
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    real=$(realpath -m -- "$dir")
    if [[ "$resolved" == "$real" || "$resolved" == "$real"/* ]]; then
      die 2 "refusing $out: it resolves inside the real OpenCode directory $dir"
    fi
  done <<<"$dirs"
  out=$resolved
}

need_file() {
  [[ -f "$2" ]] || die 2 "$1: no such file: $2"
}

# ---------------------------------------------------------------- prepare

prepare() {
  local role='' runs='' budget='' providers='' creds='' profile='' profile_id='' timeout=''
  local ocdir="$repo/models/routing/opencode/v2/.opencode"
  local -a cands=()
  while (( $# )); do
    (( $# >= 2 )) || die 2 "option $1 needs a value"
    case "$1" in
      --role) role=$2 ;;
      --out) out=$2 ;;
      --candidate) cands+=("$2") ;;
      --runs) runs=$2 ;;
      --budget) budget=$2 ;;
      --providers) providers=$2 ;;
      --credentials) creds=$2 ;;
      --profile) profile=$2 ;;
      --profile-id) profile_id=$2 ;;
      --opencode-dir) ocdir=$2 ;;
      --timeout) timeout=$2 ;;
      *) die 2 "unknown option $1" ;;
    esac
    shift 2
  done
  [[ -n "$role" && -n "$out" && -n "$runs" && -n "$budget" ]] || die 2 "--role, --out, --runs and --budget are required"
  (( ${#cands[@]} )) || die 2 "at least one --candidate KEY=SPEC is required"
  [[ "$role" =~ ^[a-z0-9-]+$ && -f "$adapter/roles/$role.json" ]] || die 2 "no such role: $role"
  [[ "$runs" =~ ^[1-9][0-9]*$ ]] || die 2 "--runs takes a positive integer"
  [[ "$budget" =~ ^[0-9]+([.][0-9]+)?$ && ! "$budget" =~ ^0+([.]0+)?$ ]] || die 2 "--budget takes a positive number"
  [[ -z "$timeout" || "$timeout" =~ ^[1-9][0-9]*$ ]] || die 2 "--timeout takes a positive integer"
  need_file --providers "$providers"
  need_file --credentials "$creds"
  if [[ -n "$profile" || -n "$profile_id" ]]; then
    [[ -n "$profile" && -n "$profile_id" ]] || die 2 "--profile and --profile-id go together"
    need_file --profile "$profile"
  fi
  [[ -d "$ocdir" ]] || die 2 "no such --opencode-dir: $ocdir"
  ocdir=$(cd "$ocdir" && pwd -P)
  load_role "$adapter/roles/$role.json"
  [[ -n "$timeout" ]] || timeout=$(jq -r '.timeout_seconds' "$role_file")

  local c key spec seen=' ' candidates='[]'
  for c in "${cands[@]}"; do
    key=${c%%=*}
    spec=${c#*=}
    [[ "$c" == *=* && "$key" =~ ^[a-z0-9][a-z0-9-]{0,23}$ ]] || die 2 "bad candidate key in $c"
    [[ "$seen" != *" $key "* ]] || die 2 "duplicate candidate key: $key"
    seen+="$key "
    if [[ "$spec" =~ ^model:([^/#]+)/([^#]+)#([^#]+)$ ]]; then
      candidates=$(jq -c --arg k "$key" --arg s "$spec" --arg p "${BASH_REMATCH[1]}" \
        --arg m "${BASH_REMATCH[2]}" --arg v "${BASH_REMATCH[3]}" --arg a "$agent_name" \
        '. + [{key: $k, spec: $s, kind: "model", agent: $a, providerID: $p, model: $m, variant: $v}]' <<<"$candidates")
    elif [[ "$spec" =~ ^agent:([A-Za-z0-9_-]+)$ ]]; then
      [[ -n "$profile" ]] || die 2 "candidate $key ($spec) needs --profile"
      candidates=$(jq -c --arg k "$key" --arg s "$spec" --arg a "${BASH_REMATCH[1]}" \
        '. + [{key: $k, spec: $s, kind: "agent", agent: $a}]' <<<"$candidates")
    else
      die 2 "candidate $key: SPEC is model:PROVIDER/MODEL#VARIANT or agent:NAME, not $spec"
    fi
  done
  [[ ! -e "$out" && ! -L "$out" ]] || die 2 "the record already exists: $out"
  check_out

  mkdir -p -- "$(dirname -- "$out")"
  mkdir -- "$out" || die 2 "cannot create the record $out"
  created_out=true
  work="$out/.work"
  mkdir -- "$work"
  export TMPDIR="$work"

  # One sandboxed server for the catalog: no model call.
  local base=- sb url version
  [[ -z "$profile" ]] || base=$profile
  python3 -I -B "$adapter/v2config.py" build-config "$base" "$providers" - "$work/catalog-config.json" \
    || die 1 "cannot build the catalog server's config"
  sb=$(v2_sandbox_create "$work") || die 1 "cannot create the catalog sandbox"
  catalog_sb=$sb
  v2_sandbox_populate "$sb" "$work/catalog-config.json" "$creds" "$ocdir" || die 1 "cannot populate the catalog sandbox"
  v2_sandbox_serve "$sb" || die 1 "the catalog server did not start"
  url=$(<"$sb/url")
  version=$(<"$sb/version")
  v2_api_get "$url" /api/model >"$work/models.json" || die 1 "cannot read GET /api/model"
  local i n kind agent data
  n=$(jq length <<<"$candidates")
  for ((i = 0; i < n; i++)); do
    kind=$(jq -r ".[$i].kind" <<<"$candidates")
    [[ "$kind" == agent ]] || continue
    agent=$(jq -r ".[$i].agent" <<<"$candidates")
    data=$(v2_agent_get "$url" "$agent" "$sb/work") || die 1 "the profile's agent $agent does not resolve"
    candidates=$(jq -c --argjson i "$i" --argjson d "$data" \
      '.[$i] += {providerID: $d.model.providerID, model: $d.model.id, variant: $d.model.variant}' <<<"$candidates")
  done
  v2_sandbox_destroy "$sb" || true
  catalog_sb=''

  local commit
  commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || printf unknown)
  printf '%s' "$candidates" >"$work/candidates.json"
  EXPERIMENT_ID="$(basename -- "$out")-$(date -u +%Y%m%d)" ROLE="$role" \
    ROLE_DEFINITION="${role_file#"$repo"/}" RUNS="$runs" BUDGET="$budget" TIMEOUT="$timeout" \
    PROVIDERS_SHA="$(sha256 "$providers")" CREDENTIALS_SHA="$(sha256 "$creds")" \
    PROFILE_ID="$profile_id" PROFILE_SHA="$([[ -z "$profile" ]] || sha256 "$profile")" \
    RUNTIME="$version" COMMIT="$commit" OPENCODE_DIR="${ocdir#"$repo"/}" WORKLOADS="$(jq '.workloads | length' "$role_file")" \
    python3 -I -B - "$work/candidates.json" "$work/models.json" "$out" <<'PY' || die 1 "the catalog refuses a candidate"
import datetime
import json
import os
import sys

env = os.environ
candidates = json.load(open(sys.argv[1], encoding="utf-8"))
models = json.load(open(sys.argv[2], encoding="utf-8")).get("data", [])
out = sys.argv[3]
listed = {(m.get("providerID"), m.get("id")): m for m in models if isinstance(m, dict)}
problems = []
for c in candidates:
    entry = listed.get((c["providerID"], c["model"]))
    name = "%s/%s" % (c["providerID"], c["model"])
    if entry is None:
        problems.append("%s: %s is not listed by GET /api/model" % (c["key"], name))
        continue
    offered = [v.get("id") if isinstance(v, dict) else v for v in entry.get("variants") or []]
    if c["variant"] not in offered:
        problems.append("%s: variant %r is not offered for %s (offered: %s)"
                        % (c["key"], c["variant"], name, offered))
    cost = entry.get("cost")
    if not isinstance(cost, list) or not cost:
        problems.append("%s: %s has no reported cost (cost %s); no budget cap could hold"
                        % (c["key"], name, json.dumps(cost)))
if problems:
    sys.stderr.write("".join("run-screening: %s\n" % p for p in problems))
    sys.exit(1)

providers = {c["providerID"] for c in candidates}
snapshot = {
    "runtime_version": env["RUNTIME"],
    "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "models": {"%s/%s" % key: {"variants": [v.get("id") if isinstance(v, dict) else v
                                             for v in m.get("variants") or []],
                               "cost": m.get("cost")}
               for key, m in sorted(listed.items()) if key[0] in providers},
}


def number(value):
    value = round(value, 10)
    return int(value) if float(value).is_integer() else value


budget = number(float(env["BUDGET"]))
calls = int(env["RUNS"]) * int(env["WORKLOADS"]) + 1
cap = number(budget / len(candidates))
protocol = {
    "experiment_id": env["EXPERIMENT_ID"],
    "status_at_freeze": "AWAITING_APPROVAL",
    "role": env["ROLE"],
    "role_definition": env["ROLE_DEFINITION"],
    "candidates": [{"key": c["key"], "spec": c["spec"], "account": "candidate_" + c["key"],
                    "expect": "%s@%s/%s#%s" % (c["agent"], c["providerID"], c["model"], c["variant"])}
                   for c in candidates],
    "runs": int(env["RUNS"]),
    "order": "rep 1..runs; workloads in definition order; live candidates in this order when "
             "(rep + workload_index) % 2 == 1 (workload_index from 0), else reversed; "
             "every candidate's capability probe first",
    "timeout_seconds": int(env["TIMEOUT"]),
    "budget": {"ceiling_credits": budget, "per_candidate_cap": cap,
               "calls_per_candidate": calls, "admission_per_call": number(cap / calls)},
    "providers_sha256": env["PROVIDERS_SHA"],
    "credentials_sha256": env["CREDENTIALS_SHA"],
    "profile_id": env["PROFILE_ID"] or None,
    "profile_digest": env["PROFILE_SHA"] or None,
    "opencode_dir": env["OPENCODE_DIR"],
    "runtime_version": env["RUNTIME"],
    "toolkit_commit": env["COMMIT"],
}
for name, document in (("catalog-snapshot.json", snapshot), ("protocol.json", protocol)):
    with open(os.path.join(out, name), "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
PY

  # The freeze: the role definition, the adapter, every frozen path (a
  # directory stands for every file under it), the protocol and the snapshot.
  local -a files=("$role_file" "$adapter"/*.sh "$adapter/v2config.py")
  local p
  while IFS= read -r p; do
    p=$(resolve_path "$p")
    if [[ -d "$p" ]]; then
      mapfile -t -O "${#files[@]}" files < <(find "$p" -type f | LC_ALL=C sort)
    else
      [[ -f "$p" ]] || die 1 "a frozen path does not exist: $p"
      files+=("$p")
    fi
  done < <(jq -r '.frozen[]' "$role_file")
  # The files every sandbox installs from --opencode-dir. Outside the toolkit
  # they cannot be frozen in place, so the record keeps a copy that dispatch uses.
  local src=$ocdir
  if [[ "$ocdir" != "$repo"/* ]]; then
    src="$out/opencode-dir"
    mkdir -p "$src/agents"
    cp -- "$ocdir/model-routing.md" "$src/" || die 1 "no model-routing.md in $ocdir"
    for p in "$ocdir"/agents/*.md; do
      [[ ! -f "$p" ]] || cp -- "$p" "$src/agents/"
    done
  fi
  [[ -f "$src/model-routing.md" ]] || die 1 "no model-routing.md in $ocdir"
  files+=("$src/model-routing.md")
  for p in "$src"/agents/*.md; do
    [[ ! -f "$p" ]] || files+=("$p")
  done
  files+=("$out/protocol.json" "$out/catalog-snapshot.json")
  local id
  id=$(jq -r .experiment_id "$out/protocol.json")
  write_freeze_manifest "$repo" "$out" "$id" "$out/freeze-manifest.json" "${files[@]}" \
    || die 1 "cannot write the freeze manifest"
  prepared=true
  jq -n --arg id "$id" --argjson c "$(jq '.budget.ceiling_credits' "$out/protocol.json")" \
    --arg sha "$(sha256 "$out/freeze-manifest.json")" \
    '{experiment_id: $id, status: "APPROVED_FOR_DISPATCH", approved_ceiling_credits: $c, freeze_manifest_sha256: $sha}'
  err "prepared $out; to approve, write the object above to $out/approval.json"
}

# ---------------------------------------------------------------- dispatch

write_status() {
  local s='{}' k state=COMPLETE
  for k in "${!stopped[@]}"; do
    s=$(jq -c --arg k "$k" --arg v "${stopped[$k]}" '. + {($k): $v}' <<<"$s")
  done
  [[ -z "$halted_reason" ]] || state=INCOMPLETE
  jq -n --arg st "$state" --argjson s "$s" --arg r "$halted_reason" --arg l "$halted_label" \
    '{state: $st, stopped: $s, halted: (if $r == "" then null else {reason: $r, label: (if $l == "" then null else $l end)} end)}' \
    >"$out/status.json"
  status_written=true
}

# halt REASON [LABEL]: the screening stops here, INCOMPLETE.
halt() {
  halted_reason=$1
  halted_label=${2:-}
  write_status
  err "screening halted: $1${2:+ at $2}"
  exit 1
}

verify_freeze() {
  verify_freeze_manifest "$repo" "$out/freeze-manifest.json" "$out"
}

# remaining ACCOUNT: the account's cap minus what it has spent, as a plain decimal.
remaining() {
  python3 -I -B - "$out/ledger.json" "$1" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
account = sys.argv[2]
spent = sum(float(e["credits"]) for e in document["entries"] if e["account"] == account)
left = round(float(document["caps"][account]) - spent, 10)
print(("%.10f" % max(left, 0)).rstrip("0").rstrip("."))
PY
}

# call KEY LABEL: admission, freeze check and the remaining allowance before a
# call; sets call_opts to the options every call of KEY shares.
before_call() {
  local key=$1 label=$2 rc=0 left
  verify_freeze || halt FREEZE_MISMATCH "$label"
  ledger_admit "$out/ledger.json" "candidate_$key" "$admission" || rc=$?
  if (( rc == 1 )); then
    stopped[$key]=BUDGET_STOP
    halt BUDGET_STOP "$label"
  fi
  (( rc == 0 )) || halt LEDGER_UNREADABLE "$label"
  left=$(remaining "candidate_$key")
  [[ "$left" != 0 ]] || { stopped[$key]=BUDGET_STOP; halt BUDGET_STOP "$label"; }
  call_opts=(--sandbox-parent "$work" --config "$work/config-$key.json" --credentials "$creds"
    --opencode-dir "$ocdir" --ledger "$out/ledger.json" --account "candidate_$key" --stop-credits "$left")
  if [[ "${kinds[$key]}" == model ]]; then
    call_opts+=(--agent "$agent_name" --expect "${expects[$key]}")
  else
    call_opts+=(--agent "${agents[$key]}" --expect "${expects[$key]}" --profile-id "$profile_id"
      --profile-digest "$profile_digest")
  fi
}

# exposure_check KEY LABEL DISPATCH_JSON PATH...: the credential backstop. Any
# string of 12 or more characters from the credentials file or the provider
# fragment found under PATH... is redacted in place, and the screening halts.
exposure_check() {
  local key=$1 label=$2 json=$3 rc=0
  shift 3
  python3 -I -B "$adapter/v2config.py" redact "$creds" "$providers" -- "$@" >&2 || rc=$?
  (( rc != 0 )) || return 0
  (( rc == 1 )) || halt CREDENTIAL_SCAN_FAILED "$label"
  if [[ -f "$json" ]]; then
    jq '.classification_before_redaction = .classification | .classification = "CREDENTIAL_EXPOSED"' \
      "$json" >"$work/exposed.json" && mv -- "$work/exposed.json" "$json"
  fi
  stopped[$key]=CREDENTIAL_EXPOSED
  halt CREDENTIAL_EXPOSED "$label"
}

# after_call KEY LABEL DIR: Ruling 5 on a finished call's dispatch.json.
after_call() {
  local key=$1 label=$2 dir=$3 classification known complete
  [[ -f "$dir/dispatch.json" ]] || halt DISPATCH_REFUSED "$label"
  classification=$(jq -r .classification "$dir/dispatch.json")
  known=$(jq -r .cost_known "$dir/dispatch.json")
  complete=$(jq -r 'if has("cost_complete") then .cost_complete else true end' "$dir/dispatch.json")
  if [[ "$classification" == BUDGET_STOP ]]; then
    stopped[$key]=BUDGET_STOP
    halt BUDGET_STOP "$label"
  fi
  if [[ "$known" != true ]]; then
    stopped[$key]=UNKNOWN_COST
    halt UNKNOWN_COST "$label"
  fi
  # A call cut off mid-step: its last step's cost was never reported, so the
  # ledger holds a lower bound.
  if [[ "$complete" != true ]]; then
    stopped[$key]=INCOMPLETE_COST
    halt INCOMPLETE_COST "$label"
  fi
  if [[ "$classification" == CAPABILITY_REGRESSION ]]; then
    stopped[$key]=CAPABILITY_REGRESSION
  fi
}

# prepare_workspace INDEX DIR: the workload's base plus its overlays, no oracle.
prepare_workspace() {
  local w=$1 ws=$2 base o
  base=$(resolve_path "$(jq -r ".workloads[$w].base" "$role_file")")
  [[ -d "$base" ]] || halt "WORKSPACE_MISSING" ""
  mkdir -p -- "$ws"
  cp -a -- "$base/." "$ws/"
  find "$ws" \( -name ground-truth.json -o -name oracle.json \) -type f -delete
  while IFS= read -r o; do
    [[ -n "$o" ]] || continue
    o=$(resolve_path "$o")
    cp -- "$o" "$ws/$(basename -- "$o")"
  done < <(jq -r ".workloads[$w].overlay[]" "$role_file")
}

dispatch() {
  local providers='' profile=''
  creds=''
  while (( $# )); do
    (( $# >= 2 )) || die 2 "option $1 needs a value"
    case "$1" in
      --out) out=$2 ;;
      --providers) providers=$2 ;;
      --credentials) creds=$2 ;;
      --profile) profile=$2 ;;
      *) die 2 "unknown option $1" ;;
    esac
    shift 2
  done
  clear_stale_work
  [[ -n "$out" ]] || die 2 "--out is required"
  need_file --providers "$providers"
  need_file --credentials "$creds"
  [[ -z "$profile" ]] || need_file --profile "$profile"
  [[ -f "$out/protocol.json" && -f "$out/freeze-manifest.json" ]] || die 2 "not a prepared record: $out"
  out=$(cd "$out" && pwd -P)
  local protocol="$out/protocol.json"

  verify_freeze || die 1 "the record does not match its freeze manifest"
  [[ -f "$out/approval.json" ]] || die 3 "no approval.json in $out"
  python3 -I -B - "$out/approval.json" "$protocol" "$(sha256 "$out/freeze-manifest.json")" <<'PY' \
    || die 3 "approval.json is not exactly the object prepare printed"
import json
import sys

try:
    approval = json.load(open(sys.argv[1], encoding="utf-8"))
    protocol = json.load(open(sys.argv[2], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
expected = {
    "experiment_id": protocol["experiment_id"],
    "status": "APPROVED_FOR_DISPATCH",
    "approved_ceiling_credits": protocol["budget"]["ceiling_credits"],
    "freeze_manifest_sha256": sys.argv[3],
}
sys.exit(0 if protocol["status_at_freeze"] == "AWAITING_APPROVAL" and approval == expected else 1)
PY
  [[ "$(sha256 "$providers")" == "$(jq -r .providers_sha256 "$protocol")" ]] \
    || die 3 "--providers is not the file the protocol froze"
  [[ "$(sha256 "$creds")" == "$(jq -r .credentials_sha256 "$protocol")" ]] \
    || die 3 "--credentials is not the file the protocol froze"
  profile_digest=$(jq -r '.profile_digest // ""' "$protocol")
  profile_id=$(jq -r '.profile_id // ""' "$protocol")
  if [[ -n "$profile_digest" || -n "$profile" ]]; then
    [[ -n "$profile" && "$(sha256 "$profile")" == "$profile_digest" ]] \
      || die 3 "--profile is not the profile the protocol froze"
  fi
  [[ ! -e "$out/runs" && ! -e "$out/capability" ]] || die 2 "runs/ or capability/ already exist in $out"

  work="$out/.work"
  rm -rf -- "$work"
  mkdir -- "$work"
  export TMPDIR="$work"
  load_role "$repo/$(jq -r .role_definition "$protocol")"
  # A repo-relative opencode_dir is used in place; an absolute one through the
  # record's frozen copy.
  ocdir=$(jq -r .opencode_dir "$protocol")
  if [[ "$ocdir" == /* ]]; then ocdir="$out/opencode-dir"; else ocdir="$repo/$ocdir"; fi

  # The runtime, measured as prepare measured it: GET /api/info of one
  # sandboxed server with prepare's config, and no model call.
  local base=- sb version frozen_version
  [[ -z "$profile" ]] || base=$profile
  python3 -I -B "$adapter/v2config.py" build-config "$base" "$providers" - "$work/catalog-config.json" \
    || die 1 "cannot build the runtime check's config"
  sb=$(v2_sandbox_create "$work") || die 1 "cannot create the runtime check's sandbox"
  catalog_sb=$sb
  v2_sandbox_populate "$sb" "$work/catalog-config.json" "$creds" "$ocdir" \
    || die 1 "cannot populate the runtime check's sandbox"
  v2_sandbox_serve "$sb" || die 1 "the runtime check's server did not start"
  version=$(<"$sb/version")
  v2_sandbox_destroy "$sb" || true
  catalog_sb=''
  rm -f -- "$work/catalog-config.json"
  frozen_version=$(jq -r .runtime_version "$protocol")
  [[ "$version" == "$frozen_version" ]] \
    || die 3 "the OpenCode runtime is $version; the protocol froze $frozen_version"

  phase=dispatch
  admission=$(jq -r .budget.admission_per_call "$protocol")
  local runs timeout extract capture
  runs=$(jq -r .runs "$protocol")
  timeout=$(jq -r .timeout_seconds "$protocol")
  extract=$(jq -r '.extract // "none"' "$role_file")
  capture=$(jq -r '.capture_patch // false' "$role_file")

  # Configs: a model candidate gets the role's agent row with its model; an
  # agent candidate the profile alone. Both get the provider fragment.
  local -a keys=()
  declare -gA kinds=() agents=() expects=()
  local key spec n
  mapfile -t keys < <(jq -r '.candidates[].key' "$protocol")
  for key in "${keys[@]}"; do
    spec=$(jq -r --arg k "$key" '.candidates[] | select(.key == $k) | .spec' "$protocol")
    expects[$key]=$(jq -r --arg k "$key" '.candidates[] | select(.key == $k) | .expect' "$protocol")
    if [[ "$spec" == agent:* ]]; then
      kinds[$key]=agent
      agents[$key]=${spec#agent:}
      python3 -I -B "$adapter/v2config.py" build-config "$profile" "$providers" - "$work/config-$key.json" \
        || die 1 "cannot build the config of $key"
    else
      kinds[$key]=model
      python3 -I -B - "$adapter" "$role_file" "$repo" "${spec#model:}" "$work/row-$key.json" <<'PY' \
        || die 1 "cannot build the agent row of $key"
import json
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config  # noqa: E402

role = json.load(open(sys.argv[2], encoding="utf-8"))
repo, target, out = sys.argv[3:]
provider, rest = target.split("/", 1)
model, variant = rest.rsplit("#", 1)
agent = role["agent"]
row = {"mode": agent["mode"], "model": {"providerID": provider, "model": model, "variant": variant}}
permissions = []
markdown = agent.get("markdown")
if markdown:
    path = markdown if os.path.isabs(markdown) else os.path.join(repo, markdown)
    permissions += v2config.md_frontmatter(path).get("permissions", [])
    text = open(path, encoding="utf-8").read()
    body = re.match(r"^---[ \t]*\n.*?\n---[ \t]*(?:\n|$)(.*)$", text, re.S)
    if not body:
        sys.exit("no frontmatter in %s" % path)
    row["system"] = body.group(1).lstrip("\n")
permissions += agent.get("permissions") or []
permissions += agent.get("permissions_append") or []
row["permissions"] = permissions
with open(out, "w", encoding="utf-8") as handle:
    json.dump({"name": agent["name"], "row": row}, handle, indent=2)
PY
      python3 -I -B "$adapter/v2config.py" build-config - "$providers" "$work/row-$key.json" "$work/config-$key.json" \
        || die 1 "cannot build the config of $key"
    fi
  done
  n=${#keys[@]}
  ledger_init "$out/ledger.json" "$(jq -c '.budget.per_candidate_cap as $c | [.candidates[] | {(.account): $c}] | add' "$protocol")"
  mkdir -p "$out/capability" "$out/runs"

  # Capability: a failed probe stops that candidate.
  local rc
  for key in "${keys[@]}"; do
    before_call "$key" "capability-$key"
    rc=0
    # shellcheck disable=SC2016 # expanded by the child shell
    run_child "${BASH:-bash}" -c 'source "$1"; shift; v2_capability_probe "$@"' _ \
      "$adapter/capability-probe.sh" "$out/capability/$key" "$key" "${call_opts[@]}" || rc=$?
    exposure_check "$key" "capability-$key" "$out/capability/$key/dispatch/dispatch.json" "$out/capability/$key"
    (( rc != 2 )) || halt DISPATCH_REFUSED "capability-$key"
    after_call "$key" "capability-$key" "$out/capability/$key/dispatch"
    if (( rc != 0 )); then
      if [[ "$(jq -r .classification "$out/capability/$key/probe.json")" == INVALID_ENVIRONMENT ]]; then
        halt INVALID_ENVIRONMENT "capability-$key"
      fi
      stopped[$key]=STOPPED_CAPABILITY
      err "candidate $key stopped: capability probe $(jq -r .classification "$out/capability/$key/probe.json")"
    fi
  done
  local live=0
  for key in "${keys[@]}"; do
    [[ -n "${stopped[$key]:-}" ]] || live=$((live + 1))
  done
  (( live > 0 )) || halt NO_LIVE_CANDIDATE

  local rep w wid label seq=0 ws wout prompt
  local -a order
  local workloads
  workloads=$(jq '.workloads | length' "$role_file")
  for ((rep = 1; rep <= runs; rep++)); do
    for ((w = 0; w < workloads; w++)); do
      wid=$(jq -r ".workloads[$w].id" "$role_file")
      prompt=$(resolve_path "$(jq -r ".workloads[$w].prompt" "$role_file")")
      if (( (rep + w) % 2 == 1 )); then
        order=("${keys[@]}")
      else
        order=()
        for ((n = ${#keys[@]} - 1; n >= 0; n--)); do order+=("${keys[$n]}"); done
      fi
      for key in "${order[@]}"; do
        [[ -z "${stopped[$key]:-}" ]] || continue
        seq=$((seq + 1))
        label=$(printf '%02d-%s-r%s-%s' "$seq" "$wid" "$rep" "$key")
        before_call "$key" "$label"
        ws="$work/ws-$label"
        wout="$work/out-$label"
        prepare_workspace "$w" "$ws"
        mkdir -p "$out/runs/$label"
        rc=0
        run_child "${BASH:-bash}" "$adapter/dispatch-fixture.sh" __dispatch "${call_opts[@]}" \
          --outdir "$out/runs/$label/dispatch" --label "$label" --prompt-file "$prompt" \
          --workspace "$ws" --workspace-out "$wout" --timeout "$timeout" || rc=$?
        (( rc != 2 )) || halt DISPATCH_REFUSED "$label"
        if [[ "$extract" == json ]]; then
          if [[ "$(jq -r .classification "$out/runs/$label/dispatch/dispatch.json" 2>/dev/null)" != OK ]]; then
            printf 'not extracted: the call is not OK\n' >"$out/runs/$label/extract-error.txt"
          elif ! dispatch_extract_json "$out/runs/$label/dispatch" >"$out/runs/$label/reported.json" \
              2>"$out/runs/$label/extract-error.txt"; then
            rm -f "$out/runs/$label/reported.json"
          else
            rm -f "$out/runs/$label/extract-error.txt"
          fi
        fi
        if [[ "$capture" == true && -d "$wout" ]]; then
          bash "$adapter/capture-tree-patch.sh" "$ws" "$wout" "$out/runs/$label/work-product.patch" \
            || err "cannot capture the work product of $label"
        fi
        exposure_check "$key" "$label" "$out/runs/$label/dispatch/dispatch.json" "$out/runs/$label" "$wout"
        rm -rf -- "$ws" "$wout"
        after_call "$key" "$label" "$out/runs/$label/dispatch"
      done
    done
  done
  write_status
}

# ---------------------------------------------------------------- score

# run_argv STAGE KEY REP: the role's STAGE argv, expanded; stdout per the role.
run_argv() {
  local stage=$1 key=${2:-} rep=${3:-} a dest rc=0
  local -a argv=()
  while IFS= read -r a; do
    argv+=("$(expand "$a" "$key" "$rep")")
  done < <(jq -r ".${stage}.argv[]" "$role_file")
  dest=$(jq -r ".${stage}.stdout // \"\"" "$role_file")
  : >"$work/stderr"
  if [[ -n "$dest" ]]; then
    dest="$out/$(expand "$dest" "$key" "$rep")"
    mkdir -p -- "$(dirname -- "$dest")"
    (cd "$repo" && "${argv[@]}") </dev/null >"$dest" 2>"$work/stderr" || rc=$?
    (( rc == 0 )) || rm -f -- "$dest"
  else
    (cd "$repo" && "${argv[@]}") </dev/null >&2 2>"$work/stderr" || rc=$?
  fi
  return "$rc"
}

score() {
  while (( $# )); do
    (( $# >= 2 )) || die 2 "option $1 needs a value"
    case "$1" in
      --out) out=$2 ;;
      *) die 2 "unknown option $1" ;;
    esac
    shift 2
  done
  clear_stale_work
  [[ -n "$out" && -f "$out/protocol.json" && -f "$out/status.json" ]] || die 2 "not a dispatched record: $out"
  out=$(cd "$out" && pwd -P)
  verify_freeze || die 1 "the record does not match its freeze manifest; nothing scored"
  [[ -f "$out/approval.json" \
     && "$(jq -r '.freeze_manifest_sha256 // ""' "$out/approval.json" 2>/dev/null)" == "$(sha256 "$out/freeze-manifest.json")" ]] \
    || die 1 "freeze-manifest.json is not the manifest approval.json approved; nothing scored"
  work="$out/.work"
  rm -rf -- "$work"
  mkdir -- "$work"
  export TMPDIR="$work"
  load_role "$repo/$(jq -r .role_definition "$out/protocol.json")"
  local runs key rep rc per notes='[]'
  local -a keys=()
  runs=$(jq -r .runs "$out/protocol.json")
  mapfile -t keys < <(jq -r '.candidates[].key' "$out/protocol.json")
  note() {
    notes=$(jq -c --arg k "$1" --arg r "$2" --arg s "$3" --arg m "$4" \
      '. + [{key: $k, rep: $r, stage: $s, message: $m}]' <<<"$notes")
  }
  if [[ "$(jq -r '.normalise.per // ""' "$role_file")" == candidate-run ]]; then
    for key in "${keys[@]}"; do
      for ((rep = 1; rep <= runs; rep++)); do
        rc=0
        run_argv normalise "$key" "$rep" || rc=$?
        if (( rc == 3 )) && grep -q 'clean control missing' "$work/stderr"; then
          note "$key" "$rep" NOT_SCORABLE "clean control missing"
        elif (( rc != 0 )); then
          note "$key" "$rep" NORMALISE_FAILED "exit $rc: $(head -c 300 "$work/stderr")"
        fi
      done
    done
  fi
  per=$(jq -r '.score.per // ""' "$role_file")
  if [[ "$per" == candidate-run ]]; then
    for key in "${keys[@]}"; do
      for ((rep = 1; rep <= runs; rep++)); do
        jq -e --arg k "$key" --arg r "$rep" 'any(.[]; .key == $k and .rep == $r)' <<<"$notes" >/dev/null && continue
        rc=0
        run_argv score "$key" "$rep" || rc=$?
        (( rc == 0 )) || note "$key" "$rep" SCORE_FAILED "exit $rc: $(head -c 300 "$work/stderr")"
      done
    done
  elif [[ "$per" == record ]]; then
    rc=0
    run_argv score || rc=$?
    (( rc == 0 )) || note '' '' SCORE_FAILED "exit $rc: $(head -c 300 "$work/stderr")"
  fi
  printf '%s' "$notes" >"$work/notes.json"

  python3 -I -B - "$out" "$work/notes.json" "$per" "$(jq -r '.score.file // ""' "$role_file")" <<'PY'
import glob
import json
import os
import sys

out, notes_path, per, record_file = sys.argv[1:]


def load(name, default=None):
    try:
        return json.load(open(os.path.join(out, name), encoding="utf-8"))
    except (OSError, ValueError):
        return default


protocol = load("protocol.json")
status = load("status.json", {})
ledger = load("ledger.json", {"caps": {}, "entries": []})
notes = json.load(open(notes_path, encoding="utf-8"))
stopped = status.get("stopped") or {}
lines = ["# Screening result: %s" % protocol["experiment_id"], ""]
lines += ["## Protocol", "",
          "- Role: %s (%s)" % (protocol["role"], protocol["role_definition"]),
          "- Runs per candidate and workload: %s" % protocol["runs"],
          "- Runtime: %s; toolkit commit %s" % (protocol["runtime_version"], protocol["toolkit_commit"]),
          "- Profile: %s (%s)" % (protocol.get("profile_id") or "none", protocol.get("profile_digest") or "none"),
          "- Ceiling: %s credits" % protocol["budget"]["ceiling_credits"],
          "- Dispatch state: %s%s" % (status.get("state"),
                                      "; halted: %s at %s" % (status["halted"]["reason"], status["halted"]["label"])
                                      if status.get("halted") else ""),
          ""]
lines += ["## Candidates", "", "| Key | Spec | Expected use | Stopped |", "|---|---|---|---|"]
for c in protocol["candidates"]:
    lines.append("| %s | `%s` | `%s` | %s |" % (c["key"], c["spec"], c["expect"], stopped.get(c["key"], "no")))
lines += ["", "## Spend", "", "| Account | Cap | Spent |", "|---|---|---|"]
for account, cap in ledger.get("caps", {}).items():
    spent = sum(e["credits"] for e in ledger.get("entries", []) if e["account"] == account)
    lines.append("| %s | %s | %s |" % (account, cap, round(spent, 10)))
total = sum(e["credits"] for e in ledger.get("entries", []))
partial = False
for path in glob.glob(os.path.join(out, "capability", "*", "dispatch", "dispatch.json")) \
        + glob.glob(os.path.join(out, "runs", "*", "dispatch", "dispatch.json")):
    try:
        call = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if call.get("cost_known") is False or call.get("cost_complete", True) is False:
        partial = True
if partial:
    lines += ["", "Total spent: %s credits (lower bound): a call's cost is unknown or was cut off "
              "mid-step." % round(total, 10), ""]
else:
    lines += ["", "Total spent: %s credits." % round(total, 10), ""]
lines += ["## Capability", "", "| Key | Probe |", "|---|---|"]
for c in protocol["candidates"]:
    probe = load(os.path.join("capability", c["key"], "probe.json"), {})
    lines.append("| %s | %s |" % (c["key"], probe.get("classification", "not probed")))
lines += ["", "## Scores", "", "| Key | Rep | Score | Summary |", "|---|---|---|---|"]
for c in protocol["candidates"]:
    for rep in range(1, protocol["runs"] + 1):
        name = "scores/%s-r%s.json" % (c["key"], rep)
        score = load(name)
        flagged = [n for n in notes if n["key"] == c["key"] and n["rep"] == str(rep)]
        if flagged:
            summary = "; ".join("%s: %s" % (n["stage"], n["message"].replace("|", "/").replace("\n", " "))
                                for n in flagged)
            lines.append("| %s | %s | %s | %s |" % (c["key"], rep, flagged[0]["stage"], summary))
        elif isinstance(score, dict):
            summary = ", ".join("%s=%s" % (k, v) for k, v in score.items()
                                if isinstance(v, (str, int, float, bool)))
            findings = load("findings-%s-r%s.json" % (c["key"], rep))
            if isinstance(findings, dict) and isinstance(findings.get("missing_runs"), list):
                summary += ", missing_runs=%d" % len(findings["missing_runs"])
            lines.append("| %s | %s | `%s` | %s |" % (c["key"], rep, name, summary))
        elif per == "record" and record_file:
            if os.path.isfile(os.path.join(out, record_file)):
                lines.append("| %s | %s | `%s` | record-level score, every candidate's runs in one file |"
                             % (c["key"], rep, record_file))
            else:
                lines.append("| %s | %s | none | record-level `%s` was not written |"
                             % (c["key"], rep, record_file))
        else:
            lines.append("| %s | %s | none | no per-run score file |" % (c["key"], rep))
for n in notes:
    if not n["key"]:
        lines.append("")
        lines.append("Record scorer %s: %s" % (n["stage"], n["message"].replace("\n", " ")))
diagnostic = sorted(glob.glob(os.path.join(out, "post-run-diagnostic", "*")))
if diagnostic:
    lines += ["", "Record-level diagnostic: `post-run-diagnostic/`."]
lines += ["", "## Adjudication", "", "Operator: not yet adjudicated", ""]
with open(os.path.join(out, "result.md"), "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines))
PY
  if jq -e 'any(.[]; .stage != "NOT_SCORABLE")' "$work/notes.json" >/dev/null; then
    jq -r '.[] | select(.stage != "NOT_SCORABLE") | "run-screening: \(.stage) \(.key) \(.rep): \(.message)"' \
      "$work/notes.json" >&2
    exit 1
  fi
}

case "${1:-}" in
  prepare) shift; prepare "$@" ;;
  dispatch) shift; dispatch "$@" ;;
  score) shift; score "$@" ;;
  *) die 2 "usage: run-screening.sh prepare|dispatch|score [OPTION...]; see the header" ;;
esac
