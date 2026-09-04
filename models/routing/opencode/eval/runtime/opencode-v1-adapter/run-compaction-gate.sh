#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
compaction_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$compaction_runner_root/dispatch-fixture.sh"

compaction_request() {
  local corpus=$1
  cat <<'PROMPT'
Compact the conversation below. Discard low-value scheduling detail, superseded
naming proposals, and incidental discussion.

Every statement tagged with a bracketed invariant identifier is binding and must
survive your summary unchanged. Reproduce each one on its own line, keeping the
bracketed identifier and the value exactly as written:

[INV-EXAMPLE] key=value

Do not restate an invariant with a different value.

--- conversation ---
PROMPT
  cat "$corpus"
}

run_compaction_gate() {
  local outdir="" ledger="" timeout_seconds=900 status
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_compaction_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture prompt
  fixture=$(cd "$compaction_runner_root/../../fixtures/compaction-invariants" && pwd)
  mkdir -p "$outdir"
  prompt="$outdir/prompt.txt"
  compaction_request "$fixture/context.md" >"$prompt"

  local ledger_args=()
  [[ -n "$ledger" ]] && ledger_args=(--ledger "$ledger")

  set +e
  dispatch_fixture --outdir "$outdir/dispatch" --label compaction-invariants \
    --prompt-file "$prompt" --agent compaction \
    --timeout "$timeout_seconds" "${ledger_args[@]}" --attempt 1
  status=$?
  set -e

  cp "$outdir/dispatch/response.txt" "$outdir/summary.txt"

  # Extract the model's own tagged values verbatim. No repair, no lookup.
  # The identifier universe is discovered mechanically from the corpus's own
  # `[INV-...]` tags (names only, never their values) so an identifier the
  # model drops resolves to an explicit null rather than a missing key.
  python3 - "$fixture/context.md" "$outdir/summary.txt" "$outdir/actual.json" <<'PY'
import json
import re
import sys

corpus_path, source, destination = sys.argv[1:]
corpus_text = open(corpus_path, encoding="utf-8").read()
known_ids = sorted(set(re.findall(r"\[(INV-[A-Z0-9_-]+)\]", corpus_text)))

text = open(source, encoding="utf-8").read()
occurrences = {}
for identifier, value in re.findall(r"\[(INV-[A-Z0-9_-]+)\]\s*([^\n]*)", text):
    occurrences.setdefault(identifier, []).append(value.strip())

invariants = {identifier: None for identifier in known_ids}
for identifier, values in occurrences.items():
    invariants[identifier] = values[0]
contradictions = sorted(identifier for identifier, values in occurrences.items()
                        if len(set(values)) > 1)
document = {
    "invariants": invariants,
    "contradictions": contradictions,
    "occurrences": occurrences,
    "runner_decides_gate_outcome": False,
    "runner_repaired_output": False,
    "scorer": "eval/scoring/compaction.sh::compaction_structured_gate",
}
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  return "$status"
}
