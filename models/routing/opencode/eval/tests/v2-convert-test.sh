#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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
for mode in normal differ leak nodoc; do
  cat >"$T/bin/opencode-$mode" <<EOF
#!/usr/bin/env bash
FAKE_SERVE_ENV_NAMES=\$(env | cut -d= -f1 | sort | paste -sd, -)
export FAKE_SERVE_ENV_NAMES
export FAKE_SERVE_INFO='$T/canned-info.json' FAKE_SERVE_MODE='$mode' FAKE_SERVE_LOG='$T/serve.log'
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
assert_contains "$out" "dropped: agents.reviewer.request.body.temperature"
assert_contains "$out" "dropped: provider.gw.blacklist"
assert_contains "$out" "dropped: server"
[[ "$out" != *"dropped: agent"$'\n'* && "$out" != *"dropped: provider"$'\n'* ]] || fail "a translated key was reported dropped: $out"
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

# 11. Nothing survives, nothing leaks.
sleep 0.5
if pgrep -f "fake-api.py .*$T" >/dev/null; then
  fail "a fake server survived: $(pgrep -af "fake-api.py .*$T")"
fi
[[ -z "$(ls -A "$T/tmp")" ]] || fail "sandbox left behind: $(ls -A "$T/tmp")"
[[ ! -e "$adapter/__pycache__" && ! -e "$fixtures/__pycache__" ]] || fail "__pycache__ written"
leaked=$(find "$bundle" -newer "$marker" 2>/dev/null || true)
leaked+=$(find /tmp -mindepth 1 -maxdepth 1 -name 'tmp.*' -newer "$marker" ! -path "$T" 2>/dev/null || true)
[[ -z "$leaked" ]] || fail "written outside the test root: $leaked"

printf 'v2-convert-test: PASS\n'
