#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Runnable entry point for the installed-vs-repository alignment check.
# Mirrors run-tests.sh: no arguments needed for the ordinary case.
#
#   bash models/routing/opencode/eval/check-alignment.sh
#   bash models/routing/opencode/eval/check-alignment.sh --json /tmp/report.json
#
# Exits 0 when aligned (or only prose is stale), 1 on drift, 2 on usage or a
# missing installation. Makes no model calls and changes nothing.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bundle=$(cd "$root/.." && pwd)
source "$root/runtime/opencode-v1-adapter/check-alignment.sh"
source "$root/runtime/opencode-v1-adapter/select-activation-target.sh"

# The installed configuration lives wherever OpenCode reads its user-global
# config. Honour XDG_CONFIG_HOME so this works on a non-default setup.
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
live_root="$config_home/opencode"

# Resolve exactly the way activation does. select_activation_target refuses
# (exit 1) when both opencode.json and opencode.jsonc exist, because there is
# no safe way to know which one OpenCode will read. Picking one silently
# would let this report ALIGNED against a file the runtime may ignore.
if ! live_config=$(select_activation_target "$live_root"); then
  printf 'check-alignment: %s contains both opencode.json and opencode.jsonc.\n' "$live_root" >&2
  printf 'check-alignment: ambiguous -- cannot tell which one OpenCode reads. Remove one.\n' >&2
  exit 2
fi

check_alignment \
  --profile "$bundle/profiles/v1-restored-2026-09.jsonc" \
  --targets "$root/manifests/phase-r-routing-targets.json" \
  --bundle-root "$bundle/.opencode" \
  --live-config "$live_config" \
  --live-support-root "$live_root" \
  "$@"
