#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/select-activation-target.sh"
manifest="$root/manifests/phase-r-ground-truth.json"
python3 - "$manifest" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["targets"]["scout"] == {"model":"github-copilot/gpt-5.6-luna","variant":"low"}
assert d["targets"]["compaction"] == {"model":"github-copilot/gpt-5.6-terra","variant":"medium"}
assert "low/medium" not in json.dumps(d)
assert d["status"] == "READY"
assert d["reviewer_gate"]["required_detections"] == 5
assert d["reviewer_gate"]["allowed_clean_material_findings"] == 0
assert d["explore_gate"] == {"required_hops":4,"terminal_symbol":"PROTOCOL_VERSION","terminal_value":"v3"}
assert d["compaction_gate"] == {"required_preserved":4,"allowed_contradictions":0}
activation=d["activation"]
assert activation["scope"] == "user-global"
assert activation["root"] == "~/.config/opencode/"
assert activation["project_local"] is False
assert activation["repository_owned_installer"] is False
assert activation["both_files_action"] == "BLOCK"
assert activation["preserve_unrelated_configuration"] is True
assert activation["local_backup_required"] is True
assert activation["verify_effective_resolved_profile"] is True
PY
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
assert_eq "$w/opencode.jsonc" "$(select_activation_target "$w")"
touch "$w/opencode.json"; assert_eq "$w/opencode.json" "$(select_activation_target "$w")"
rm "$w/opencode.json"; touch "$w/opencode.jsonc"; assert_eq "$w/opencode.jsonc" "$(select_activation_target "$w")"
touch "$w/opencode.json"
if select_activation_target "$w" >/dev/null; then fail "accepted ambiguous activation root"; fi
printf 'PASS: Phase R targets and activation contract\n'
