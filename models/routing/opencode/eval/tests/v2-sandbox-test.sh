#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=models/routing/opencode/eval/tests/test-lib.sh disable=SC1091 # path built from the script's own directory at run time
source "$root/tests/test-lib.sh"
adapter="$root/runtime/opencode-v2-adapter"
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-sandbox.sh disable=SC1091 # path built from the script's own directory at run time
source "$adapter/v2-sandbox.sh"

# The sandboxed server a screening dispatch runs against: layer check, config
# building, sandbox lifecycle, and the server itself through
# fixtures-v2/fake-opencode-screening.sh.

fixtures="$root/tests/fixtures-v2"
v2config() { python3 -I -B "$adapter/v2config.py" "$@"; }

work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
cleanup() {
  # Only processes this shell recorded, by pid.
  _v2_cleanup
  rm -rf "${work:?}"
}
trap cleanup EXIT

# layers_clean_and_leak
sb="$work/sb-layers"
mkdir -p "$sb/config/opencode" "$sb/work"
printf '[{"path":"%s/config/opencode/opencode.json","type":"document"},{"path":"%s/work","type":"directory"}]\n' \
  "$sb" "$sb" >"$work/layers-clean.json"
v2config layers "$work/layers-clean.json" "$sb" || fail "clean layers refused"
jq -c '. + [{"path":"/etc/x","type":"directory"}]' "$work/layers-clean.json" >"$work/layers-leak.json"
rc=0; err=$(v2config layers "$work/layers-leak.json" "$sb" 2>&1) || rc=$?
assert_eq 1 "$rc"
assert_contains "$err" "  - /etc/x (directory) is outside the sandbox"

# layers_pathless_hides_info: a layer's info (the effective config) never
# reaches the problem text.
printf '[{"type":"global","info":{"providers":{"fakep":{"key":"INFO-MARKER-77"}}}}]\n' >"$work/layers-nopath.json"
rc=0; err=$(v2config layers "$work/layers-nopath.json" "$sb" 2>&1) || rc=$?
assert_eq 1 "$rc"
assert_contains "$err" "a layer with no path (type global, keys ['info', 'type'])"
[[ "$err" != *INFO-MARKER-77* ]] || fail "a layer's info reached the problem text"

# build_config_minimal
printf '{"providers":{"fakep":{"settings":{"baseURL":"http://127.0.0.1:9/v1"}}}}\n' >"$work/fragment.json"
printf '{"name":"screening-reviewer","row":{"mode":"primary"}}\n' >"$work/row.json"
v2config build-config - "$work/fragment.json" "$work/row.json" "$work/built.json" \
  || fail "build-config failed"
assert_eq disable "$(jq -r .update "$work/built.json")"
assert_eq primary "$(jq -r '.agents["screening-reviewer"].mode' "$work/built.json")"
assert_eq true "$(jq '.providers.fakep != null' "$work/built.json")"
assert_eq https://opencode.ai/config.json "$(jq -r '."$schema"' "$work/built.json")"

# build_config_merges_over_a_base
printf '{"update":"auto","providers":{"other":{"a":1},"fakep":{"old":true}},"policies":[{"action":"x","resource":"*","effect":"deny"}]}\n' >"$work/base.json"
printf '{"providers":{"fakep":{"new":true}},"policies":[{"action":"y","resource":"*","effect":"allow"}]}\n' >"$work/fragment2.json"
v2config build-config "$work/base.json" "$work/fragment2.json" - "$work/built2.json" \
  || fail "build-config over a base failed"
assert_eq disable "$(jq -r .update "$work/built2.json")"
assert_eq '{"a":1}' "$(jq -c .providers.other "$work/built2.json")"
assert_eq '{"new":true}' "$(jq -c .providers.fakep "$work/built2.json")"
assert_eq x,y "$(jq -r '[.policies[].action] | join(",")' "$work/built2.json")"

# build_config_rejects_fragment_keys
printf '{"providers":{},"agents":{"x":{}}}\n' >"$work/fragment-bad.json"
rc=0; v2config build-config - "$work/fragment-bad.json" - "$work/bad.json" 2>/dev/null || rc=$?
assert_eq 2 "$rc"
[[ ! -e "$work/bad.json" ]] || fail "output written for a refused fragment"

