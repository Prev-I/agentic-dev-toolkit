#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../../../../../.." && pwd)
eval_root="$repo/models/routing/opencode/eval"
fixture="$eval_root/fixtures/reviewer-seeded-defects"

source "$eval_root/scoring/reviewer.sh"
bash "$root/normalize-results.sh"

for key in astra sol61; do
  findings="$root/findings-$key.json"
  reviewer_structured_gate "$fixture/oracle.json" "$findings" >"$root/verdict-$key.txt"
  reviewer_structured_attribution "$fixture/oracle.json" "$findings" >"$root/attribution-$key.json"
done

printf 'Reviewer scoring complete; human adjudication must apply the preregistered outcomes.\n'
