#!/usr/bin/env bash
# The OpenCode 2 capability probe, after V1's probe.sh, run through
# dispatch_fixture so it shares the sandbox, routing check and credits.
# Source this file.
#
#   v2_capability_probe OUTDIR KEY DISPATCH_OPTION...
#       calls dispatch_fixture DISPATCH_OPTION... --outdir OUTDIR/dispatch
#       --label capability-KEY --prompt-file OUTDIR/prompt.txt --timeout 120,
#       the prompt being exactly `Reply with exactly: CAPABILITY_OK`, and writes
#       OUTDIR/probe.json as {key, classification}: USABLE when the dispatch is
#       OK and its response, stripped, is CAPABILITY_OK; WRONG_RESPONSE when the
#       dispatch is OK and the response is anything else; otherwise the
#       dispatch's own classification. 0 only for USABLE; 2 on a usage error.
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck source=models/routing/opencode/eval/runtime/opencode-v2-adapter/dispatch-fixture.sh disable=SC1091 # path built from the script's own directory at run time
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dispatch-fixture.sh"

v2_capability_probe() {
  local outdir=${1:?v2_capability_probe: OUTDIR required} key=${2:?v2_capability_probe: KEY required}
  local rc=0 classification
  shift 2
  mkdir -p "$outdir"
  printf '%s' 'Reply with exactly: CAPABILITY_OK' >"$outdir/prompt.txt"
  dispatch_fixture "$@" --outdir "$outdir/dispatch" --label "capability-$key" \
    --prompt-file "$outdir/prompt.txt" --timeout 120 || rc=$?
  if (( rc == 2 )) || [[ ! -f "$outdir/dispatch/dispatch.json" ]]; then
    printf 'v2_capability_probe: dispatch_fixture refused its options\n' >&2
    return 2
  fi
  classification=$(dispatch_classification "$outdir/dispatch")
  if [[ "$classification" == OK ]]; then
    if python3 -I -B -c 'import sys
sys.exit(0 if open(sys.argv[1], encoding="utf-8").read().strip() == "CAPABILITY_OK" else 1)' \
        "$outdir/dispatch/response.txt"; then
      classification=USABLE
    else
      classification=WRONG_RESPONSE
    fi
  fi
  jq -n --arg k "$key" --arg c "$classification" '{key: $k, classification: $c}' >"$outdir/probe.json"
  [[ "$classification" == USABLE ]]
}