# real-dirs
dirs=$(XDG_CONFIG_HOME="$work/xdg" v2config real-dirs)
home=$(python3 -I -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')
assert_contains "$dirs" "$home/.config/opencode"
assert_contains "$dirs" "$home/.opencode"
assert_contains "$dirs" "$work/xdg/opencode"

# create_refuses_real_dirs
rc=0; XDG_CONFIG_HOME="$work/xdg" v2_sandbox_create "$work/xdg/opencode/x" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"
[[ ! -e "$work/xdg" ]] || fail "create made a directory under a refused parent"
rc=0; XDG_CONFIG_HOME="$work/xdg" v2_sandbox_create "$work/xdg/opencode" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"

# create
SANDBOX=$(v2_sandbox_create "$work/sandboxes")
[[ "$SANDBOX" == "$work/sandboxes/"* ]] || fail "sandbox not under its parent: $SANDBOX"
for d in home config/opencode data/opencode state cache work; do
  assert_dir "$SANDBOX/$d"
done

# populate_rewrites_instructions
printf '{"instructions":[".opencode/model-routing.md"],"update":"disable"}\n' >"$work/cfg.json"
printf '{"fakep":{"type":"api","key":"not-a-real-key"}}\n' >"$work/creds.json"
v2_sandbox_populate "$SANDBOX" "$work/cfg.json" "$work/creds.json" "$root/../v2/.opencode" \
  || fail "populate failed"
assert_eq "[\"$SANDBOX/config/opencode/model-routing.md\"]" \
  "$(jq -c .instructions "$SANDBOX/config/opencode/opencode.json")"
assert_file "$SANDBOX/config/opencode/model-routing.md"
assert_file "$SANDBOX/config/opencode/agents/reviewer.md"
assert_eq 600 "$(stat -c %a "$SANDBOX/data/opencode/auth.json")"
cmp -s "$work/creds.json" "$SANDBOX/data/opencode/auth.json" || fail "credentials not copied verbatim"
v2_sandbox_destroy "$SANDBOX"
[[ ! -e "$SANDBOX" ]] || fail "sandbox not removed"

# A wrapper bakes the fake's state directory, since the server starts under env -i.
state="$work/state"
mkdir -p "$state"
printf '{"data":[]}\n' >"$state/models.json"
cat >"$work/opencode" <<EOF
#!/usr/bin/env bash
export FAKE_SCREEN_STATE='$state'
exec '$fixtures/fake-opencode-screening.sh' "\$@"
EOF
chmod +x "$work/opencode"
export OPENCODE_BIN="$work/opencode"

# serve_and_destroy
SANDBOX=$(v2_sandbox_create "$work/sandboxes")
v2_sandbox_populate "$SANDBOX" "$work/built.json" "$work/creds.json" || fail "populate failed"
V2_CONFIG_POLL_TIMEOUT=10 v2_sandbox_serve "$SANDBOX" || fail "serve failed"
assert_file "$SANDBOX/layers.json"
assert_file "$SANDBOX/version"
assert_file "$SANDBOX/url"
assert_eq 2.3.0-fake "$(cat "$SANDBOX/version")"
assert_eq 2 "$(jq 'length' "$SANDBOX/layers.json")"
line=$(grep '^serve ' "$state/log")
pid=$(sed -n 's/.* pid=\([0-9]*\) .*/\1/p' <<<"$line")
assert_eq "$SANDBOX/work" "$(sed -n 's/.* cwd=\(.*\) home=.*/\1/p' <<<"$line")"
assert_eq "$SANDBOX/home" "$(sed -n 's/.* home=\(.*\)$/\1/p' <<<"$line")"
assert_eq "$pid" "$(cat "$SANDBOX/pid")"
kill -0 "$pid" 2>/dev/null || fail "server not running after serve"
v2_api_get "$(cat "$SANDBOX/url")" /api/model >/dev/null || fail "api_model not served"
v2_sandbox_destroy "$SANDBOX"
! kill -0 "$pid" 2>/dev/null || fail "server $pid survived destroy"
[[ ! -e "$SANDBOX" ]] || fail "sandbox not removed"
v2_sandbox_destroy "$SANDBOX" || fail "destroy is not idempotent"

# serve_refuses_leak
: >"$state/log"
printf 'leak\n' >"$state/mode"
SANDBOX=$(v2_sandbox_create "$work/sandboxes")
v2_sandbox_populate "$SANDBOX" "$work/built.json" "$work/creds.json" || fail "populate failed"
# Not in $(...): the server must be this shell's child, recorded in its _V2_PIDS.
rc=0; V2_CONFIG_POLL_TIMEOUT=10 v2_sandbox_serve "$SANDBOX" 2>"$work/leak.err" >/dev/null || rc=$?
assert_eq 1 "$rc"
assert_contains "$(cat "$work/leak.err")" /etc/opencode-outside
pid=$(sed -n 's/.* pid=\([0-9]*\) .*/\1/p' "$state/log")
[[ -n "$pid" ]] || fail "no server was started"
v2_sandbox_destroy "$SANDBOX"
! kill -0 "$pid" 2>/dev/null || fail "server $pid survived destroy after a refusal"
assert_eq '' "$(ls -A "$work/sandboxes")"
(( ${#_V2_PIDS[@]} == 0 )) || fail "pids still recorded: ${_V2_PIDS[*]}"

printf 'v2-sandbox-test: PASS\n'
