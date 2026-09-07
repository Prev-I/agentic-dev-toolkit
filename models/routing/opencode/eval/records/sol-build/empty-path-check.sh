#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# Post-review diagnostic, not a change to the frozen comparative oracle.
installer=$(realpath "$1/environments/linux/install.sh")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mapfile -t lines < "$installer"
[[ "${lines[-1]}" == 'main "$@"' ]]
unset 'lines[-1]'
printf '%s\n' "${lines[@]}" > "$scratch/functions.sh"
HOME="$scratch/home" ROOT="$scratch" /bin/bash --noprofile --norc <<'BASH'
set -Eeuo pipefail
mkdir -p "$HOME/.local/bin" "$HOME/bin" "$HOME/.opencode/bin"
normal_path=$PATH
expected="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:"
PATH=''
source "$ROOT/functions.sh"
bootstrap=$PATH
PATH=$normal_path
ensure_shell_configuration >/dev/null
generated=$(PATH='' /bin/bash --noprofile --norc -c '
  direnv() { :; }
  source "$HOME/.bashrc"
  printf "%s" "$PATH"
')
# Let configuration perform real temp-HOME I/O with an empty PATH. These
# wrappers resolve utility executables only; they do not alter PATH behavior.
mkdir() { /usr/bin/mkdir "$@"; }
touch() { /usr/bin/touch "$@"; }
mktemp() { /usr/bin/mktemp "$@"; }
awk() { /usr/bin/awk "$@"; }
cat() { /usr/bin/cat "$@"; }
cmp() { /usr/bin/cmp "$@"; }
cp() { /usr/bin/cp "$@"; }
mv() { /usr/bin/mv "$@"; }
rm() { /usr/bin/rm "$@"; }
PATH=''
ensure_shell_configuration >/dev/null
refresh=$PATH
PATH=$normal_path
failed=0
for site in bootstrap generated refresh; do
  if [[ "${!site}" == "$expected" ]]; then
    printf 'PASS empty PATH: %s preserves trailing empty entry\n' "$site"
  else
    printf 'FAIL empty PATH: %s expected <%s>, got <%s>\n' "$site" "$expected" "${!site}"
    failed=1
  fi
done
exit "$failed"
BASH
