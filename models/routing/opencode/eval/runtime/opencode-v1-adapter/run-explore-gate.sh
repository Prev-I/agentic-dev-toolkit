#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
explore_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$explore_runner_root/dispatch-fixture.sh"

explore_request() {
  cat <<'PROMPT'
The current directory contains a set of shell scripts. Starting from the entry
script, follow the `source` dependencies until you reach the file that defines
a constant rather than sourcing anything further.

Report your answer and nothing else, as a single JSON object on the final line,
in exactly this form:

{"ordered_path":["<file stem>", "..."],"reported_hops":<integer>,"terminal_symbol":"<name>","terminal_value":"<value>"}

`ordered_path` lists every file you traversed in order, by stem (file name
without the .sh extension), beginning with the entry script and ending with the
terminal file. `reported_hops` is the number of source steps between them.
`terminal_symbol` and `terminal_value` are the constant defined in the terminal
file and the value assigned to it.
PROMPT
}

run_explore_gate() {
  local outdir="" ledger="" timeout_seconds=900 status
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_explore_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture sandbox prompt
  fixture=$(cd "$explore_runner_root/../../fixtures/explore-dependency-chain" && pwd)
  mkdir -p "$outdir"
  sandbox="$outdir/sandbox"
  rm -rf "$sandbox"
  mkdir -p "$sandbox"
  cp -R "$fixture/snapshot/." "$sandbox/"
  prompt="$outdir/prompt.txt"
  explore_request >"$prompt"

  local ledger_args=()
  [[ -n "$ledger" ]] && ledger_args=(--ledger "$ledger")

  set +e
  dispatch_fixture --outdir "$outdir/dispatch" --label explore-dependency-chain \
    --prompt-file "$prompt" --agent explore --workspace "$sandbox" \
    --timeout "$timeout_seconds" "${ledger_args[@]}" --attempt 1
  status=$?
  set -e

  set +e
  dispatch_extract_json "$outdir/dispatch" >"$outdir/reported.json" 2>/dev/null
  local parsed=$?
  set -e
  (( parsed == 0 )) || printf '{}\n' >"$outdir/reported.json"

  # Copy the model's own fields verbatim. No repair, no inference.
  python3 - "$outdir/reported.json" "$outdir/actual.json" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
reported = json.load(open(source, encoding="utf-8"))
document = {key: reported.get(key) for key in
            ("ordered_path", "reported_hops", "terminal_symbol", "terminal_value")}
document["runner_decides_gate_outcome"] = False
document["scorer"] = "eval/scoring/explore.sh::explore_gate"
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  rm -rf "$sandbox"
  return "$status"
}
