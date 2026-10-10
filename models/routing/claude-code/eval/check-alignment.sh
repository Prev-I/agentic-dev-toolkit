#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Does the installed Claude Code configuration still match this bundle?
#
#   bash models/routing/claude-code/eval/check-alignment.sh
#   bash models/routing/claude-code/eval/check-alignment.sh --json /tmp/report.json
#
# Exits 0 when aligned (or only prose is stale), 1 on drift, 2 on usage or a
# missing installation. Makes no model calls and writes nothing itself
# outside a temporary directory; when the installed hook's content matches
# the bundle's, it runs it on two synthetic dispatches.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bundle=$(cd "$root/.." && pwd)
installed=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$root/lib" exec python3 -m check_alignment \
  --bundle "$bundle" --installed "$installed" "$@"
