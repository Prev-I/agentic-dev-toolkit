#!/usr/bin/env bash
# One-time conversion of an OpenCode 1.x config file to the 2.x shape. Source
# this file, or run it directly with the same arguments.
#
#   convert_v1_config --input FILE --output FILE [--in-place] \
#     --backup-root DIR [--opencode-bin BIN]
#
# Exit 0 on success; 1 if the conversion, the layer check or the reload check
# fails, or the result is not V2; 2 on usage, or if the input is not V1.
#
# Upstream (https://opencode.ai/v2/docs/migrate-v1, read 2026-11-21) offers no
# non-interactive converter: it suggests asking OpenCode to migrate the file,
# and says 2.x normalizes V1 fields in memory without rewriting the source.
# This tool takes that in-memory translation as the result instead of
# reimplementing the table:
#
#   1. a sandboxed `opencode serve` whose only config is the input (comments
#      stripped) is polled on GET /api/config until the `document` layer for
#      the sandbox's config file appears; its `info` is the translation;
#   2. every `agents.<role>.request.body.temperature` is removed (2.x does not
#      send it), and `request` with it when left empty;
#   3. the result must hold no V1 key;
#   4. a second sandboxed server loads the result, and its `document` `info`
#      must equal it as parsed JSON; only then is it staged beside the output
#      (with a `//` provenance header when the output ends in `.jsonc`);
#   5. the input (and an output it replaces) is backed up to
#      BACKUP_ROOT/convert-<stamp>/ with a SHA256SUMS, and the staged file is
#      moved onto the output atomically, keeping the replaced file's mode.
#
# `dropped: <key path>` is printed for each removed temperature; each V1
# `provider.<p>.blacklist` and `provider.<p>.whitelist` (2.3.0 drops both);
# `server`; any other V1 top-level key whose content has no counterpart in
# the result; each entry of `agent`, `mode`, `provider`, `command` or `mcp`
# missing from its target map (`agents`, `providers`, `commands`,
# `mcp.servers`); and each provider listed in `disabled_providers` (or
# `enabled_providers`) without a `provider.use` policy naming it, as the
# resource or within a list-valued resource, with effect deny (or allow);
# a non-empty `enabled_providers` also needs a `provider.use` deny on `*`
# (`dropped: enabled_providers (deny *)` otherwise).
#
# Isolation: HOME and XDG_* alone do not isolate a 2.x server (it also loads
# the account's ~/.opencode and its working directory's config). Each server
# runs under `env -i` with sandbox HOME/XDG_*, a random password and
# OPENCODE_DISABLE_AUTOUPDATE=1, from the sandbox's `work` directory, on a free
# loopback port, in its own process group. The layer list is refused unless
# every layer is inside the sandbox, or is the account's ~/.opencode holding
# none of opencode.json, opencode.jsonc, agents/, agent/, command/, plugins/.
# Servers are stopped and the sandbox removed on every exit, signal included.
# V2_CONFIG_POLL_TIMEOUT (default 30) bounds each poll, in seconds.
set -Eeuo pipefail
IFS=$'\n\t'
v2_convert_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-run.sh disable=SC1091 # path built from the script's own directory at run time
source "$v2_convert_root/v2-run.sh"

_cv_usage() {
  printf 'usage: convert_v1_config --input FILE --output FILE [--in-place] --backup-root DIR [--opencode-bin BIN]\n' >&2
  printf '       with --in-place, --output may be omitted (it is the input)\n' >&2
}

_cv_err() {
  printf 'convert_v1_config: %s\n' "$*" >&2
}

# Absolute path of a file whose parent directory exists.
_cv_abspath() {
  local dir
  dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s' "$dir" "$(basename "$1")"
}

