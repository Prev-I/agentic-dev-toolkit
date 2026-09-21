#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/opencode-service/opencode-direnv-exec.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
command -v direnv >/dev/null || fail 'real direnv is required'

# Isolate both the approval database and the input environment from the host.
export HOME="$TEMP_DIR/home" XDG_CONFIG_HOME="$TEMP_DIR/config" XDG_DATA_HOME="$TEMP_DIR/data"
export DIRENV_CONFIG="$TEMP_DIR/custom-direnv"
unset DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
mkdir -p "$HOME" "$DIRENV_CONFIG"
export OPENCODE_DIRENV_ROOT="$TEMP_DIR/work spaces"
export OPENCODE_DIRENV_VARS='TEST_ALPHA TEST_BETA'
export CHILD_RECORD="$TEMP_DIR/child-ran" BASELINE_PATH="$PATH"
mkdir -p "$OPENCODE_DIRENV_ROOT/first" "$OPENCODE_DIRENV_ROOT/second"

cat > "$TEMP_DIR/child" <<'CHILD'
#!/usr/bin/env bash
set -eu
[[ "$PATH" == "$BASELINE_PATH" ]]
[[ "${TEST_ALPHA:-}" == $'alpha with spaces\nsecond line\n' ]]
[[ "${TEST_BETA:-}" == 'beta=value' ]]
[[ "${WORKSPACE_ROOT:-}" == 'original-root' ]]
[[ -z "${NOT_ALLOWED+x}" ]]
[[ "$#" == 2 && "$1" == '--flag' && "$2" == 'argument with spaces' ]]
touch "$CHILD_RECORD"
exit "${CHILD_EXIT:-0}"
CHILD
chmod +x "$TEMP_DIR/child"
export WORKSPACE_ROOT=original-root

cat > "$OPENCODE_DIRENV_ROOT/first/.envrc" <<'ENVRC'
export TEST_ALPHA=$'alpha with spaces\nsecond line\n'
export NOT_ALLOWED=should-not-be-imported
export WORKSPACE_ROOT="$PWD"
# Output must not contaminate the data channel or leak into logs.
printf 'SENSITIVE_FIXTURE_OUTPUT\n'
printf 'SENSITIVE_FIXTURE_ERROR\n' >&2
ENVRC
cat > "$OPENCODE_DIRENV_ROOT/second/.envrc" <<'ENVRC'
export TEST_BETA='beta=value'
ENVRC
direnv allow "$OPENCODE_DIRENV_ROOT/first" >/dev/null 2>&1
direnv allow "$OPENCODE_DIRENV_ROOT/second" >/dev/null 2>&1

invoke() {
  rm -f "$CHILD_RECORD"
  STATUS=0
  OUTPUT="$(bash "$LAUNCHER" "$TEMP_DIR/child" --flag 'argument with spaces' 2>&1)" || STATUS=$?
  [[ "$OUTPUT" != *SENSITIVE_FIXTURE* && "$OUTPUT" != *'alpha with spaces'* && "$OUTPUT" != *'beta=value'* ]] \
    || fail 'launcher leaked environment values/output'
}
invoke
[[ "$STATUS" == 0 && -f "$CHILD_RECORD" ]] || fail 'discovery must merge two isolated workspace environments'
[[ -z "${TEST_ALPHA+x}" && -z "${TEST_BETA+x}" ]] || fail 'launcher must not mutate caller environment'
TEST_BETA=existing-service-value invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" && "$OUTPUT" == *'service environment'* ]] \
  || fail 'conflict with inherited service value must be rejected'
TEST_BETA='beta=value' invoke
[[ "$STATUS" == 0 && -f "$CHILD_RECORD" ]] || fail 'identical inherited service value must be accepted'

# A workspace PATH change must not replace the absolute extraction tools or
# reach the server. The direnv subprocess itself keeps its own normal semantics.
printf 'export PATH=/usr/bin:/bin\n' >> "$OPENCODE_DIRENV_ROOT/second/.envrc"
direnv allow "$OPENCODE_DIRENV_ROOT/second" >/dev/null 2>&1
invoke
[[ "$STATUS" == 0 && -f "$CHILD_RECORD" ]] || fail 'workspace PATH must not affect server PATH'

# Equal duplicates are accepted; nested configs must never be evaluated.
printf "export TEST_BETA='beta=value'\n" >> "$OPENCODE_DIRENV_ROOT/first/.envrc"
direnv allow "$OPENCODE_DIRENV_ROOT/first" >/dev/null 2>&1
mkdir -p "$OPENCODE_DIRENV_ROOT/first/nested"
printf 'exit 1\n' > "$OPENCODE_DIRENV_ROOT/first/nested/.envrc"
invoke
[[ "$STATUS" == 0 && -f "$CHILD_RECORD" ]] || fail 'equal duplicates/depth-one discovery'

CHILD_EXIT=17 invoke
[[ "$STATUS" == 17 ]] || fail 'child exit status must propagate'

printf "export TEST_BETA=different\n" >> "$OPENCODE_DIRENV_ROOT/first/.envrc"
direnv allow "$OPENCODE_DIRENV_ROOT/first" >/dev/null 2>&1
invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" && "$OUTPUT" == *TEST_BETA* && "$OUTPUT" == *first* && "$OUTPUT" == *second* ]] \
  || fail 'conflicts must block exec and identify name and sources'
printf "export TEST_BETA='beta=value'\n" >> "$OPENCODE_DIRENV_ROOT/first/.envrc"
# Modification invalidates approval. The launcher must never approve it itself.
invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" ]] || fail 'blocked envrc must prevent exec'
direnv allow "$OPENCODE_DIRENV_ROOT/first" >/dev/null 2>&1
printf 'exit 1\n' >> "$OPENCODE_DIRENV_ROOT/first/.envrc"
direnv allow "$OPENCODE_DIRENV_ROOT/first" >/dev/null 2>&1
invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" ]] || fail 'erroring envrc must prevent exec'

OPENCODE_DIRENV_VARS='PATH' invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" ]] || fail 'reserved environment must be rejected'
OPENCODE_DIRENV_ROOT="$TEMP_DIR/missing" invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" ]] || fail 'missing root must not silently skip loading'
OPENCODE_DIRENV_VARS='' invoke
[[ "$STATUS" != 0 && ! -f "$CHILD_RECORD" ]] || fail 'empty allowlist must be rejected'

mkdir -p "$HOME/code"
env -u OPENCODE_DIRENV_ROOT bash "$LAUNCHER" /bin/true >/dev/null 2>&1 \
  || fail 'default HOME/code with no workspaces must support an empty result'
[[ "$(bash "$LAUNCHER" --version)" == 0.1.0 ]] || fail 'launcher version'

printf 'PASS: OpenCode direnv launcher tests\n'
