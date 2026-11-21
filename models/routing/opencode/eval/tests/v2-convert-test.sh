#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"

# convert_v1_config against a fake `opencode serve` (fixtures-v2/fake-opencode-serve.sh).

adapter="$root/runtime/opencode-v2-adapter"
converter="$adapter/convert-v1-config.sh"
fixtures="$root/tests/fixtures-v2"
bundle=$(cd "$root/.." && pwd)

T=$(mktemp -d)
cleanup() {
  pkill -f "fake-api.py .*$T" 2>/dev/null || true
  rm -rf "${T:?}"
}
trap cleanup EXIT
mkdir -p "$T/tmp" "$T/bin" "$T/bk"
marker="$T/marker"
: >"$marker"
sleep 1

# A wrapper per mode: records which variables the converter passed, then sets
# the fake's own and runs it.
for mode in normal differ leak nodoc lossy real nodenyall; do
  case $mode in
    nodenyall) info="$T/canned-nodenyall.json" ;;
    lossy) info="$T/canned-lossy.json" ;;
    real) info="$fixtures/convert/real-2.3.0-info.json" ;;
    *) info="$T/canned-info.json" ;;
  esac
  cat >"$T/bin/opencode-$mode" <<EOF
#!/usr/bin/env bash
FAKE_SERVE_ENV_NAMES=\$(env | cut -d= -f1 | sort | paste -sd, -)
export FAKE_SERVE_ENV_NAMES
export FAKE_SERVE_INFO='$info' FAKE_SERVE_MODE='$mode' FAKE_SERVE_LOG='$T/serve.log'
exec '$fixtures/fake-opencode-serve.sh' "\$@"
EOF
  chmod +x "$T/bin/opencode-$mode"
done

cat >"$T/in.jsonc" <<'EOF'
{
  // A V1 config, with comments and a trailing comma.
  "$schema": "https://opencode.ai/config.json",
  "model": "gw/m1",
  "autoupdate": false,
  "server": { "port": 4096 },
  "provider": {
    "gw": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://gateway.invalid/v1" },
      "blacklist": ["bad-model"],
      "models": { "m1": { "name": "M1" } }
    }
  },
  "agent": {
    "reviewer": { "mode": "subagent", "model": "gw/m1", "variant": "high",
                  "temperature": 0.1, "prompt": "Review." },
    "build": { "model": "gw/m1" }
  },
  "permission": { "bash": "ask" },
}
EOF

# A token unique to this run, carried in the input config, so a leftover sandbox
# in the global /tmp can be told apart from another process's temp dir.
isolation_token="isolation-token-$(basename "$T")"
sed -i "s/\"prompt\": \"Review[.]/& $isolation_token/" "$T/in.jsonc"
grep -qF "$isolation_token" "$T/in.jsonc" || fail "isolation token not placed in the input"

cat >"$T/canned-info.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": { "providerID": "gw", "model": "m1" },
  "update": "disable",
  "providers": {
    "gw": {
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": { "baseURL": "http://gateway.invalid/v1" },
      "models": { "m1": { "name": "M1" } }
    }
  },
  "agents": {
    "reviewer": { "mode": "subagent",
                  "model": { "providerID": "gw", "model": "m1", "variant": "high" },
                  "system": "Review.", "request": { "body": { "temperature": 0.1 } } },
    "build": { "model": { "providerID": "gw", "model": "m1" } }
  },
  "permissions": [ { "action": "shell", "resource": "*", "effect": "ask" } ]
}
EOF
python3 -B - "$T/canned-info.json" "$T/expected.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
del d["agents"]["reviewer"]["request"]
json.dump(d, open(sys.argv[2], "w"))
PY

# same FILE_A FILE_B: equal as parsed JSON (comments stripped).
same() {
  python3 -B - "$adapter" "$1" "$2" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config
sys.exit(0 if v2config.load(sys.argv[2]) == v2config.load(sys.argv[3]) else 1)
PY
}
shape() { python3 -B "$adapter/v2config.py" shape "$1"; }

# run NAME MODE ARGS...: sets $rc, $out (stdout) and $err (stderr).
run() {
  local name=$1 mode=$2
  shift 2
  rc=0
  TMPDIR="$T/tmp" V2_CONFIG_POLL_TIMEOUT="${POLL:-30}" \
    bash "$converter" "$@" --opencode-bin "$T/bin/opencode-$mode" \
    >"$T/$name.out" 2>"$T/$name.err" </dev/null || rc=$?
  out=$(cat "$T/$name.out")
  err=$(cat "$T/$name.err")
}

in_sum=$(sha256sum "$T/in.jsonc" | cut -d' ' -f1)