# Python helpers. Subcommands:
#   document API_CONFIG CFG SANDBOX OUT   3: no document layer yet; 1: refused
#   finalize V1 INFO OUT                  dropped: lines; 1 if a V1 key remains
#   strict SRC OUT                        SRC (comments stripped) as strict JSON
#   same A B                              0 when equal as parsed JSON
#   version INFO_JSON                     the version field
#   password                              32 random [A-Za-z0-9]
#   port                                  a free loopback port
_cv_py() {
  python3 -B - "$v2_convert_root" "$@" <<'PY'
import json
import os
import pwd
import secrets
import socket
import string
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config  # noqa: E402

cmd, args = sys.argv[2], sys.argv[3:]


def inside(path, root):
    real = os.path.realpath(path)
    return real == root or real.startswith(root + os.sep)


if cmd == "document":
    api, cfg, sandbox, out = args
    sandbox = os.path.realpath(sandbox)
    cfg = os.path.realpath(cfg)
    try:
        with open(api) as f:
            layers = json.load(f)
    except (OSError, ValueError):
        sys.exit(3)
    if not isinstance(layers, list):
        sys.exit(3)
    doc = [l for l in layers if isinstance(l, dict) and l.get("type") == "document"
           and isinstance(l.get("path"), str) and os.path.realpath(l["path"]) == cfg]
    if not doc or not isinstance(doc[0].get("info"), dict):
        sys.exit(3)
    account = os.path.realpath(os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".opencode"))
    forbidden = ("opencode.json", "opencode.jsonc", "agents", "agent", "command", "plugins")
    bad = []
    for layer in layers:
        path = layer.get("path") if isinstance(layer, dict) else None
        if not isinstance(path, str) or not path:
            bad.append("a layer with no path: %s" % json.dumps(layer)[:200])
        elif inside(path, sandbox):
            continue
        elif os.path.realpath(path) == account:
            held = [n for n in forbidden if os.path.lexists(os.path.join(account, n))]
            if held:
                bad.append("%s holds %s" % (path, ", ".join(held)))
        else:
            bad.append("%s (%s) is outside the sandbox" % (path, layer.get("type")))
    if bad:
        sys.stderr.write("convert_v1_config: refusing the server's config layers; it did not load"
                         " only the sandbox:\n" + "".join("  - %s\n" % b for b in bad))
        sys.exit(1)
    with open(out, "w") as f:
        json.dump(doc[0]["info"], f)
    sys.exit(0)

if cmd == "finalize":
    v1_path, info_path, out = args
    v1 = v2config.load(v1_path)
    with open(info_path) as f:
        result = json.load(f)
    dropped = []
    agents = result.get("agents")
    if isinstance(agents, dict):
        for role, row in agents.items():
            request = row.get("request") if isinstance(row, dict) else None
            body = request.get("body") if isinstance(request, dict) else None
            if isinstance(body, dict) and "temperature" in body:
                del body["temperature"]
                dropped.append("agents.%s.request.body.temperature" % role)
                if not body:
                    del request["body"]
                if not request:
                    del row["request"]
    providers = v1.get("provider")
    if isinstance(providers, dict):
        out_providers = result.get("providers") or {}
        for name, entry in providers.items():
            kept = out_providers.get(name) if isinstance(out_providers, dict) else None
            kept = kept if isinstance(kept, dict) else {}
            # 2.3.0 drops both model filters (measured: a filter-only built-in
            # provider becomes `{}`); a lost whitelist widens what may be used.
            for filt in ("blacklist", "whitelist"):
                if isinstance(entry, dict) and filt in entry and filt not in kept:
                    dropped.append("provider.%s.%s" % (name, filt))
    # Where each V1 top-level key's content lands in V2.
    renamed = {"agent": "agents", "mode": "agents", "permission": "permissions",
               "provider": "providers", "disabled_providers": "policies",
               "enabled_providers": "policies", "plugin": "plugins",
               "autoupdate": "update", "command": "commands", "snapshot": "snapshots"}
    for key in v1:
        if renamed.get(key, key) not in result:
            dropped.append(key)
    # Second level: every entry of a map-valued V1 key must reach its target
    # map. Checked per source, so a key sharing a target cannot mask another.
    entry_targets = {"agent": ("agents",), "mode": ("agents",),
                     "provider": ("providers",), "command": ("commands",),
                     "mcp": ("mcp", "servers")}
    for key, target_path in entry_targets.items():
        source = v1.get(key)
        if not isinstance(source, dict) or not source:
            continue
        target = result
        for part in target_path:
            target = target.get(part) if isinstance(target, dict) else None
        if not isinstance(target, dict):
            target = {}
        for name in source:
            if name not in target:
                dropped.append("%s.%s" % (key, name))
    # disabled_providers / enabled_providers become `provider.use` policies
    # (measured on 2.3.0: a deny per disabled provider; for enabled ones a
    # `deny *` then an allow each). Each listed provider needs a policy with
    # its own name as resource and the matching effect.
    wanted = {"disabled_providers": "deny", "enabled_providers": "allow"}
    if any(isinstance(v1.get(k), list) for k in wanted):
        granted = set()
        policies = result.get("policies")
        for policy in policies if isinstance(policies, list) else []:
            if not isinstance(policy, dict) or policy.get("action") != "provider.use":
                continue
            resource = policy.get("resource")
            names = resource if isinstance(resource, list) else [resource]
            effect = policy.get("effect")
            if not isinstance(effect, str):
                continue
            for name in names:
                if isinstance(name, str):
                    granted.add((name, effect))
        for key, effect in wanted.items():
            listed = v1.get(key)
            for name in listed if isinstance(listed, list) else []:
                if not isinstance(name, str) or (name, effect) not in granted:
                    dropped.append("%s.%s" % (key, name))
        # The allows only matter behind the deny-all that makes the list
        # restrictive (2.3.0 emits `provider.use * deny` first).
        enabled = v1.get("enabled_providers")
        if isinstance(enabled, list) and enabled and ("*", "deny") not in granted:
            dropped.append("enabled_providers (deny *)")
    left = [k for k in v2config.V1_KEYS if k in result]
    mcp = result.get("mcp")
    if isinstance(mcp, dict) and "servers" not in mcp:
        left.append("mcp (without servers)")
    if left:
        sys.stderr.write("convert_v1_config: the translation still holds V1 keys: %s\n"
                         % ", ".join(left))
        sys.exit(1)
    with open(out, "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    for path in dropped:
        print("dropped: %s" % path)
    sys.exit(0)

if cmd == "strict":
    src, out = args
    with open(out, "w") as f:
        json.dump(v2config.load(src), f, indent=2)
        f.write("\n")
    sys.exit(0)

if cmd == "same":
    a, b = (v2config.load(p) for p in args)
    if a == b:
        sys.exit(0)
    keys = sorted(set(a) | set(b)) if isinstance(a, dict) and isinstance(b, dict) else []
    diff = [k for k in keys if a.get(k) != b.get(k)]
    sys.stderr.write("convert_v1_config: differing top-level keys: %s\n" % ", ".join(diff))
    sys.exit(1)

if cmd == "version":
    try:
        print(json.loads(args[0]).get("version") or "unknown")
    except (ValueError, AttributeError):
        print("unknown")
    sys.exit(0)

if cmd == "password":
    alphabet = string.ascii_letters + string.digits
    print("".join(secrets.choice(alphabet) for _ in range(32)))
    sys.exit(0)

if cmd == "port":
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
    s.close()
    sys.exit(0)

sys.exit("unknown helper command: %s" % cmd)
PY
}

