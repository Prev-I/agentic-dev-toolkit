#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"

bundle=$(cd "$root/.." && pwd)
profile=$(mktemp)
trap 'rm -f "$profile"' EXIT
load_routing_profile "$bundle/opencode.jsonc" >"$profile"

python3 - "$profile" "$root/manifests/phase-r-routing-targets.json" "$bundle" "$root" <<'PY'
import json
import sys

profile_path, targets_path, bundle, eval_root = sys.argv[1:]
profile = json.load(open(profile_path, encoding="utf-8"))
targets = json.load(open(targets_path, encoding="utf-8"))
agents = profile.get("agent", {})
failures = []

def check(condition, message):
    if not condition:
        failures.append(message)

# 1. Every declared row is present with the exact declared model and variant.
check(len(targets["agents"]) == 11, "target manifest must declare exactly 11 agents")
for role, target in targets["agents"].items():
    row = agents.get(role)
    check(isinstance(row, dict), f"{role}: missing routing row")
    if not isinstance(row, dict):
        continue
    check(row.get("model") == target["model"],
          f"{role}: model {row.get('model')!r} != {target['model']!r}")
    check(row.get("variant") == target["variant"],
          f"{role}: variant {row.get('variant')!r} != {target['variant']!r}")
    if target["mode"] is not None:
        check(row.get("mode") == target["mode"],
              f"{role}: mode {row.get('mode')!r} != {target['mode']!r}")

# 2. No undeclared agent rows.
check(set(agents) == set(targets["agents"]),
      f"routing rows {sorted(set(agents) ^ set(targets['agents']))} differ from the declared target")

# 3. Default model.
check(profile.get("model") == targets["default_model"],
      f"default model {profile.get('model')!r} != {targets['default_model']!r}")

# 4. Forbidden model references anywhere in the production profile.
serialized = json.dumps(profile)
for forbidden in targets["forbidden_model_references"]:
    check(forbidden not in serialized,
          f"a production routing row still references {forbidden}")

# 5. The six migrated rows specifically.
for role in targets["risk_decision_rows"]:
    check("gpt-5.3-codex" not in json.dumps(agents.get(role, {})),
          f"{role}: migrated row still references gpt-5.3-codex")

# 6. Provider separation and effort separation.
check(agents.get("reviewer", {}).get("model", "").split("/")[0] == "github-copilot",
      "Reviewer provider is not GitHub Copilot")
check(agents.get("expert", {}).get("model", "").split("/")[0] == "openai",
      "Expert provider is not direct OpenAI")
check(agents.get("expert", {}).get("variant") != agents.get("reviewer", {}).get("variant"),
      "Expert effort must differ from Reviewer effort")

# 7. The explicitly forbidden effective state.
forbidden = targets["forbidden_effective_state"]
both_sol_high = (
    agents.get("reviewer", {}).get("model") == forbidden["reviewer"]["model"]
    and agents.get("reviewer", {}).get("variant") == forbidden["reviewer"]["variant"]
    and agents.get("expert", {}).get("model") == forbidden["expert"]["model"]
    and agents.get("expert", {}).get("variant") == forbidden["expert"]["variant"]
)
check(not both_sol_high, "forbidden state: Reviewer Sol high together with Expert Sol high")

# 8. Exact frozen variants.
check(agents.get("scout", {}).get("variant") == "low", "Scout variant must be exactly low")
check(agents.get("compaction", {}).get("variant") == "medium", "Compaction variant must be exactly medium")

# 9. Breakglass production invariants.
breakglass = agents.get("breakglass", {})
check(breakglass.get("mode") == "primary", "Breakglass mode must be primary")
check(breakglass.get("model") == "openai/gpt-5.6-sol", "Breakglass must be direct OpenAI Sol")
check(breakglass.get("variant") == "max", "Breakglass variant must be max")
for role, row in agents.items():
    if role == "breakglass":
        continue
    task = row.get("permission", {}).get("task")
    if task is None:
        continue
    denies_breakglass = task == "deny" or (isinstance(task, dict) and task.get("breakglass") == "deny")
    check(denies_breakglass,
          f"{role}: Task permission must deny breakglass explicitly")
top_task = profile.get("permission", {}).get("task")
check(isinstance(top_task, dict) and top_task.get("breakglass") == "deny",
      "top-level Task permission must deny breakglass")

# 10. Read-only boundaries preserved.
reviewer_permission = agents.get("reviewer", {}).get("permission", {})
check(reviewer_permission.get("edit") == "deny", "Reviewer must deny edit")
check(reviewer_permission.get("task") == "deny", "Reviewer must deny task")
expert_permission = agents.get("expert", {}).get("permission", {})
for boundary in ("edit", "bash", "task", "webfetch", "websearch"):
    check(expert_permission.get(boundary) == "deny", f"Expert must deny {boundary}")

# 11. plan's variant is backed by an executed Phase-0 capability record.
record = json.load(open(f"{eval_root}/{targets['plan_variant_capability_record'].split('eval/')[-1]}", encoding="utf-8"))
check(record.get("classification") == "USABLE" and record.get("variant") == targets["agents"]["plan"]["variant"],
      "plan variant is not backed by a USABLE Phase-0 capability record")

# 12. Single routing authority: markdown agents carry no routing fields.
check(targets["markdown_agents_carry_routing_fields"] is False,
      "target manifest must declare markdown agents free of routing fields")
for name in ("reviewer", "expert"):
    text = open(f"{bundle}/.opencode/agents/{name}.md", encoding="utf-8").read()
    frontmatter = text.split("---")[1]
    for field in ("model:", "variant:"):
        check(field not in frontmatter,
              f"{name}.md frontmatter must not carry {field} — routing lives in opencode.jsonc")

if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
PY

printf 'PASS: Phase R routing restoration invariants (11 agents)\n'