# 1. Conversion to strict JSON.
run basic normal --input "$T/in.jsonc" --output "$T/out.json" --backup-root "$T/bk"
(( rc == 0 )) || fail "basic conversion exited $rc: $err"
same "$T/expected.json" "$T/out.json" || fail "output differs from the canned translation minus temperature"
# Exactly these, so nothing translated (agent, provider, permission,
# autoupdate, ...) is falsely reported.
assert_eq "dropped: agents.reviewer.request.body.temperature
dropped: provider.gw.blacklist
dropped: server" "$(grep '^dropped: ' <<<"$out" | sort)"
assert_eq v2 "$(shape "$T/out.json")"
assert_eq '{' "$(head -c 1 "$T/out.json")"
assert_eq "$in_sum" "$(sha256sum "$T/in.jsonc" | cut -d' ' -f1)"
python3 -B -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/out.json" || fail "strict output is not strict JSON"

# The fake was started as the brief requires.
log=$(cat "$T/serve.log")
assert_contains "$log" "argv: [serve] [--hostname] [127.0.0.1] [--port] ["
[[ "$(grep -c '^cwd=' "$T/serve.log")" == 2 ]] || fail "expected two servers: $log"
while IFS= read -r line; do
  [[ "$line" == cwd="$T"/tmp/*/work ]] || fail "server not started in the sandbox's work dir: $line"
done < <(grep '^cwd=' "$T/serve.log")
while IFS= read -r line; do
  assert_eq "env=HOME,OPENCODE_DISABLE_AUTOUPDATE,OPENCODE_PASSWORD,OPENCODE_SERVER_PASSWORD,PATH,PWD,SHLVL,XDG_CACHE_HOME,XDG_CONFIG_HOME,XDG_DATA_HOME,XDG_STATE_HOME,_" "$line"
done < <(grep '^env=' "$T/serve.log")

# 2. A .jsonc output carries the provenance header.
run header normal --input "$T/in.jsonc" --output "$T/out.jsonc" --backup-root "$T/bk"
(( rc == 0 )) || fail "jsonc conversion exited $rc: $err"
head=$(grep '^//' "$T/out.jsonc")
assert_contains "$head" "$T/in.jsonc"
assert_contains "$head" "$in_sum"
assert_contains "$head" "2.3.0-fake"
assert_contains "$head" "converted with OpenCode 2's own translation"
same "$T/expected.json" "$T/out.jsonc" || fail "jsonc output differs from the expected translation"
assert_eq v2 "$(shape "$T/out.jsonc")"

# 3. An unexpected top-level key the translation drops is reported.
python3 -B - "$adapter" "$T/in.jsonc" "$T/extra.json" <<'PY'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config
d = v2config.load(sys.argv[2])
d["x_custom"] = {"kept": False}
json.dump(d, open(sys.argv[3], "w"))
PY
run extra normal --input "$T/extra.json" --output "$T/extra-out.json" --backup-root "$T/bk"
(( rc == 0 )) || fail "extra-key conversion exited $rc: $err"
assert_contains "$out" "dropped: x_custom"

# 3b. Entries the translation drops are reported one by one, per source key, so
# a key sharing a target (agent/mode -> agents) cannot mask a loss.
python3 -B - "$adapter" "$T/in.jsonc" "$T/canned-info.json" "$T/lossy.json" "$T/canned-lossy.json" <<'PY'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import v2config
v1 = v2config.load(sys.argv[2])
v1["provider"]["legacy"] = {"npm": "@ai-sdk/openai-compatible", "models": {}}
v1["agent"]["old"] = {"model": "gw/m1"}
v1["mode"] = {"planner": {"model": "gw/m1"}}
v1["command"] = {"c1": {"template": "x"}}
v1["mcp"] = {"srv": {"type": "local", "command": ["true"]}}
v1["disabled_providers"] = ["legacy", "ghost"]
v1["enabled_providers"] = ["gw", "nogo"]
json.dump(v1, open(sys.argv[4], "w"))
info = json.load(open(sys.argv[3]))
info["agents"]["planner"] = {"model": {"providerID": "gw", "model": "m1"}}
info["commands"] = {}
info["mcp"] = {"servers": {}}
# An object-valued and a list-valued resource must not crash the check; the
# list counts for each name in it (the deny-all is written as ["*"]). `nogo`
# has the wrong effect.
info["policies"] = [
    {"action": "provider.use", "resource": {"odd": True}, "effect": "deny"},
    {"action": "provider.use", "resource": ["*"], "effect": "deny"},
    {"action": "provider.use", "resource": ["legacy", "other"], "effect": "deny"},
    {"action": "provider.use", "resource": "gw", "effect": "allow"},
    {"action": "provider.use", "resource": "nogo", "effect": "deny"},
]
json.dump(info, open(sys.argv[5], "w"))
PY
run lossy lossy --input "$T/lossy.json" --output "$T/lossy-out.json" --backup-root "$T/bk"
(( rc == 0 )) || fail "lossy conversion exited $rc: $err"
assert_eq "dropped: agent.old
dropped: agents.reviewer.request.body.temperature
dropped: command.c1
dropped: disabled_providers.ghost
dropped: enabled_providers.nogo
dropped: mcp.srv
dropped: provider.gw.blacklist
dropped: provider.legacy
dropped: server" "$(grep '^dropped: ' <<<"$out" | sort)"

# 3c. The real 2.3.0 translation of one entry of each kind (fixtures-v2/convert,
# observed on 2026-11-21): only genuine losses are reported.
run real real --input "$fixtures/convert/v1-all-kinds.jsonc" --output "$T/real-out.json" --backup-root "$T/bk"
(( rc == 0 )) || fail "real-shape conversion exited $rc: $err"
assert_eq "dropped: agents.writer.request.body.temperature
dropped: provider.gw.blacklist
dropped: provider.openai.blacklist
dropped: provider.openai.whitelist
dropped: server" "$(grep '^dropped: ' <<<"$out" | sort)"
python3 -B - "$fixtures/convert/real-2.3.0-info.json" "$T/real-out.json" <<'PY' \
  || fail "real-shape output differs from the observed translation minus temperature"
import json, sys
want = json.load(open(sys.argv[1]))
del want["agents"]["writer"]["request"]
sys.exit(0 if json.load(open(sys.argv[2])) == want else 1)
PY

# 3d. enabled_providers whose translation keeps the allows but lost the
# `deny *` that makes them restrictive; a dict effect must not crash.
python3 -B - "$fixtures/convert/real-2.3.0-info.json" "$T/canned-nodenyall.json" <<'PY'
import json, sys
info = json.load(open(sys.argv[1]))
info["policies"] = [p for p in info["policies"] if p["resource"] != "*"]
info["policies"].append({"action": "provider.use", "resource": "gw", "effect": {"odd": True}})
json.dump(info, open(sys.argv[2], "w"))
PY
run nodenyall nodenyall --input "$fixtures/convert/v1-all-kinds.jsonc" --output "$T/nodenyall-out.json" --backup-root "$T/bk"
(( rc == 0 )) || fail "no-deny-all conversion exited $rc: $err"
assert_eq "dropped: agents.writer.request.body.temperature
dropped: enabled_providers (deny *)
dropped: provider.gw.blacklist
dropped: provider.openai.blacklist
dropped: provider.openai.whitelist
dropped: server" "$(grep '^dropped: ' <<<"$out" | sort)"

# 4. A V2 input is refused with 2, and nothing is written.
run v2in normal --input "$T/out.json" --output "$T/v2-out.json" --backup-root "$T/bk"
assert_eq 2 "$rc"
[[ ! -e "$T/v2-out.json" ]] || fail "a refused V2 input produced output"

# 5. Usage errors.
run usage normal --input "$T/in.jsonc" --backup-root "$T/bk"
assert_eq 2 "$rc"
run same-path normal --input "$T/in.jsonc" --output "$T/in.jsonc" --backup-root "$T/bk"
assert_eq 2 "$rc"
assert_eq "$in_sum" "$(sha256sum "$T/in.jsonc" | cut -d' ' -f1)"

# 6. In place: atomic, mode kept, original backed up with SHA256SUMS.
cp "$T/in.jsonc" "$T/ip.jsonc"
chmod 640 "$T/ip.jsonc"
run inplace normal --input "$T/ip.jsonc" --in-place --backup-root "$T/bk"
(( rc == 0 )) || fail "in-place conversion exited $rc: $err"
assert_eq v2 "$(shape "$T/ip.jsonc")"
same "$T/expected.json" "$T/ip.jsonc" || fail "in-place result differs"
assert_eq 640 "$(stat -c %a "$T/ip.jsonc")"
backup=$(find "$T/bk" -name ip.jsonc -path '*/convert-*/*')
[[ -n "$backup" ]] || fail "no backup of the original under --backup-root"
assert_eq "$in_sum" "$(sha256sum "$backup" | cut -d' ' -f1)"
(cd "$(dirname "$backup")" && sha256sum -c --quiet SHA256SUMS) || fail "backup SHA256SUMS does not verify"
[[ -z "$(find "$T" -maxdepth 1 -name '.convert-v1*')" ]] || fail "staging left behind"

# 7. In place on a symlink is refused, untouched.
cp "$T/in.jsonc" "$T/target.jsonc"
ln -s "$T/target.jsonc" "$T/link.jsonc"
run symlink normal --input "$T/link.jsonc" --in-place --backup-root "$T/bk"
assert_eq 1 "$rc"
[[ -L "$T/link.jsonc" ]] || fail "symlink replaced"
assert_eq "$in_sum" "$(sha256sum "$T/target.jsonc" | cut -d' ' -f1)"

# 8. A reload that differs fails, leaving no output.
run differ differ --input "$T/in.jsonc" --output "$T/differ.json" --backup-root "$T/bk"
assert_eq 1 "$rc"
assert_contains "$err" "reload"
[[ ! -e "$T/differ.json" ]] || fail "output written although the reload check failed"
[[ -z "$(find "$T" -maxdepth 1 -name '.convert-v1*')" ]] || fail "staging left behind after a failed reload"

# 9. A layer outside the sandbox is refused.
run leak leak --input "$T/in.jsonc" --output "$T/leak.json" --backup-root "$T/bk"
assert_eq 1 "$rc"
assert_contains "$err" "/etc/opencode-outside"
[[ ! -e "$T/leak.json" ]] || fail "output written although a layer leaked"

# 10. A server that never reports the document layer times out.
POLL=2 run nodoc nodoc --input "$T/in.jsonc" --output "$T/nodoc.json" --backup-root "$T/bk"
assert_eq 1 "$rc"
assert_contains "$err" "document"
[[ ! -e "$T/nodoc.json" ]] || fail "output written although no document layer appeared"

# 10b. v2_stop_pid stays bounded when `ps` reports nothing for a live leader
# that ignores TERM: it must not `wait` on it, and the group is KILLed.
rc=0
(
  # shellcheck source=SCRIPTDIR/../runtime/opencode-v2-adapter/v2-run.sh
  source "$adapter/v2-run.sh"
  # shellcheck disable=SC2329  # called by v2_stop_pid
  ps() { return 1; }
  setsid bash -c 'trap "" TERM; sleep 60' </dev/null >/dev/null 2>&1 &
  leader=$!
  sleep 0.3
  start=$SECONDS
  v2_stop_pid "$leader"
  (( SECONDS - start < 10 )) || { kill -s KILL -- "-$leader" 2>/dev/null; exit 3; }
  ! kill -0 -- "-$leader" 2>/dev/null || { kill -s KILL -- "-$leader" 2>/dev/null; exit 4; }
) || rc=$?
assert_eq 0 "$rc"

# 11. Nothing survives, nothing leaks.
sleep 0.5
if pgrep -f "fake-api.py .*$T" >/dev/null; then
  fail "a fake server survived: $(pgrep -af "fake-api.py .*$T")"
fi
[[ -z "$(ls -A "$T/tmp")" ]] || fail "sandbox left behind: $(ls -A "$T/tmp")"
[[ ! -e "$adapter/__pycache__" && ! -e "$fixtures/__pycache__" ]] || fail "__pycache__ written"
leaked=$(find "$bundle" -newer "$marker" 2>/dev/null || true)
# Temp files. The converter's own processes honour TMPDIR (set to $T/tmp for every
# run and checked empty above). The server it starts runs under `env -i` with no
# TMPDIR, by design, so that is NOT covered by that check: its sandbox is the
# converter's work dir, which lives wherever the converter's mktemp put it. A
# fingerprinted scan of the global /tmp covers it without depending on other
# processes: fail only on a new entry holding this run's sandbox layout or token.
while IFS= read -r entry; do
  if [[ -d "$entry/config/opencode" && -d "$entry/work" ]] \
     || grep -rqF -- "$isolation_token" "$entry" 2>/dev/null; then
    leaked+="$entry "
  fi
done < <(find /tmp -mindepth 1 -maxdepth 1 -name 'tmp.*' -newer "$marker" ! -path "$T" 2>/dev/null)
# A hardcoded /tmp in the runtime would bypass TMPDIR. Every file must exist,
# or the grep below would pass without looking.
hardcode_files=("$adapter/convert-v1-config.sh" "$adapter/v2-run.sh" "$adapter/v2-http.sh" \
  "$adapter/v2config.py" "$fixtures/fake-api.py")
for f in "${hardcode_files[@]}"; do
  [[ -f "$f" ]] || fail "isolation check input missing: $f"
done
if grep -n '/tmp\b' "${hardcode_files[@]}" | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' >"$T/hardcoded-tmp.txt"; then
  fail "the converter runtime hardcodes /tmp, bypassing TMPDIR: $(<"$T/hardcoded-tmp.txt")"
fi
[[ -z "$leaked" ]] || fail "written outside the test root: $leaked"

printf 'v2-convert-test: PASS\n'