# _cv_serve SANDBOX BIN CONFIG_JSON -> loads CONFIG_JSON (strict) in a fresh
# sandboxed server; writes SANDBOX/info.json (the document layer's info) and
# SANDBOX/version. The server is stopped before returning.
_cv_serve() {
  local sb=$1 bin=$2 config=$3 port pid url rc deadline
  local timeout=${V2_CONFIG_POLL_TIMEOUT:-30}
  if ! mkdir -p "$sb/home" "$sb/config/opencode" "$sb/data" "$sb/state" "$sb/cache" "$sb/work" \
     || ! cp "$config" "$sb/config/opencode/opencode.json"; then
    _cv_err "cannot build the sandbox in $sb"
    return 1
  fi
  port=$(_cv_py port) && [[ -n "$port" ]] || { _cv_err "cannot pick a free loopback port"; return 1; }
  (
    cd "$sb/work"
    exec setsid env -i PATH=/usr/bin:/bin HOME="$sb/home" \
      XDG_CONFIG_HOME="$sb/config" XDG_DATA_HOME="$sb/data" \
      XDG_STATE_HOME="$sb/state" XDG_CACHE_HOME="$sb/cache" \
      OPENCODE_PASSWORD="$V2_PASSWORD" OPENCODE_SERVER_PASSWORD="$V2_PASSWORD" \
      OPENCODE_DISABLE_AUTOUPDATE=1 \
      "$bin" serve --hostname 127.0.0.1 --port "$port"
  ) </dev/null >"$sb/server.log" 2>&1 &
  pid=$!
  _V2_PIDS+=("$pid")
  url="http://127.0.0.1:$port"
  deadline=$(( SECONDS + timeout ))
  while :; do
    if ! kill -0 "$pid" 2>/dev/null; then
      _cv_err "the sandboxed server exited early; its log:"
      tail -n 20 "$sb/server.log" >&2 || true
      return 1
    fi
    rc=0
    v2_api_get "$url" /api/config >/dev/null 2>&1 || rc=$?
    if (( rc == 2 )); then
      _cv_err "the generated password or URL cannot be passed to curl"
      return 1
    fi
    if v2_auth_refused; then
      _cv_err "the sandboxed server refused the generated password (HTTP $V2_LAST_STATUS)"
      return 1
    fi
    if (( rc == 0 )); then
      printf '%s' "$V2_LAST_BODY" >"$sb/api-config.json" \
        || { _cv_err "cannot write $sb/api-config.json"; return 1; }
      rc=0
      _cv_py document "$sb/api-config.json" "$sb/config/opencode/opencode.json" "$sb" "$sb/info.json" || rc=$?
      (( rc == 3 )) || break
    fi
    if (( SECONDS >= deadline )); then
      _cv_err "no document layer for the sandbox's config in GET /api/config within ${timeout}s (last status ${V2_LAST_STATUS:-none})"
      return 1
    fi
    sleep 0.25
  done
  (( rc == 0 )) || return 1
  if v2_api_get "$url" /api/info >/dev/null 2>&1; then
    _cv_py version "$V2_LAST_BODY" >"$sb/version" \
      || { _cv_err "cannot read the server version"; return 1; }
  else
    printf 'unknown\n' >"$sb/version" || { _cv_err "cannot write $sb/version"; return 1; }
  fi
  v2_stop_pid "$pid"
}

