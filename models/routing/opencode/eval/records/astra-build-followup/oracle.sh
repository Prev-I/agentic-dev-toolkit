#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Unconditional prepends, substring matches, or a missed PATH-setting site
# must fail these checks; helper names and implementation text are irrelevant.
installer=$(realpath "$1/environments/linux/install.sh")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mapfile -t lines < "$installer"
[[ "${lines[-1]}" == 'main "$@"' ]] || exit 1
unset 'lines[-1]'
printf '%s\n' "${lines[@]}" > "$scratch/functions.sh"

for scenario in all mixed missing exact existing; do
  HOME="$scratch/home with spaces $scenario" CASE="$scenario" ROOT="$scratch" \
    PATH=/usr/bin:/bin /bin/bash --noprofile --norc <<'BASH'
set -Eeuo pipefail
IFS=$'\n\t'
mkdir -p "$HOME"
case "$CASE" in
  all|exact|existing) mkdir -p "$HOME/.local/bin" "$HOME/bin" "$HOME/.opencode/bin" ;;
  mixed) mkdir -p "$HOME/.local/bin" "$HOME/.opencode/bin" ;;
esac
case "$CASE" in
  all) initial=/usr/bin:/bin
    expected="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$initial" ;;
  mixed) initial="$HOME/.local/bin:/usr/bin:/bin"
    expected="$HOME/.opencode/bin:$initial" ;;
  missing) initial=/usr/bin:/bin; expected="$initial" ;;
  exact) initial="$HOME/bin-extra:/usr/bin:/bin"
    expected="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$initial" ;;
  existing) initial="/usr/bin:$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/bin:/bin"
    expected="$initial" ;;
esac
PATH="$initial"
source "$ROOT/functions.sh"
[[ "$PATH" == "$expected" ]] || {
  printf 'FAIL bootstrap %s: expected <%s>, got <%s>\n' "$CASE" "$expected" "$PATH"
  exit 1
}
printf 'PASS bootstrap %s\n' "$CASE"

# Dry-run must not create a shell config, nor refresh PATH.
PATH="$initial"
DRY_RUN=1
ensure_shell_configuration >/dev/null
[[ ! -e "$HOME/.bashrc" && "$PATH" == "$initial" ]]
DRY_RUN=0
printf '# user setting\n' > "$HOME/.bashrc"
ensure_shell_configuration >/dev/null
# The existing configure function legitimately creates .local/bin.
if [[ "$CASE" == missing ]]; then expected="$HOME/.local/bin:$initial"; fi
[[ "$PATH" == "$expected" ]] || {
  printf 'FAIL refresh %s: expected <%s>, got <%s>\n' "$CASE" "$expected" "$PATH"
  exit 1
}
[[ "$(<"$HOME/.bashrc.pre-agentic-dev-toolkit")" == '# user setting' ]]
printf 'PASS refresh and dry-run %s\n' "$CASE"

# Stub only the external activation dependency, not PATH logic.
direnv() { :; }
export -f direnv
PATH="$initial" EXPECTED="$expected" /bin/bash --noprofile --norc <<'ACTIVATE'
set -Eeuo pipefail
source "$HOME/.bashrc"
[[ "$PATH" == "$EXPECTED" ]] || {
  printf 'FAIL generated block: expected <%s>, got <%s>\n' "$EXPECTED" "$PATH"
  exit 1
}
source "$HOME/.bashrc"
[[ "$PATH" == "$EXPECTED" ]] || exit 1
[[ "${OPENCODE_ENABLE_EXA:-}" == true ]]
ACTIVATE
printf 'PASS generated block and repeated activation %s\n' "$CASE"
BASH
done
printf 'PASS: independent PATH oracle (5 scenarios, all 3 sites)\n'
