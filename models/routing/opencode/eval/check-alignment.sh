#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Runnable entry point for the installed-vs-repository alignment check.
# Mirrors run-tests.sh: no arguments needed for the ordinary case.
#
#   bash models/routing/opencode/eval/check-alignment.sh
#   bash models/routing/opencode/eval/check-alignment.sh --json /tmp/report.json
#
# Checks against the OpenCode 2 bundle under v2/.
#
# Exits 0 when aligned (or only prose is stale), 1 on drift, 2 on usage or a
# missing installation. Makes no model calls and changes nothing.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bundle=$(cd "$root/.." && pwd)
source "$root/runtime/opencode-v2-adapter/check-alignment.sh"
# The target selector is shared with 1.x: both versions use the same filenames.
source "$root/runtime/opencode-v1-adapter/select-activation-target.sh"

# The installed configuration lives wherever OpenCode reads its user-global
# config. Honour XDG_CONFIG_HOME so this works on a non-default setup.
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
live_root="$config_home/opencode"

# Resolve the way activation does. A symlinked config is refused (activation
# would replace the link, so there is nothing safe to compare), and a dangling
# link counts as present. When both opencode.json and opencode.jsonc exist
# there is no safe way to know which one OpenCode reads, so refuse rather than
# report ALIGNED against a file the runtime may ignore.
for candidate in "$live_root/opencode.json" "$live_root/opencode.jsonc"; do
  if [[ -L "$candidate" ]]; then
    printf 'check-alignment: %s is a symlink (to %s).\n' "$candidate" "$(readlink "$candidate")" >&2
    printf 'check-alignment: refusing -- check the link target directly, or replace the link.\n' >&2
    exit 2
  fi
done
if [[ ( -e "$live_root/opencode.json" || -L "$live_root/opencode.json" ) \
      && ( -e "$live_root/opencode.jsonc" || -L "$live_root/opencode.jsonc" ) ]]; then
  printf 'check-alignment: %s contains both opencode.json and opencode.jsonc.\n' "$live_root" >&2
  printf 'check-alignment: ambiguous -- cannot tell which one OpenCode reads. Remove one.\n' >&2
  exit 2
fi
live_config=$(select_activation_target "$live_root")

check_alignment_v2 \
  --profile "$bundle/v2/opencode.jsonc" \
  --targets "$bundle/v2/manifests/current-routing-targets.json" \
  --bundle-root "$bundle/v2/.opencode" \
  --live-config "$live_config" \
  --live-support-root "$live_root" \
  "$@"