# Runs inside v2_run_isolated: WORK is removed, and the servers stopped, on exit.
_cv_collect() {
  local work=$1 input=$2 output=$3 backup_root=$4 bin=$5
  local stage staged version stamp backup_dir n sum prev_sum header_path dropped
  V2_PASSWORD=$(_cv_py password) && [[ -n "$V2_PASSWORD" ]] \
    || { _cv_err "cannot generate the sandbox password"; return 1; }

  _cv_py strict "$input" "$work/v1.json" || { _cv_err "cannot read $input as JSON"; return 1; }
  _cv_serve "$work/first" "$bin" "$work/v1.json" || return 1
  version=$(cat "$work/first/version") || { _cv_err "cannot read the server version"; return 1; }
  dropped=$(_cv_py finalize "$input" "$work/first/info.json" "$work/result.json") || return 1

  if [[ "$(python3 -B "$v2_convert_root/v2config.py" shape "$work/result.json")" != v2 ]]; then
    _cv_err "the result is not V2-shaped"
    return 1
  fi
  # Reload check before anything appears beside the output.
  _cv_serve "$work/second" "$bin" "$work/result.json" || return 1
  if ! _cv_py same "$work/second/info.json" "$work/result.json"; then
    _cv_err "reload check failed: a second server does not read the result back unchanged"
    return 1
  fi

  sum=$(sha256sum "$input" | cut -d' ' -f1) && [[ -n "$sum" ]] \
    || { _cv_err "cannot hash $input"; return 1; }
  stage=$(mktemp -d "$(dirname "$output")/.convert-v1.XXXXXX") || { _cv_err "cannot stage beside $output"; return 1; }
  _V2_TMPDIRS+=("$stage")
  staged="$stage/$(basename "$output")"
  if [[ "$output" == *.jsonc ]]; then
    header_path=${input//[$'\r\n']/?}
    if ! {
      printf '// Converted from the OpenCode 1.x config %s\n' "$header_path" &&
      printf '// source sha256: %s\n' "$sum" &&
      printf '// converted at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" &&
      printf '// OpenCode version: %s\n' "$version" &&
      printf "// converted with OpenCode 2's own translation (GET /api/config, document layer info)\n" &&
      cat "$work/result.json"
    } >"$staged"; then
      _cv_err "cannot write $staged"
      return 1
    fi
  elif ! cp "$work/result.json" "$staged"; then
    _cv_err "cannot write $staged"
    return 1
  fi
  if ! _cv_py same "$staged" "$work/result.json"; then
    _cv_err "the staged output does not match the checked result"
    return 1
  fi

  if [[ -e "$output" ]]; then
    chmod --reference="$output" "$staged" || { _cv_err "cannot copy the mode of $output"; return 1; }
  fi
  stamp=$(date +%Y%m%dT%H%M%S%z)
  backup_dir="$backup_root/convert-$stamp"
  n=1
  # mkdir without -p claims the directory atomically; an existing one is skipped.
  until mkdir "$backup_dir" 2>/dev/null; do
    if [[ ! -e "$backup_dir" ]] || (( n > 100 )); then
      _cv_err "cannot create a backup directory under $backup_root"
      return 1
    fi
    backup_dir="$backup_root/convert-$stamp-$n"
    n=$(( n + 1 ))
  done
  if ! cp -p "$input" "$backup_dir/$(basename "$input")" \
     || ! printf '%s  %s\n' "$sum" "$(basename "$input")" >"$backup_dir/SHA256SUMS"; then
    _cv_err "cannot back up $input to $backup_dir; nothing replaced"
    return 1
  fi
  if [[ -e "$output" && "$output" != "$input" ]]; then
    prev_sum=$(sha256sum "$output" | cut -d' ' -f1) && [[ -n "$prev_sum" ]] \
      || { _cv_err "cannot hash $output; nothing replaced"; return 1; }
    if ! mkdir "$backup_dir/previous-output" \
       || ! cp -p "$output" "$backup_dir/previous-output/$(basename "$output")" \
       || ! printf '%s  %s\n' "$prev_sum" "previous-output/$(basename "$output")" >>"$backup_dir/SHA256SUMS"; then
      _cv_err "cannot back up $output to $backup_dir; nothing replaced"
      return 1
    fi
  fi
  if ! (cd "$backup_dir" && sha256sum -c --quiet SHA256SUMS >/dev/null 2>&1); then
    _cv_err "the backup in $backup_dir does not verify; nothing replaced"
    return 1
  fi
  mv -f -T "$staged" "$output" || { _cv_err "cannot move the result onto $output"; return 1; }

  [[ -z "$dropped" ]] || printf '%s\n' "$dropped"
  printf 'converted: %s -> %s (OpenCode %s); backup: %s\n' "$input" "$output" "$version" "$backup_dir"
}

convert_v1_config() {
  local input='' output='' backup_root='' bin='opencode' inplace=0 kind
  while (( $# )); do
    case "$1" in
      --input|--output|--backup-root|--opencode-bin)
        (( $# >= 2 )) || { _cv_err "$1 needs a value"; _cv_usage; return 2; }
        case "$1" in
          --input) input=$2 ;;
          --output) output=$2 ;;
          --backup-root) backup_root=$2 ;;
          --opencode-bin) bin=$2 ;;
        esac
        shift 2 ;;
      --in-place) inplace=1; shift ;;
      *) _cv_err "unknown argument: $1"; _cv_usage; return 2 ;;
    esac
  done
  if [[ -z "$input" || -z "$backup_root" ]] || { (( ! inplace )) && [[ -z "$output" ]]; }; then
    _cv_usage
    return 2
  fi
  [[ -f "$input" ]] || { _cv_err "no such file: $input"; return 2; }
  if (( inplace )) && [[ -L "$input" ]]; then
    _cv_err "refusing to replace a symlink in place: $input"
    return 1
  fi
  input=$(_cv_abspath "$input") || { _cv_err "cannot resolve $input"; return 2; }
  if (( inplace )); then
    if [[ -n "$output" ]]; then
      [[ "$(_cv_abspath "$output" 2>/dev/null || true)" == "$input" ]] \
        || { _cv_err "--in-place writes the input; --output must be omitted or name it"; return 2; }
    fi
    output=$input
  else
    output=$(_cv_abspath "$output") || { _cv_err "the output's directory does not exist: $output"; return 2; }
    if [[ "$output" == "$input" ]]; then
      _cv_err "the output is the input; use --in-place to replace it"
      return 2
    fi
    if [[ -L "$output" ]]; then
      _cv_err "refusing to replace a symlink: $output"
      return 1
    fi
    [[ ! -d "$output" ]] || { _cv_err "the output is a directory: $output"; return 2; }
  fi
  if [[ "$bin" == */* ]]; then
    bin=$(_cv_abspath "$bin") || { _cv_err "no such opencode binary: $bin"; return 2; }
  else
    bin=$(command -v "$bin") || { _cv_err "opencode binary not found on PATH"; return 2; }
  fi
  [[ -x "$bin" && ! -d "$bin" ]] || { _cv_err "not an executable: $bin"; return 2; }

  kind=$(python3 -B "$v2_convert_root/v2config.py" shape "$input" 2>/dev/null || true)
  if [[ "$kind" != v1 ]]; then
    _cv_err "the input is not a V1 config (shape: ${kind:-unreadable}): $input"
    return 2
  fi
  mkdir -p "$backup_root" || { _cv_err "cannot create $backup_root"; return 2; }
  backup_root=$(cd "$backup_root" && pwd -P)

  v2_run_isolated _cv_collect "$input" "$output" "$backup_root" "$bin"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then convert_v1_config "$@"; fi
