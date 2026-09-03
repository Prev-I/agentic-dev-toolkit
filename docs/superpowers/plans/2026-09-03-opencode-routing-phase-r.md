# OpenCode V1 Multi-Model Routing Restoration (Phase R) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the nine Copilot-hosted routing rows, raise direct-OpenAI Expert from `high` to `xhigh`, install Breakglass as the eleventh production routing row, activate the complete profile in the user-global OpenCode configuration, and prove it against every committed Phase-R ground-truth gate.

**Architecture:** Routing becomes single-authority — all eleven rows live in the `agent` block of `models/routing/opencode/opencode.jsonc`, declared once in a committed target manifest that both the profile and every verifier compare against. The two custom agent markdown files keep their prompts and drop their `model:`/`variant:` frontmatter so no competing routing authority survives. Behavioral gate execution is built as **one shared dispatch primitive** over the existing OpenCode V1 runtime adapter, with four thin role adapters that select a fixture, construct a request, and normalize the result into the schema the **already-committed scorers** consume. Runners never decide pass/fail; the committed oracles, scorers and state machine do. Activation merges only routing-owned keys into the user-global JSONC after a fresh timestamped local backup, and effective routing is then verified through `opencode debug agent` from a neutral working directory.

**Tech Stack:** Bash (`set -Eeuo pipefail`, `IFS=$'\n\t'`), Python 3 standard library only, OpenCode V1 CLI `1.18.27`. No package manager, no build step, no new dependency.

**Spec:** `models/routing/opencode/docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md`

Supporting committed evidence this plan argues from:

- `models/routing/opencode/docs/evidence/2026-09-02-phase-0-capability-matrix.md`
- `models/routing/opencode/docs/evidence/2026-09-03-phase-0-readiness.md`
- `models/routing/opencode/docs/evidence/2026-09-03-phase-r-ground-truth-readiness.md`
- `models/routing/opencode/docs/evidence/2026-09-03-activation-preflight.md`
- `models/routing/opencode/eval/manifests/phase-r-ground-truth.json`
- `models/routing/opencode/eval/manifests/phase-0-budgets.json`

## Global Constraints

- **Repository:** all work happens inside `checkouts/agentic-dev-toolkit`. Never mix parent-workspace files into a commit here.
- **Branch:** `feat/opencode-routing-phase-r`, cut fresh from `main` at `092b760`. Do not reuse a Phase-0 or preflight branch.
- **Bash only.** Every script starts with `#!/usr/bin/env bash`, then `set -Eeuo pipefail`, then `IFS=$'\n\t'`.
- **Never begin a comment line with a linter name followed by a space** (`# shellcheck ` at line start silently disables analysis of the enclosing function).
- Shell scripts are tracked executable (`100755`); `*.sh` is pinned `eol=lf` in `.gitattributes`.
- **Dependency-free harness.** Bash plus the Python 3 standard library, matching the Phase-0 pattern. Do not introduce a framework or package to implement four thin adapters.
- **No secrets, tokens, credentials, global configuration contents, resolved-config dumps, or backup contents may be committed.**
- **Target runtime:** OpenCode V1, observed `1.18.27`. Record the observed version in every evidence artifact; never hardcode Phase 0's `1.18.26`.
- **Activation target is exactly** `~/.config/opencode/opencode.jsonc`. Expected real state: `~/.config/opencode/opencode.json` absent, `~/.config/opencode/opencode.jsonc` present with SHA-256 `b996dc7d596b164337aca23cf60e00d4c5dcc5e4852d7475bcab3a8f1cc15e32`. If that is no longer true, STOP; do not re-run normalization inside Phase R.
- **Probe syntax is frozen by Phase 0:** `opencode run --model <provider/model> --variant <variant> --format json "Reply with exactly: CAPABILITY_OK"`. Do not create a second probe system.
- **Phase-0 verified highest Opus 5 variant is `max`** (`eval/records/claude-opus-5-max.json`, classification `USABLE`). That is the exact value `plan` uses; never substitute a guessed "highest".
- **Budgets:** evaluation `100` credits, Phase-R recovery `250` credits (non-reclaimable by evaluation), organization guardrail `7600` credits/billing cycle. Credits derive as `observed_cost * 100` for GitHub Copilot USD provider-reported cost. Stop if the applicable budget would be exceeded; never lower a threshold to fit a budget.
- **Pricing regime:** Copilot GPT-5.6 Sol runs executed before `2026-09-04` are `promotional` and must not establish the canonical Reviewer steady-state cost reference.
- **Forward-only recovery.** Phase R has no supported rollback. Never restore Opus 4.6, never use Codex as an ordinary rollback, never create an undocumented hybrid.
- **Do not describe GPT-5.3-Codex as retired or unavailable.** The six non-capability-forced moves are an explicit risk decision.
- **Ground truth is frozen.** Fixtures, oracles, scorers, thresholds and the Build state machine are committed and must not be edited to make a model pass.
- **Scratch directory:** several tasks write non-committed working output to `$SCRATCH`. Export it once per shell session before running any task: `export SCRATCH=/tmp/claude-1000/-mnt-c-Users-previtalicl-source-repos-spec-driven-dev/5816a9e1-4142-4910-ae2d-f9de4929211d/scratchpad && mkdir -p "$SCRATCH"`. Nothing under `$SCRATCH` is ever committed.
- **Out of scope:** Phase 3 (Build Opus-vs-Sonnet A/B, Reviewer effort optimization, General challengers) and Phase 4 (Expert experiments). Do not modify Superpowers, OpenSpec, SpecRivet, branching conventions, the installer, or other toolkit features.

## Target Routing Profile — eleven production rows

Every value is copied from committed evidence, not from prose. This table is encoded once, declaratively, in `eval/manifests/phase-r-routing-targets.json` (Task 2); the profile, the invariant test, the capability preflight, the activation merge and the effective-routing verification all read that one manifest.

| Role | Provider / model | Variant | Mode | Migration class |
|---|---|---|---|---|
| `plan` | `github-copilot/claude-opus-5` | `max` | `primary` | capability-forced |
| `build` | `github-copilot/claude-opus-5` | `high` | `primary` | capability-forced |
| `general` | `github-copilot/gpt-5.6-terra` | `high` | — | capability-forced |
| `explore` | `github-copilot/gpt-5.6-luna` | `medium` | — | risk decision |
| `scout` | `github-copilot/gpt-5.6-luna` | `low` | — | risk decision |
| `reviewer` | `github-copilot/gpt-5.6-sol` | `high` | `subagent` | risk decision |
| `compaction` | `github-copilot/gpt-5.6-terra` | `medium` | — | risk decision |
| `title` | `github-copilot/gpt-5.6-luna` | `low` | — | risk decision |
| `summary` | `github-copilot/gpt-5.6-luna` | `low` | — | risk decision |
| `expert` | `openai/gpt-5.6-sol` | `xhigh` | `subagent` | Expert effort bump |
| `breakglass` | `openai/gpt-5.6-sol` | `max` | `primary` | decision §16 / §42.26 |

Default top-level `model`: `github-copilot/claude-opus-5`.

**Capability-forced** (`plan`, `build`, `general`): `github-copilot/claude-opus-4.6` failed the runtime capability check — `MODEL_UNRESOLVABLE` / `ProviderModelNotFoundError`.

**Risk decision** (`explore`, `scout`, `reviewer`, `compaction`, `title`, `summary`): explicit decision not to depend on GPT-5.3-Codex for the staged migration. Codex still resolved at the recorded capability check.

**Breakglass invariants**, enforced in the profile, in the effective resolved configuration, and in the security revalidation:

```
model    == openai/gpt-5.6-sol
variant  == max
mode     == primary
normal agents cannot Task-route to breakglass
explicit human primary selection remains supported
```

`hidden` is never treated as the security boundary. The security oracle stays what Phase 0 established: resolved permission rules plus agent inventory, never prompt behavior.

**Expert/Reviewer ordering invariant.** There must be no supported installed state where `Reviewer = Sol high` and `Expert = Sol high`. Expert reaches `xhigh` **atomically with** the Reviewer move: both rows land in the same commit (Task 7) and the same single activation write (Task 17). The invariant test and the effective-routing verifier both assert the forbidden state is absent.

## Ownership Boundaries

Authority must not leak across these lines. Every task below states which boundary it touches.

| Concern | Owning artifact | Rule |
|---|---|---|
| **Production routing** (role → provider/model/variant/mode/permissions) | `models/routing/opencode/opencode.jsonc`, `agent` block | Single source of truth. Nothing else may assign a model or variant. |
| **Declared routing target** | `eval/manifests/phase-r-routing-targets.json` | The one declarative statement of the eleven rows; the profile and all verifiers are checked against it. |
| **Agent prompts / instructions / non-routing metadata** | `.opencode/agents/reviewer.md`, `.opencode/agents/expert.md` | Prompt body, `mode`, `temperature`, `steps`, `hidden`, permissions. **No `model:`, no `variant:`.** |
| **Semantic routing policy** | `.opencode/model-routing.md` | When work goes to which role. Never a model assignment. |
| **Runtime dispatch mechanics** | `eval/runtime/opencode-v1-adapter/dispatch-fixture.sh` | OpenCode invocation, workspace setup, capture, timeout, exit status, runtime failure classification, provenance, cost/tokens/wall-clock, attempt identity, raw evidence preservation. |
| **Fixture-specific adaptation** | `run-build-restoration-gate.sh`, `run-reviewer-gate.sh`, `run-explore-gate.sh`, `run-compaction-gate.sh` | Select the committed fixture, construct the role request, call the shared primitive, normalize the result into the existing scorer input schema, persist evidence. **Never decides PASS/FAIL.** |
| **Ground truth** | `eval/fixtures/**` (`oracle.sh`, `oracle.json`, `ground-truth.json`, `fixture.json`) | Frozen. Committed before Phase R. Never edited to accommodate model output. |
| **Scoring / pass-fail** | `eval/scoring/*.sh`, `eval/decision-rules/build-gate.sh`, fixture `oracle.sh` | Sole authority on PASS/FAIL and on the Build 3→5 state machine. **Unmodified by Phase R.** |
| **Provenance** | `eval/runtime/opencode-v1-adapter/provenance.sh`, `budget-ledger.sh` | Run records, profile/commit/runtime identity, credit derivation and budget admission. |
| **Phase-R evidence** | `eval/records/phase-r/**`, `eval/manifests/phase-r-*.json`, `docs/evidence/2026-09-03-phase-r-execution.md` | Append-only outcome record. Never edited to change a result. |
| **Installed profile** | `eval/manifests/installed-profile.json` | What is actually installed on the workstation: profile id, source commit, install time, runtime version, target path, effective routing. |
| **Restored profile snapshot** | `profiles/v1-restored-2026-09.jsonc` | Created only after every gate passes. Forward quality/operational reference and rollback target for **later** phases. |
| **Historical baseline** | `profiles/baseline-2026-08.jsonc` | Written once in Task 3, never rewritten. Not a Phase-R rollback target. |

## Behavioral Gate Architecture

```
        existing OpenCode V1 runtime adapter
        (probe.sh, provenance.sh, capture-permissions.sh, budget-ledger.sh)
                              |
                              v
              dispatch-fixture.sh   <-- ONE shared execution primitive
        invocation | workspace | capture | timeout | exit status
        failure classification | provenance | cost/tokens | raw evidence
                              |
        +----------+----------+----------+-------------+
        |          |          |          |             |
   Build      Reviewer     Explore    Compaction   (thin adapters:
   adapter     adapter     adapter     adapter      fixture + request
        |          |          |          |          + normalization only)
        v          v          v          v
   oracle.sh   reviewer_    explore_   compaction_   <-- COMMITTED ORACLES
   + build_    structured_  gate       structured_       decide PASS/FAIL
     gate      gate                    gate
```

The adapters produce evidence. The committed oracles decide. No adapter contains a threshold, a hop count, a defect taxonomy, or a state-machine branch.

## Known Risks

1. **Eval budget headroom is tight.** A trivial Opus 5 probe reported `observed_cost` `0.1126975`, which the committed derivation turns into `11.27` credits. Three real multi-turn `build-restoration-gate` runs may consume a large fraction of the 100-credit evaluation budget. Every model-bearing run is preceded by a hard ledger admission check; exhaustion is a STOP, never a threshold reduction.
2. **Agent-block plus markdown merge semantics.** OpenCode V1 must be shown to produce **one** unambiguous effective definition when an `agent` block and a markdown file describe the same agent id. Task 7 verifies this with `opencode debug agent` (no model call) **before** relying on it. If the merge proves unsafe or ambiguous even after routing fields are removed, STOP and report the runtime contradiction; plan the smallest supported single-definition representation that preserves the markdown prompt rather than guessing around it.
3. **Reviewer detection normalization.** Each seeded case applies exactly one override to the clean snapshot, so the adapter normalizes "the severity the reviewer reported against the overridden file" into the scorer's input. The adapter invents no taxonomy and makes no detection ruling — `reviewer_structured_gate` compares detected IDs against `expected_ids`. Verbatim finding summaries are preserved in raw evidence so a human can audit that the reviewer found the seeded defect rather than an unrelated one. This limitation is stated in the evidence record.
4. **Comments are not preserved in the user-global file.** The activation merge rewrites `~/.config/opencode/opencode.jsonc` as generated JSONC with a provenance header. The fresh timestamped backup retains the original text verbatim. Accepted and stated.

## File Structure

**Created — shared runtime** (`models/routing/opencode/eval/runtime/opencode-v1-adapter/`)

| File | Responsibility |
|---|---|
| `load-routing-profile.sh` | Strip JSONC comments/trailing commas, emit strict JSON. The one parser. |
| `budget-ledger.sh` | Budget admission and credit accounting across evaluation and recovery accounts. |
| `classify-capability-failure.sh` | Map a probe/dispatch record to the Phase-0 failure taxonomy; isolate capability regression from transient/external causes. |
| `run-capability-preflight.sh` | Drive the existing `probe_model_variant` across the declared target manifest. |
| `dispatch-fixture.sh` | **The shared execution primitive.** All four gates dispatch through it. |
| `activate-profile.sh` | Back up the user-global JSONC, merge only routing-owned keys, write the activated file. |
| `verify-effective-routing.sh` | Resolve every role via `opencode debug agent` from a neutral cwd and from the repository; compare both against the target manifest. |

**Created — thin role adapters** (same directory)

`run-build-restoration-gate.sh`, `run-reviewer-gate.sh`, `run-explore-gate.sh`, `run-compaction-gate.sh`.

**Created — tests** (`models/routing/opencode/eval/tests/`)

`routing-loader-test.sh`, `routing-profile-test.sh`, `budget-ledger-test.sh`, `capability-preflight-test.sh`, `dispatch-fixture-test.sh`, `build-restoration-runner-test.sh`, `reviewer-runner-test.sh`, `explore-runner-test.sh`, `compaction-runner-test.sh`, `activation-merge-test.sh`, `effective-routing-test.sh`. Each is picked up automatically by the existing `eval/run-tests.sh` glob.

**Created — manifests and profiles**

`eval/manifests/phase-r-routing-targets.json`, `eval/manifests/phase-r-capability-preflight.json`, `profiles/baseline-2026-08.jsonc`, `profiles/v1-restored-2026-09.jsonc`.

**Modified**

`models/routing/opencode/opencode.jsonc`, `.opencode/agents/reviewer.md`, `.opencode/agents/expert.md`, `.opencode/model-routing.md`, `README.md`, `eval/manifests/installed-profile.json`.

**Unmodified by contract**

`eval/scoring/*.sh`, `eval/decision-rules/build-gate.sh`, `eval/fixtures/**`, `eval/thresholds/continuous.json`, `eval/run-tests.sh`, `environments/linux/install.sh`, `tests/install.sh`.

## Task Map

| # | Task | Boundary touched |
|---|---|---|
| 1 | Branch and JSONC routing loader | runtime dispatch (parsing) |
| 2 | Declare the 11-agent target manifest and routing invariants (RED) | declared target + verification |
| 3 | Preserve the historical baseline profile | historical record |
| 4 | Budget ledger | provenance |
| 5 | Capability failure classifier and preflight driver | runtime dispatch |
| 6 | Fresh runtime capability preflight (first model calls) | evidence |
| 7 | Centralize routing authority in `opencode.jsonc` | production routing + agent prompts |
| 8 | Shared OpenCode fixture-dispatch primitive | runtime dispatch |
| 9 | Build runner (thin adapter) | fixture adaptation |
| 10 | Reviewer runner (thin adapter) | fixture adaptation |
| 11 | Explore runner (thin adapter) | fixture adaptation |
| 12 | Compaction runner (thin adapter) | fixture adaptation |
| 13 | Activation tooling: backup and routing-owned merge | installed profile |
| 14 | Effective-routing verification tooling | verification |
| 15 | Pre-activation validation gate | verification |
| 16 | Activate the complete restored profile | installed profile |
| 17 | Verify effective routing and revalidate security boundaries | verification + evidence |
| 18 | Build restoration gate execution | evidence |
| 19 | Reviewer gate execution | evidence |
| 20 | Explore gate execution | evidence |
| 21 | Compaction gate execution | evidence |
| 22 | Budget, pricing and Phase-R evidence record | evidence |
| 23 | Establish `v1-restored-2026-09.jsonc` | restored profile snapshot |
| 24 | Independent review, verification-before-completion, PR | — |

---

### Task 1: Branch and the JSONC routing loader

Every later task reads the committed routing profile. `opencode.jsonc` carries `//` comments, so `json.load` cannot read it. This provides the one parser the whole plan uses.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh`
- Test: `models/routing/opencode/eval/tests/routing-loader-test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `load_routing_profile <jsonc-path>` — prints strict JSON on stdout, exits non-zero on malformed input. Sourced by Tasks 2, 5, 13, 14.

- [ ] **Step 1: Create the branch**

```bash
cd checkouts/agentic-dev-toolkit
git switch -c feat/opencode-routing-phase-r
git log -1 --oneline
```

Expected: branch created from `092b760 Merge pull request #7 ...`.

- [ ] **Step 2: Write the failing test**

Create `models/routing/opencode/eval/tests/routing-loader-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"
source "$root/runtime/opencode-v1-adapter/load-routing-profile.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

cat >"$workspace/sample.jsonc" <<'JSONC'
{
  // a line comment
  "model": "github-copilot/claude-opus-5",
  /* a block comment */
  "note": "a // slash inside a string is not a comment",
  "agent": {
    "plan": { "variant": "max" },
  }
}
JSONC

read_key() { load_routing_profile "$workspace/sample.jsonc" | python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }
assert_eq 'github-copilot/claude-opus-5' "$(read_key '["model"]')"
assert_eq 'a // slash inside a string is not a comment' "$(read_key '["note"]')"
assert_eq 'max' "$(read_key '["agent"]["plan"]["variant"]')"

printf '{ "broken": ' >"$workspace/broken.jsonc"
if load_routing_profile "$workspace/broken.jsonc" >/dev/null 2>&1; then
  fail "accepted malformed JSONC"
fi

load_routing_profile "$root/../opencode.jsonc" >/dev/null || fail "cannot load the committed routing profile"

printf 'PASS: JSONC routing loader\n'
```

- [ ] **Step 3: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/routing-loader-test.sh
```

Expected: `FAIL: missing file: .../load-routing-profile.sh`.

- [ ] **Step 4: Write the loader**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

load_routing_profile() {
  python3 - "$1" <<'PY'
import json
import re
import sys

raw = open(sys.argv[1], encoding="utf-8").read()
out = []
index = 0
size = len(raw)
in_string = False
escaped = False
while index < size:
    char = raw[index]
    if in_string:
        out.append(char)
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = False
        index += 1
        continue
    if char == '"':
        in_string = True
        out.append(char)
        index += 1
        continue
    if char == "/" and index + 1 < size and raw[index + 1] == "/":
        while index < size and raw[index] != "\n":
            index += 1
        continue
    if char == "/" and index + 1 < size and raw[index + 1] == "*":
        index += 2
        while index + 1 < size and not (raw[index] == "*" and raw[index + 1] == "/"):
            index += 1
        index += 2
        continue
    out.append(char)
    index += 1
text = re.sub(r",(\s*[}\]])", r"\1", "".join(out))
try:
    document = json.loads(text)
except json.JSONDecodeError as error:
    raise SystemExit(f"malformed JSONC: {error}")
json.dump(document, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
}
```

- [ ] **Step 5: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh \
         models/routing/opencode/eval/tests/routing-loader-test.sh
bash models/routing/opencode/eval/tests/routing-loader-test.sh
```

Expected: `PASS: JSONC routing loader`.

- [ ] **Step 6: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh \
        models/routing/opencode/eval/tests/routing-loader-test.sh
git commit -m "test(opencode): add JSONC routing profile loader"
```

---

### Task 2: Declare the 11-agent target and assert restoration invariants

Two artifacts, one deliverable: the declarative statement of the target, and the test that holds the profile to it. The test must fail against the pre-Phase-R routing — that is the §5 requirement.

**Files:**
- Create: `models/routing/opencode/eval/manifests/phase-r-routing-targets.json`
- Create: `models/routing/opencode/eval/tests/routing-profile-test.sh`

**Interfaces:**
- Consumes: `load_routing_profile` from Task 1.
- Produces: `phase-r-routing-targets.json` — the single declarative target read by Tasks 5, 7, 13, 14, 17.

- [ ] **Step 1: Write the target manifest**

Create `models/routing/opencode/eval/manifests/phase-r-routing-targets.json`:

```json
{
  "profile_id": "v1-restored-2026-09",
  "decision_reference": "docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md",
  "ground_truth_reference": "eval/manifests/phase-r-ground-truth.json",
  "default_model": "github-copilot/claude-opus-5",
  "agents": {
    "plan":       {"model": "github-copilot/claude-opus-5", "variant": "max",    "mode": "primary",  "migration_class": "capability-forced"},
    "build":      {"model": "github-copilot/claude-opus-5", "variant": "high",   "mode": "primary",  "migration_class": "capability-forced"},
    "general":    {"model": "github-copilot/gpt-5.6-terra", "variant": "high",   "mode": null,       "migration_class": "capability-forced"},
    "explore":    {"model": "github-copilot/gpt-5.6-luna",  "variant": "medium", "mode": null,       "migration_class": "risk-decision"},
    "scout":      {"model": "github-copilot/gpt-5.6-luna",  "variant": "low",    "mode": null,       "migration_class": "risk-decision"},
    "reviewer":   {"model": "github-copilot/gpt-5.6-sol",   "variant": "high",   "mode": "subagent", "migration_class": "risk-decision"},
    "compaction": {"model": "github-copilot/gpt-5.6-terra", "variant": "medium", "mode": null,       "migration_class": "risk-decision"},
    "title":      {"model": "github-copilot/gpt-5.6-luna",  "variant": "low",    "mode": null,       "migration_class": "risk-decision"},
    "summary":    {"model": "github-copilot/gpt-5.6-luna",  "variant": "low",    "mode": null,       "migration_class": "risk-decision"},
    "expert":     {"model": "openai/gpt-5.6-sol",           "variant": "xhigh",  "mode": "subagent", "migration_class": "expert-effort-bump"},
    "breakglass": {"model": "openai/gpt-5.6-sol",           "variant": "max",    "mode": "primary",  "migration_class": "decision-16-42-26"}
  },
  "capability_forced_rows": ["plan", "build", "general"],
  "capability_forced_reason": "github-copilot/claude-opus-4.6 MODEL_UNRESOLVABLE / ProviderModelNotFoundError",
  "risk_decision_rows": ["explore", "scout", "reviewer", "compaction", "title", "summary"],
  "risk_decision_reason": "explicit decision not to depend on GPT-5.3-Codex for the staged migration; Codex still resolved at the recorded capability check",
  "forbidden_model_references": ["claude-opus-4.6", "gpt-5.3-codex"],
  "forbidden_effective_state": {
    "description": "Reviewer and Expert must not both be Sol at effort high",
    "reviewer": {"model": "github-copilot/gpt-5.6-sol", "variant": "high"},
    "expert": {"model": "openai/gpt-5.6-sol", "variant": "high"}
  },
  "routing_authority": "opencode.jsonc agent block",
  "markdown_agents_carry_routing_fields": false,
  "plan_variant_capability_record": "eval/records/claude-opus-5-max.json"
}
```

- [ ] **Step 2: Write the failing invariants test**

Create `models/routing/opencode/eval/tests/routing-profile-test.sh`:

```bash
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
    check(isinstance(task, dict) and task.get("breakglass") == "deny",
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
```

- [ ] **Step 3: Run it and capture the expected pre-restoration failures**

```bash
chmod +x models/routing/opencode/eval/tests/routing-profile-test.sh
SCRATCH=/tmp/claude-1000/-mnt-c-Users-previtalicl-source-repos-spec-driven-dev/5816a9e1-4142-4910-ae2d-f9de4929211d/scratchpad
mkdir -p "$SCRATCH"
bash models/routing/opencode/eval/tests/routing-profile-test.sh 2>&1 | tee "$SCRATCH/phase-r-red.txt"
```

Expected: exit 1. The output must name at minimum:

```
FAIL: plan: model 'github-copilot/claude-opus-4.6' != 'github-copilot/claude-opus-5'
FAIL: build: model 'github-copilot/claude-opus-4.6' != 'github-copilot/claude-opus-5'
FAIL: general: model 'github-copilot/claude-opus-4.6' != 'github-copilot/gpt-5.6-terra'
FAIL: explore: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-luna'
FAIL: scout: variant 'high' != 'low'
FAIL: reviewer: missing routing row
FAIL: expert: missing routing row
FAIL: breakglass: missing routing row
FAIL: compaction: variant None != 'medium'
FAIL: a production routing row still references claude-opus-4.6
FAIL: a production routing row still references gpt-5.3-codex
FAIL: top-level Task permission must deny breakglass
FAIL: reviewer.md frontmatter must not carry model:
FAIL: expert.md frontmatter must not carry model:
```

These are the required §5 pre-restoration failure reasons. Keep `phase-r-red.txt`; it is quoted in the Phase-R evidence record in Task 22.

- [ ] **Step 4: Confirm no other test regressed**

`run-tests.sh` has no `|| true` and aborts at the first failure, so check the rest explicitly:

```bash
for t in models/routing/opencode/eval/tests/*-test.sh; do
  case "$t" in *routing-profile-test.sh) continue;; esac
  bash "$t" || echo "UNEXPECTED FAILURE: $t"
done
```

Expected: all `PASS:` lines, no `UNEXPECTED FAILURE`.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/manifests/phase-r-routing-targets.json \
        models/routing/opencode/eval/tests/routing-profile-test.sh
git commit -m "test(opencode): assert Phase R 11-agent routing restoration"
```

---

### Task 3: Preserve the historical baseline profile

Decision §30 and §42.6 require a preserved row-level historical record. It does not exist yet. Capture it while `opencode.jsonc` still holds the pre-Phase-R rows.

**Files:**
- Create: `models/routing/opencode/profiles/baseline-2026-08.jsonc`

**Interfaces:**
- Consumes: the unmodified `models/routing/opencode/opencode.jsonc`.
- Produces: a historical artifact. Never rewritten by any later task.

- [ ] **Step 1: Copy the pre-Phase-R profile verbatim**

```bash
mkdir -p models/routing/opencode/profiles
cp models/routing/opencode/opencode.jsonc models/routing/opencode/profiles/baseline-2026-08.jsonc
```

- [ ] **Step 2: Prepend the dated row-level status header**

Insert this block at the very top of `models/routing/opencode/profiles/baseline-2026-08.jsonc`, above the existing first line:

```jsonc
// HISTORICAL RECORD — DO NOT EDIT, DO NOT ACTIVATE.
//
// The published OpenCode V1 routing profile as it stood before Phase R.
// Preserved under decision V3.4.3 §30 and §42.6. Superseded by
// profiles/v1-restored-2026-09.jsonc once Phase R passes. This file is NOT a
// Phase-R rollback target: Phase R has no supported rollback.
//
// Row-level status at the recorded capability check:
//
//   plan        Opus 4.6        MODEL_UNRESOLVABLE / ProviderModelNotFoundError
//   build       Opus 4.6        MODEL_UNRESOLVABLE / ProviderModelNotFoundError
//   general     Opus 4.6        MODEL_UNRESOLVABLE / ProviderModelNotFoundError
//
//   explore     GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//   scout       GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//   reviewer    GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//   compaction  GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//   title       GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//   summary     GPT-5.3-Codex   resolves; abandoned by explicit risk decision
//
//   expert      openai/gpt-5.6  working before-state, effort high
//   breakglass  absent          not present in the pre-Phase-R production profile
//
// Codex is NOT retired and NOT globally unavailable. The six moves above are a
// recorded risk decision, not a capability finding.
```

- [ ] **Step 3: Verify it still parses and still describes the old profile**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh
load_routing_profile models/routing/opencode/profiles/baseline-2026-08.jsonc \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"]); print(d["agent"]["explore"]["model"])'
```

Expected:
```
github-copilot/claude-opus-4.6
github-copilot/gpt-5.3-codex
```

- [ ] **Step 4: Confirm the invariant test does not scan the baseline**

```bash
grep -n 'profiles/' models/routing/opencode/eval/tests/routing-profile-test.sh || echo "baseline not scanned (correct)"
```

Expected: `baseline not scanned (correct)`. The historical record legitimately contains the forbidden strings; only `opencode.jsonc` is the production routing artifact under test.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/profiles/baseline-2026-08.jsonc
git commit -m "docs(opencode): preserve pre-Phase-R routing baseline"
```

---

### Task 4: Budget ledger

Every model-bearing run from Task 6 onward must be refused if it would push the applicable budget past its cap. Build this before anything spends.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh`
- Test: `models/routing/opencode/eval/tests/budget-ledger-test.sh`

**Interfaces:**
- Consumes: `derive_copilot_credits` from the existing `provenance.sh`.
- Produces:
  - `ledger_init <ledger.json> <budgets.json>` — create the ledger from the committed budgets.
  - `ledger_spent <ledger.json> <account>` — credits spent on `evaluation` or `recovery`.
  - `ledger_admit <ledger.json> <account> <projected-credits> [--reclaim-recovery]` — exit 0 if the run may proceed; always exit 1 for `--reclaim-recovery`.
  - `ledger_append <ledger.json> <account> <label> <provider> <credits>` — append one entry.
  - `ledger_credits_from_cost <provider> <cost>` — `null` for non-Copilot providers.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/budget-ledger-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"

ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
assert_eq '0' "$(ledger_spent "$ledger" evaluation)"
assert_eq '0' "$(ledger_spent "$ledger" recovery)"

ledger_admit "$ledger" evaluation 40 || fail "rejected a run inside the evaluation budget"
ledger_append "$ledger" evaluation preflight-plan github-copilot 40
assert_eq '40' "$(ledger_spent "$ledger" evaluation)"

ledger_admit "$ledger" evaluation 60 || fail "rejected a run that exactly fills the budget"
ledger_append "$ledger" evaluation build-run-1 github-copilot 60
assert_eq '100' "$(ledger_spent "$ledger" evaluation)"

if ledger_admit "$ledger" evaluation 1; then
  fail "admitted a run that would exceed the 100-credit evaluation budget"
fi
if ledger_admit "$ledger" evaluation 1 --reclaim-recovery; then
  fail "allowed evaluation to reclaim the non-reclaimable recovery budget"
fi

ledger_admit "$ledger" recovery 250 || fail "rejected a run inside the recovery budget"
ledger_append "$ledger" recovery bisect-build github-copilot 250
if ledger_admit "$ledger" recovery 1; then
  fail "admitted a run that would exceed the 250-credit recovery budget"
fi

assert_eq 'null' "$(ledger_credits_from_cost openai 0.5)"
assert_eq 'null' "$(ledger_credits_from_cost github-copilot null)"
assert_eq '50.0' "$(ledger_credits_from_cost github-copilot 0.5)"

assert_contains "$(<"$ledger")" '"recovery_reclaimable_for_eval": false'
assert_contains "$(<"$ledger")" '"organization_guardrail_credits": 7600'

printf 'PASS: Phase R budget ledger\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/budget-ledger-test.sh
```

Expected: `FAIL: missing file: .../budget-ledger.sh`.

- [ ] **Step 3: Write the ledger**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ledger_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ledger_root/provenance.sh"

ledger_init() {
  local ledger=$1 budgets=$2
  [[ -f "$ledger" ]] && return 0
  python3 - "$ledger" "$budgets" <<'PY'
import json
import sys

ledger_path, budgets_path = sys.argv[1:]
budgets = json.load(open(budgets_path, encoding="utf-8"))
document = {
    "caps": {
        "evaluation": budgets["eval_budget_credits"],
        "recovery": budgets["phase_r_recovery_budget_credits"],
    },
    "recovery_reclaimable_for_eval": budgets["recovery_budget_reclaimable_for_eval"],
    "organization_guardrail_credits": budgets["organizational_user_guardrail_credits"],
    "at_guardrail": budgets["at_guardrail"],
    "entries": [],
}
with open(ledger_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

ledger_spent() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

ledger, account = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
total = sum(entry["credits"] for entry in document["entries"] if entry["account"] == account)
print(int(total) if float(total).is_integer() else total)
PY
}

ledger_admit() {
  local ledger=$1 account=$2 projected=$3 reclaim=${4:-}
  [[ "$reclaim" != "--reclaim-recovery" ]] || return 1
  python3 - "$ledger" "$account" "$projected" <<'PY'
import json
import sys

ledger, account, projected = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
cap = document["caps"][account]
spent = sum(entry["credits"] for entry in document["entries"] if entry["account"] == account)
raise SystemExit(0 if spent + float(projected) <= cap else 1)
PY
}

ledger_append() {
  local ledger=$1 account=$2 label=$3 provider=$4 credits=$5
  python3 - "$ledger" "$account" "$label" "$provider" "$credits" <<'PY'
import datetime
import json
import sys

ledger, account, label, provider, credits = sys.argv[1:]
document = json.load(open(ledger, encoding="utf-8"))
document["entries"].append({
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "account": account,
    "label": label,
    "provider": provider,
    "credits": float(credits),
})
with open(ledger, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

ledger_credits_from_cost() {
  local provider=$1 cost=$2
  [[ -n "$cost" && "$cost" != null ]] || { printf 'null\n'; return; }
  derive_copilot_credits "$provider" USD copilot_provider_reported "$cost"
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh \
         models/routing/opencode/eval/tests/budget-ledger-test.sh
bash models/routing/opencode/eval/tests/budget-ledger-test.sh
```

Expected: `PASS: Phase R budget ledger`.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh \
        models/routing/opencode/eval/tests/budget-ledger-test.sh
git commit -m "test(opencode): add Phase R budget ledger"
```

---

### Task 5: Capability failure classifier and preflight driver

The external catalog can change after Phase 0. This builds the driver that re-probes every declared target using the **existing** `probe_model_variant`, and the classifier that separates a genuine capability regression (STOP Phase R) from a transient or external failure (do not retry until green).

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/classify-capability-failure.sh`
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-capability-preflight.sh`
- Test: `models/routing/opencode/eval/tests/capability-preflight-test.sh`

**Interfaces:**
- Consumes: `probe_model_variant` from `probe.sh`; `ledger_append`/`ledger_credits_from_cost` from Task 4; `phase-r-routing-targets.json` from Task 2.
- Produces:
  - `classify_capability_failure <record.json>` — one of `MODEL_UNRESOLVABLE`, `MODEL_UNAVAILABLE`, `POLICY_DENIED`, `QUOTA_FAILURE`, `AUTH_FAILURE`, `NETWORK_FAILURE`, `PROVIDER_FAILURE`, `UNCLASSIFIED`.
  - `capability_stop_class <classification>` — `CAPABILITY_REGRESSION` or `TRANSIENT_OR_EXTERNAL`.
  - `preflight_targets <targets-manifest.json>` — `role model variant` lines, in declared order.
  - `run_capability_preflight <output-dir> <manifest-out> <ledger> <targets-manifest>` — exit 0 only when all eleven are `USABLE`.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/capability-preflight-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/classify-capability-failure.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-capability-preflight.sh"
source "$root/runtime/opencode-v1-adapter/classify-capability-failure.sh"
source "$root/runtime/opencode-v1-adapter/run-capability-preflight.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
emit() { printf '%s\n' "$2" >"$workspace/$1"; }

emit unresolvable.json '{"error_text":"ProviderModelNotFoundError: model github-copilot/claude-opus-4.6 not found"}'
assert_eq 'MODEL_UNRESOLVABLE' "$(classify_capability_failure "$workspace/unresolvable.json")"

emit unavailable.json '{"error_text":"model is not available for this account"}'
assert_eq 'MODEL_UNAVAILABLE' "$(classify_capability_failure "$workspace/unavailable.json")"

emit policy.json '{"error_text":"blocked by organization policy"}'
assert_eq 'POLICY_DENIED' "$(classify_capability_failure "$workspace/policy.json")"

emit quota.json '{"error_text":"usage limit has been reached","status_code":429}'
assert_eq 'QUOTA_FAILURE' "$(classify_capability_failure "$workspace/quota.json")"

emit auth.json '{"error_text":"unauthorized: invalid_api_key"}'
assert_eq 'AUTH_FAILURE' "$(classify_capability_failure "$workspace/auth.json")"

emit network.json '{"error_text":"connection timeout"}'
assert_eq 'NETWORK_FAILURE' "$(classify_capability_failure "$workspace/network.json")"

emit provider.json '{"error_text":"service unavailable","status_code":503}'
assert_eq 'PROVIDER_FAILURE' "$(classify_capability_failure "$workspace/provider.json")"

emit odd.json '{"error_text":"something else entirely"}'
assert_eq 'UNCLASSIFIED' "$(classify_capability_failure "$workspace/odd.json")"

assert_eq 'CAPABILITY_REGRESSION' "$(capability_stop_class MODEL_UNRESOLVABLE)"
assert_eq 'CAPABILITY_REGRESSION' "$(capability_stop_class MODEL_UNAVAILABLE)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class QUOTA_FAILURE)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class POLICY_DENIED)"
assert_eq 'TRANSIENT_OR_EXTERNAL' "$(capability_stop_class UNCLASSIFIED)"

targets=$(preflight_targets "$root/manifests/phase-r-routing-targets.json")
assert_eq '11' "$(printf '%s\n' "$targets" | grep -c .)"
assert_eq 'plan github-copilot/claude-opus-5 max' "$(printf '%s\n' "$targets" | head -1)"
assert_contains "$targets" 'breakglass openai/gpt-5.6-sol max'
assert_contains "$targets" 'scout github-copilot/gpt-5.6-luna low'
assert_contains "$targets" 'compaction github-copilot/gpt-5.6-terra medium'
assert_contains "$targets" 'expert openai/gpt-5.6-sol xhigh'
assert_contains "$targets" 'reviewer github-copilot/gpt-5.6-sol high'

printf 'PASS: Phase R capability preflight\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/capability-preflight-test.sh
```

Expected: `FAIL: missing file: .../classify-capability-failure.sh`.

- [ ] **Step 3: Write the classifier**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/classify-capability-failure.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

classify_capability_failure() {
  python3 - "$1" <<'PY'
import json
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
message = str(record.get("error_text") or "").lower()
status = record.get("status_code")

RESOLUTION = ("providermodelnotfounderror", "model not found", "unknown model",
              "no such model", "not found")
UNAVAILABLE = ("not available", "unavailable for", "model is disabled",
               "model has been retired")
POLICY = ("organization policy", "policy denied", "blocked by policy",
          "disabled by your organization")
QUOTA = ("usage limit", "rate limit", "quota", "too many requests")
AUTH = ("unauthorized", "invalid_api_key", "authentication", "forbidden")
NETWORK = ("timeout", "network", "connection", "dns", "econnreset")
PROVIDER = ("service unavailable", "provider unavailable", "bad gateway",
            "internal server error")

def hit(markers):
    return any(marker in message for marker in markers)

if hit(RESOLUTION):
    result = "MODEL_UNRESOLVABLE"
elif hit(UNAVAILABLE):
    result = "MODEL_UNAVAILABLE"
elif hit(POLICY):
    result = "POLICY_DENIED"
elif hit(QUOTA) or status == 429:
    result = "QUOTA_FAILURE"
elif hit(AUTH) or status in (401, 403):
    result = "AUTH_FAILURE"
elif hit(NETWORK):
    result = "NETWORK_FAILURE"
elif hit(PROVIDER) or status in (500, 502, 503, 504):
    result = "PROVIDER_FAILURE"
else:
    result = "UNCLASSIFIED"
print(result)
PY
}

capability_stop_class() {
  case "$1" in
    MODEL_UNRESOLVABLE|MODEL_UNAVAILABLE) printf 'CAPABILITY_REGRESSION\n' ;;
    *) printf 'TRANSIENT_OR_EXTERNAL\n' ;;
  esac
}
```

- [ ] **Step 4: Write the preflight driver**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-capability-preflight.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
preflight_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$preflight_root/probe.sh"
source "$preflight_root/classify-capability-failure.sh"
source "$preflight_root/budget-ledger.sh"

preflight_targets() {
  python3 - "$1" <<'PY'
import json
import sys

ORDER = ["plan", "build", "general", "explore", "scout", "reviewer",
         "compaction", "title", "summary", "expert", "breakglass"]
agents = json.load(open(sys.argv[1], encoding="utf-8"))["agents"]
for role in ORDER:
    row = agents[role]
    print(role, row["model"], row["variant"])
PY
}

run_capability_preflight() {
  local output_dir=$1 manifest=$2 ledger=$3 targets=$4
  mkdir -p "$output_dir"
  local role model variant record status classification stop_class credits cost
  while read -r role model variant; do
    [[ -n "$role" ]] || continue
    record="$output_dir/${role}.json"
    set +e
    probe_model_variant "$model" "$variant" "$record"
    status=$?
    set -e
    if (( status == 0 )); then
      classification=USABLE
      stop_class=NONE
    else
      classification=$(classify_capability_failure "$record")
      stop_class=$(capability_stop_class "$classification")
    fi
    cost=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_cost"])' "$record")
    credits=$(ledger_credits_from_cost "${model%%/*}" "$cost")
    [[ "$credits" == null ]] || ledger_append "$ledger" evaluation "preflight-$role" "${model%%/*}" "$credits"
    ROLE="$role" CLASSIFICATION="$classification" STOP_CLASS="$stop_class" CREDITS="$credits" \
      python3 - "$record" <<'PY'
import json
import os
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
record["role"] = os.environ["ROLE"]
record["phase_r_classification"] = os.environ["CLASSIFICATION"]
record["phase_r_stop_class"] = os.environ["STOP_CLASS"]
record["derived_credits"] = None if os.environ["CREDITS"] == "null" else float(os.environ["CREDITS"])
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2)
    handle.write("\n")
PY
  done < <(preflight_targets "$targets")

  python3 - "$manifest" "$output_dir" "$targets" <<'PY'
import datetime
import glob
import json
import os
import sys

manifest_path, output_dir, targets_path = sys.argv[1:]
declared = json.load(open(targets_path, encoding="utf-8"))["agents"]
rows = []
for path in sorted(glob.glob(os.path.join(output_dir, "*.json"))):
    record = json.load(open(path, encoding="utf-8"))
    rows.append({
        "role": record["role"],
        "provider": record["provider"],
        "model": record["model"],
        "variant": record["variant"],
        "classification": record["phase_r_classification"],
        "stop_class": record["phase_r_stop_class"],
        "pricing_regime": record["pricing_regime"],
        "observed_cost": record["observed_cost"],
        "derived_credits": record["derived_credits"],
        "wall_clock_ms": record["wall_clock_ms"],
        "runtime_version": record["runtime_version"],
        "exact_invocation": record["exact_invocation"],
    })
covered = {row["role"] for row in rows}
missing = sorted(set(declared) - covered)
regressions = [row for row in rows if row["stop_class"] == "CAPABILITY_REGRESSION"]
transient = [row for row in rows if row["stop_class"] == "TRANSIENT_OR_EXTERNAL"]
if missing:
    status = "INCOMPLETE"
elif regressions:
    status = "CAPABILITY_REGRESSION"
elif transient:
    status = "BLOCKED_TRANSIENT"
else:
    status = "PASS"
document = {
    "captured_at": datetime.datetime.now().astimezone().isoformat(),
    "phase": "R-capability-preflight",
    "probe_mechanism": "eval/runtime/opencode-v1-adapter/probe.sh",
    "second_probe_system_created": False,
    "status": status,
    "missing_roles": missing,
    "targets": rows,
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if status == "PASS" else 1)
PY
}
```

- [ ] **Step 5: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/classify-capability-failure.sh \
         models/routing/opencode/eval/runtime/opencode-v1-adapter/run-capability-preflight.sh \
         models/routing/opencode/eval/tests/capability-preflight-test.sh
bash models/routing/opencode/eval/tests/capability-preflight-test.sh
```

Expected: `PASS: Phase R capability preflight`. No model was called — `preflight_targets` reads the manifest, and every classifier case uses a fabricated record.

- [ ] **Step 6: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/classify-capability-failure.sh \
        models/routing/opencode/eval/runtime/opencode-v1-adapter/run-capability-preflight.sh \
        models/routing/opencode/eval/tests/capability-preflight-test.sh
git commit -m "test(opencode): add Phase R capability preflight driver"
```

---

### Task 6: Fresh runtime capability preflight (first model calls)

The §4 gate: revalidate every declared target against the live catalog **before** the routing change. This is the first task that spends credits.

**Files:**
- Create: `models/routing/opencode/eval/manifests/phase-r-capability-preflight.json`
- Create: `models/routing/opencode/eval/records/phase-r/preflight/*.json`
- Create: `models/routing/opencode/eval/records/phase-r/budget-ledger.json`

**Interfaces:**
- Consumes: `run_capability_preflight`, `ledger_init` from Tasks 4–5.
- Produces: the preflight manifest read by Task 22's evidence record.

- [ ] **Step 1: Record the runtime version and confirm the workstation state**

```bash
opencode --version
ls ~/.config/opencode/opencode.json 2>/dev/null && echo "STOP: opencode.json present" || echo "opencode.json absent (correct)"
sha256sum ~/.config/opencode/opencode.jsonc
for v in OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR; do printf '%s=%s\n' "$v" "${!v-<unset>}"; done
```

Expected: `1.18.27`; `opencode.json absent (correct)`; SHA-256 `b996dc7d596b164337aca23cf60e00d4c5dcc5e4852d7475bcab3a8f1cc15e32`; all three variables `<unset>`. Any deviation is a **STOP** — do not normalize configuration inside Phase R.

- [ ] **Step 2: Initialize the ledger**

```bash
mkdir -p models/routing/opencode/eval/records/phase-r/preflight
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger_init models/routing/opencode/eval/records/phase-r/budget-ledger.json \
            models/routing/opencode/eval/manifests/phase-0-budgets.json
cat models/routing/opencode/eval/records/phase-r/budget-ledger.json
```

Expected: caps `evaluation: 100`, `recovery: 250`, `recovery_reclaimable_for_eval: false`, `organization_guardrail_credits: 7600`.

- [ ] **Step 3: Run the preflight**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-capability-preflight.sh
set +e
run_capability_preflight \
  models/routing/opencode/eval/records/phase-r/preflight \
  models/routing/opencode/eval/manifests/phase-r-capability-preflight.json \
  models/routing/opencode/eval/records/phase-r/budget-ledger.json \
  models/routing/opencode/eval/manifests/phase-r-routing-targets.json
echo "exit=$?"
set -e
```

Expected on success: `exit=0`, manifest `status: "PASS"`, eleven `USABLE` rows.

- [ ] **Step 4: Read the result and apply the STOP rules**

```bash
python3 -c '
import json
m = json.load(open("models/routing/opencode/eval/manifests/phase-r-capability-preflight.json"))
print("status:", m["status"])
for row in m["targets"]:
    print(f"{row[\"role\"]:11} {row[\"provider\"]}/{row[\"model\"]:18} {row[\"variant\"]:7} {row[\"classification\"]:20} {row[\"stop_class\"]}")
'
```

Apply exactly:

- Any row `stop_class: CAPABILITY_REGRESSION` (`MODEL_UNRESOLVABLE` / `MODEL_UNAVAILABLE`): **STOP Phase R.** Commit the preserved evidence, report the capability regression naming the role, model, variant and exact error. **Do not substitute another model.** Do not proceed to Task 7.
- Any row `stop_class: TRANSIENT_OR_EXTERNAL` (quota, auth, network, provider, policy, unclassified): **do not retry until green.** Record the classification, report the blocked state, stop the normal sequence. A retry is permitted only after the external cause is independently resolved, and every attempt is recorded.
- All eleven `USABLE`: proceed.

- [ ] **Step 5: Check budget headroom before committing to the Build gate**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
spent=$(ledger_spent models/routing/opencode/eval/records/phase-r/budget-ledger.json evaluation)
echo "evaluation spent: $spent / 100"
python3 -c "import sys; print('HEADROOM OK' if float('$spent') <= 40 else 'WARNING: three Opus build runs may not fit — report before Task 18')"
```

If the warning fires, report it to the human before proceeding. A tight budget is a STOP condition later, never a reason to weaken a gate.

- [ ] **Step 6: Commit the evidence**

```bash
git add models/routing/opencode/eval/manifests/phase-r-capability-preflight.json \
        models/routing/opencode/eval/records/phase-r/
git commit -m "test(opencode): record Phase R capability preflight"
```

---

### Task 7: Centralize routing authority in `opencode.jsonc`

The nine Copilot rows, the Expert bump and Breakglass are **one logical transition**. Do not commit a partial routing profile. This task also eliminates the competing routing authority in the agent markdown files.

**Files:**
- Modify: `models/routing/opencode/opencode.jsonc` (full rewrite)
- Modify: `models/routing/opencode/.opencode/agents/reviewer.md` (frontmatter only)
- Modify: `models/routing/opencode/.opencode/agents/expert.md` (frontmatter + Availability section)
- Modify: `models/routing/opencode/.opencode/model-routing.md`
- Modify: `models/routing/opencode/README.md`

**Interfaces:**
- Consumes: `phase-r-routing-targets.json` from Task 2.
- Produces: the target routing profile read by Tasks 13, 14, 16, 17, 23.

- [ ] **Step 1: Verify OpenCode V1 merge semantics before relying on them**

Before removing routing fields, prove the runtime produces **one** unambiguous definition when an `agent` block and a markdown file describe the same id. This uses `opencode debug agent` only — no model call, no credits.

```bash
probe=$(mktemp -d)
mkdir -p "$probe/.opencode/agents"
cat >"$probe/.opencode/agents/reviewer.md" <<'MD'
---
description: probe reviewer
mode: subagent
temperature: 0.1
permission:
  edit: deny
  task: deny
---
PROBE_PROMPT_BODY
MD
cfg='{"agent":{"reviewer":{"mode":"subagent","model":"github-copilot/gpt-5.6-sol","variant":"high","permission":{"edit":"deny","task":"deny"}}}}'
( cd "$probe" && OPENCODE_CONFIG_CONTENT="$cfg" opencode debug agent reviewer ) \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); m=d.get("model",{}); print("name:",d.get("name")); print("mode:",d.get("mode")); print("model:",f"{m.get(\"providerID\")}/{m.get(\"modelID\")}"); print("variant:",d.get("variant")); print("prompt_retained:", "PROBE_PROMPT_BODY" in json.dumps(d))'
rm -rf "$probe"
```

Expected: exactly one resolved definition with `model: github-copilot/gpt-5.6-sol`, `variant: high`, `mode: subagent`, and the markdown prompt retained.

**STOP condition:** if the runtime returns an ambiguous or duplicated definition, drops the markdown prompt, or resolves a model other than the config's, **do not guess around it.** Record the observed runtime contradiction verbatim in `docs/evidence/2026-09-03-phase-r-execution.md`, report it, and plan the smallest supported single-definition representation that preserves the markdown prompt content before continuing.

- [ ] **Step 2: Rewrite the routing profile**

Replace the entire contents of `models/routing/opencode/opencode.jsonc` with:

```jsonc
{
  // OpenCode V1 multi-model routing configuration — restored profile.
  //
  // Merge this fragment into an existing project or global configuration.
  // Do not replace unrelated configuration, and append to an existing
  // instructions array rather than replacing it.
  //
  // Restored by Phase R of the approved routing decision at
  // docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md.
  // The declared target is eval/manifests/phase-r-routing-targets.json.
  //
  // Capability-forced rows (Opus 4.6 was MODEL_UNRESOLVABLE):
  //   plan, build, general
  // Rows migrated by explicit risk decision (Codex still resolved):
  //   explore, scout, reviewer, compaction, title, summary
  //
  // THIS FILE IS THE SINGLE AUTHORITY for role -> model/variant/mode.
  // .opencode/agents/*.md carry prompts and non-routing metadata only.
  "$schema": "https://opencode.ai/config.json",

  // Append this entry to any instructions already configured.
  "instructions": [
    ".opencode/model-routing.md"
  ],

  // Baseline model applied when no agent override matches.
  "model": "github-copilot/claude-opus-5",

  "permission": {
    // Web search via Exa AI — requires OPENCODE_ENABLE_EXA=true in the environment.
    "websearch": "allow",

    // Breakglass is never reachable through ordinary Task delegation.
    // This deny rule is the security control; `hidden` is not one.
    "task": {
      "*": "allow",
      "breakglass": "deny"
    }
  },

  "agent": {
    // ── Primary work agents ────────────────────────────────────────

    "plan": {
      // Architectural planning and task decomposition.
      // Variant `max` is the Phase-0 verified highest supported Opus effort
      // (eval/records/claude-opus-5-max.json, classification USABLE).
      "mode": "primary",
      "model": "github-copilot/claude-opus-5",
      "variant": "max",
      "permission": {
        "edit": "deny",
        "task": {
          "*": "allow",
          "breakglass": "deny"
        },
        "bash": "ask"
      }
    },

    "build": {
      // Hands-on code generation and modification; the restoration controller.
      "mode": "primary",
      "model": "github-copilot/claude-opus-5",
      "variant": "high",
      "permission": {
        "edit": "allow",
        "task": {
          "*": "allow",
          "breakglass": "deny"
        },
        "bash": {
          "*": "allow",
          "git push*": "deny"
        }
      }
    },

    "general": {
      // Catch-all delegated worker for bounded tasks.
      "model": "github-copilot/gpt-5.6-terra",
      "variant": "high",
      "permission": {
        "task": {
          "*": "allow",
          "breakglass": "deny"
        }
      }
    },

    // ── Navigation and analysis agents ─────────────────────────────

    "explore": {
      // Codebase discovery, search, and context gathering.
      "model": "github-copilot/gpt-5.6-luna",
      "variant": "medium"
    },

    "scout": {
      // Targeted lookup and fact-finding across repositories.
      "model": "github-copilot/gpt-5.6-luna",
      "variant": "low"
    },

    // ── Review and escalation ──────────────────────────────────────

    "reviewer": {
      // Independent read-only review. Copilot-hosted, deliberately a
      // different family from the Opus implementers.
      "mode": "subagent",
      "model": "github-copilot/gpt-5.6-sol",
      "variant": "high",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "task": "deny",
        "skill": "allow",
        "bash": {
          "*": "deny",
          "git status*": "allow",
          "git diff*": "allow",
          "git log*": "allow",
          "git show*": "allow"
        }
      }
    },

    "expert": {
      // Escalation-only adviser on direct OpenAI, for provider, quota,
      // policy, credential and governance-domain separation from Copilot.
      // Effort is deliberately above Reviewer's; Reviewer Sol high together
      // with Expert Sol high is a forbidden state.
      "mode": "subagent",
      "model": "openai/gpt-5.6-sol",
      "variant": "xhigh",
      "temperature": 0.1,
      "steps": 6,
      "hidden": true,
      "permission": {
        "edit": "deny",
        "bash": "deny",
        "task": "deny",
        "webfetch": "deny",
        "websearch": "deny",
        "external_directory": "deny",
        "skill": "allow"
      }
    },

    "breakglass": {
      // Human-selected primary only. Never Task-routable; the deny rules
      // above are the control. `hidden` is not a security property.
      "mode": "primary",
      "model": "openai/gpt-5.6-sol",
      "variant": "max",
      "permission": {
        "edit": "deny",
        "bash": "deny",
        "task": "deny"
      }
    },

    // ── Lightweight utility agents ─────────────────────────────────

    "compaction": {
      "model": "github-copilot/gpt-5.6-terra",
      "variant": "medium"
    },

    "title": {
      "model": "github-copilot/gpt-5.6-luna",
      "variant": "low"
    },

    "summary": {
      "model": "github-copilot/gpt-5.6-luna",
      "variant": "low"
    }
  }
}
```

- [ ] **Step 3: Remove routing authority from the reviewer definition**

In `models/routing/opencode/.opencode/agents/reviewer.md`, delete the `model:` and `variant:` lines. The frontmatter becomes exactly:

```yaml
---
description: Independent reviewer — validates spec compliance, code quality, and architectural coherence on a separate model family from implementers. Model and variant are assigned by opencode.jsonc.
mode: subagent
temperature: 0.1
permission:
  edit: deny
  task: deny
  skill: allow
  bash:
    "*": deny
    "git status*": allow
    "git diff*": allow
    "git log*": allow
    "git show*": allow
---
```

Leave the entire prompt body unchanged.

- [ ] **Step 4: Remove routing authority from the expert definition**

In `models/routing/opencode/.opencode/agents/expert.md`, delete the `model:` and `variant:` lines. The frontmatter becomes exactly:

```yaml
---
description: Escalation-only principal engineer adviser — provides structured guidance on hard design and architecture problems without writing code. Model and variant are assigned by opencode.jsonc.
mode: subagent
temperature: 0.1
steps: 6
hidden: true
permission:
  edit: deny
  task: deny
  skill: allow
  bash: deny
---
```

Then replace the body's Availability section, which currently implies a generic OpenAI model:

```markdown
## Availability

This agent runs on direct OpenAI and requires an active OpenAI subscription. If
the model is unavailable, the calling agent should proceed with its own best
judgment and document the uncertainty.
```

Leave the rest of the prompt body unchanged.

- [ ] **Step 5: Update the semantic routing policy**

In `models/routing/opencode/.opencode/model-routing.md`, replace the "Model Family Assignments" section:

```markdown
## Model Family Assignments

Four model families divide the workload by cognitive profile:

| Family | Strengths | Assigned Roles |
|--------|-----------|----------------|
| **Claude Opus 5** | Deep reasoning, nuanced code generation, architectural judgment | plan, build |
| **GPT-5.6 Terra** | Efficient bounded execution and summarization | general, compaction |
| **GPT-5.6 Luna** | Fast retrieval and broad pattern matching | explore, scout, title, summary |
| **GPT-5.6 Sol** | Deep analytical review and escalation | reviewer (Copilot), expert and breakglass (direct OpenAI) |

Role-to-model assignment lives in `opencode.jsonc`. This document assigns work
to roles; it never assigns a model.

### Why different families for different jobs

Placing the reviewer on a separate model family from the implementers (build, general) is a design
heuristic intended to introduce a more independent analytical perspective. It may reduce the risk of
shared blind spots, but it does not guarantee better review quality.

Reviewer and Expert both run GPT-5.6 Sol, on different providers and at
different reasoning efforts. Provider diversity is operational diversity, not
cognitive independence; this correlated-reasoning risk is tracked as
`R-EXPERT-CORRELATED-REASONING`.
```

Then update the Track A capability paragraph so it no longer names Codex as the review family, update the `reviewer` and `expert` role descriptions so neither claims its model comes from the markdown file, add a `breakglass` role description stating it is human-selected primary and never Task-routable, and correct the Superpowers mapping table's dispatched-role column to `reviewer` (Copilot Sol high) and `expert` (direct OpenAI Sol xhigh).

- [ ] **Step 6: Update the bundle README**

In `models/routing/opencode/README.md`, replace the "Model map" section:

```markdown
## Model map

| Role | OpenCode agent | Model | Variant |
|---|---|---|---|
| Planning/design | `plan` | `github-copilot/claude-opus-5` | `max` |
| Primary build/controller | `build` | `github-copilot/claude-opus-5` | `high` |
| Delegated implementation/debugging | `general` | `github-copilot/gpt-5.6-terra` | `high` |
| Local codebase exploration | `explore` | `github-copilot/gpt-5.6-luna` | `medium` |
| External/upstream research | `scout` | `github-copilot/gpt-5.6-luna` | `low` |
| Independent review | `reviewer` | `github-copilot/gpt-5.6-sol` | `high` |
| Escalation-only expert | `expert` | `openai/gpt-5.6-sol` | `xhigh` |
| Human-only breakglass | `breakglass` | `openai/gpt-5.6-sol` | `max` |
| Context compaction | `compaction` | `github-copilot/gpt-5.6-terra` | `medium` |
| Session title | `title` | `github-copilot/gpt-5.6-luna` | `low` |
| Session summary | `summary` | `github-copilot/gpt-5.6-luna` | `low` |

`opencode.jsonc` is the single authority for role-to-model assignment.
`.opencode/agents/reviewer.md` and `.opencode/agents/expert.md` define prompt,
permissions and non-routing metadata only; they carry no `model` or `variant`.

`breakglass` is human-selected primary. Ordinary agents cannot reach it: the
`task` permission denies it explicitly, at the top level and on every agent that
can delegate. `hidden` is not treated as a security property anywhere in this
bundle.

Reviewer and Expert both run GPT-5.6 Sol at different providers and efforts.
The configuration must never install Reviewer Sol `high` together with Expert
Sol `high`; the Expert bump lands atomically with the Reviewer move.
```

Also correct §1's model-verification list to the restored IDs, correct §3's claim that expert "is the only intended path to GPT-5.6 Sol" (Reviewer now uses Sol through Copilot, and Breakglass uses it directly), replace §4's fragment summary block with the eleven restored rows, replace §5's Superpowers routing block, and correct §8's quota rule to name the roles that must stay off direct OpenAI.

- [ ] **Step 7: Run the restoration invariants — they must now pass**

```bash
bash models/routing/opencode/eval/tests/routing-profile-test.sh
```

Expected: `PASS: Phase R routing restoration invariants (11 agents)`.

- [ ] **Step 8: Run the full suite, the installer suite, and the whitespace check**

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
```

Expected: every `PASS:` line, installer suite green, no whitespace errors.

- [ ] **Step 9: Commit — one atomic routing transition**

The eleven rows, the Expert bump and the markdown de-duplication land together. There is no supported intermediate state.

```bash
git add models/routing/opencode/opencode.jsonc \
        models/routing/opencode/.opencode/agents/reviewer.md \
        models/routing/opencode/.opencode/agents/expert.md \
        models/routing/opencode/.opencode/model-routing.md \
        models/routing/opencode/README.md
git commit -m "feat(opencode): restore V1 multi-model routing"
```

---

### Task 8: Shared OpenCode fixture-dispatch primitive

**The single execution layer.** All four behavioral gates dispatch through this. It owns every infrastructure concern and owns **no** pass/fail semantics. Built entirely against fake runtime responses — no credits are spent testing plumbing.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh`
- Test: `models/routing/opencode/eval/tests/dispatch-fixture-test.sh`

**Interfaces:**
- Consumes: `classify_capability_failure` (Task 5), `ledger_append`/`ledger_credits_from_cost` (Task 4).
- Produces:
  - `dispatch_fixture --outdir DIR --label L --prompt-file F (--agent NAME | --model M --variant V) [--workspace DIR] [--timeout SECONDS] [--ledger LEDGER] [--account evaluation|recovery] [--attempt N]`
    Writes `DIR/raw.jsonl` (verbatim stdout+stderr), `DIR/response.txt` (concatenated text parts), `DIR/dispatch.json` (provenance). Exit 0 only when dispatch itself was healthy. **Never reflects gate outcome.**
  - `dispatch_classification <outdir>` — `OK`, `TIMEOUT`, `INVALID_ENVIRONMENT`, `CAPABILITY_REGRESSION`, or `EMPTY_RESPONSE`.
  - `dispatch_response_text <outdir>` — the model's text.
  - `dispatch_extract_json <outdir>` — the last balanced JSON object in the response; exit 1 on parse failure.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/dispatch-fixture-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
printf 'do the thing\n' >"$workspace/prompt.txt"

make_fake() {
  local name=$1
  cat >"$workspace/$name"
  chmod +x "$workspace/$name"
}

make_fake opencode-ok <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$*" >"${DISPATCH_ARGS_SINK:-/dev/null}"
printf '{"type":"step_finish","part":{"cost":0.25,"tokens":{"total":420}}}\n'
printf '{"type":"text","part":{"text":"{\"ordered_path\":[\"entry\"],\"reported_hops\":1}"}}\n'
FAKE

make_fake opencode-error <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"error","error":{"data":{"message":"usage limit has been reached","statusCode":429}}}\n'
exit 1
FAKE

make_fake opencode-gone <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"error","error":{"data":{"message":"ProviderModelNotFoundError: model not found"}}}\n'
exit 1
FAKE

make_fake opencode-slow <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
sleep 30
FAKE

make_fake opencode-prose <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.1,"tokens":{"total":10}}}\n'
printf '{"type":"text","part":{"text":"I could not produce structured output."}}\n'
FAKE

make_fake opencode-empty <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.1,"tokens":{"total":10}}}\n'
FAKE

# --- success path, provenance, raw evidence preservation ---
out="$workspace/ok"
DISPATCH_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-ok" \
  dispatch_fixture --outdir "$out" --label explore-chain --prompt-file "$workspace/prompt.txt" \
    --agent explore --ledger "$ledger" --account evaluation \
  || fail "healthy dispatch reported failure"
assert_eq 'OK' "$(dispatch_classification "$out")"
assert_file "$out/raw.jsonl"
assert_file "$out/response.txt"
assert_file "$out/dispatch.json"
assert_contains "$(<"$out/raw.jsonl")" 'step_finish'
assert_contains "$(<"$workspace/args.txt")" '--agent explore'
assert_contains "$(<"$workspace/args.txt")" '--format json'
for field in routing_profile_commit runtime_version eval_runner_version label attempt \
             dispatch_target wall_clock_ms observed_cost derived_credits tokens exit_status classification; do
  assert_contains "$(<"$out/dispatch.json")" "\"$field\""
done
assert_eq '25.0' "$(ledger_spent "$ledger" evaluation)"

# --- structured extraction and parsing failure ---
assert_eq '1' "$(dispatch_extract_json "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reported_hops"])')"
prose="$workspace/prose"
OPENCODE_BIN="$workspace/opencode-prose" dispatch_fixture --outdir "$prose" --label p \
  --prompt-file "$workspace/prompt.txt" --agent explore || fail "prose dispatch should still be healthy"
assert_eq 'OK' "$(dispatch_classification "$prose")"
if dispatch_extract_json "$prose" >/dev/null 2>&1; then
  fail "accepted unparseable structured output"
fi

# --- error path: transient/external maps to INVALID_ENVIRONMENT ---
err="$workspace/err"
if OPENCODE_BIN="$workspace/opencode-error" dispatch_fixture --outdir "$err" --label e \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "failed dispatch reported success"
fi
assert_eq 'INVALID_ENVIRONMENT' "$(dispatch_classification "$err")"
assert_contains "$(<"$err/dispatch.json")" '"failure_class": "QUOTA_FAILURE"'

# --- error path: capability regression is NOT laundered as INVALID_ENVIRONMENT ---
gone="$workspace/gone"
if OPENCODE_BIN="$workspace/opencode-gone" dispatch_fixture --outdir "$gone" --label g \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "capability regression reported success"
fi
assert_eq 'CAPABILITY_REGRESSION' "$(dispatch_classification "$gone")"

# --- timeout ---
slow="$workspace/slow"
if OPENCODE_BIN="$workspace/opencode-slow" dispatch_fixture --outdir "$slow" --label s \
     --prompt-file "$workspace/prompt.txt" --agent build --timeout 2; then
  fail "timed-out dispatch reported success"
fi
assert_eq 'TIMEOUT' "$(dispatch_classification "$slow")"

# --- empty response ---
empty="$workspace/empty"
if OPENCODE_BIN="$workspace/opencode-empty" dispatch_fixture --outdir "$empty" --label x \
     --prompt-file "$workspace/prompt.txt" --agent build; then
  fail "empty response reported success"
fi
assert_eq 'EMPTY_RESPONSE' "$(dispatch_classification "$empty")"

# --- explicit model dispatch and workspace cwd ---
mkdir -p "$workspace/fixturedir"
printf 'marker\n' >"$workspace/fixturedir/marker.txt"
model_out="$workspace/model"
DISPATCH_ARGS_SINK="$workspace/model-args.txt" OPENCODE_BIN="$workspace/opencode-ok" \
  dispatch_fixture --outdir "$model_out" --label m --prompt-file "$workspace/prompt.txt" \
    --model github-copilot/claude-sonnet-5 --variant high --workspace "$workspace/fixturedir" \
  || fail "explicit model dispatch failed"
assert_contains "$(<"$workspace/model-args.txt")" '--model github-copilot/claude-sonnet-5 --variant high'
assert_contains "$(<"$model_out/dispatch.json")" '"dispatch_target": "github-copilot/claude-sonnet-5"'

# --- the primitive owns no gate semantics ---
if grep -nE '(PASS|FAIL|pass|block)' "$root/runtime/opencode-v1-adapter/dispatch-fixture.sh" \
     | grep -vE 'classification|CAPABILITY|INVALID|TIMEOUT|EMPTY' | grep -q .; then
  fail "dispatch primitive contains gate pass/fail vocabulary"
fi

printf 'PASS: shared fixture dispatch primitive\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/dispatch-fixture-test.sh
```

Expected: `FAIL: missing file: .../dispatch-fixture.sh`.

- [ ] **Step 3: Write the shared primitive**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
dispatch_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$dispatch_root/classify-capability-failure.sh"
source "$dispatch_root/budget-ledger.sh"

dispatch_fixture() {
  local outdir="" label="" prompt_file="" agent="" model="" variant=""
  local fixture_workspace="" timeout_seconds=900 ledger="" account=evaluation attempt=1
  local bin=${OPENCODE_BIN:-opencode}

  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      --prompt-file) prompt_file=$2; shift 2 ;;
      --agent) agent=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      --workspace) fixture_workspace=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --account) account=$2; shift 2 ;;
      --attempt) attempt=$2; shift 2 ;;
      *) printf 'dispatch_fixture: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" && -n "$label" && -n "$prompt_file" ]] || return 2
  [[ -n "$agent" || ( -n "$model" && -n "$variant" ) ]] || return 2

  mkdir -p "$outdir"
  local raw="$outdir/raw.jsonl" start end status version commit target cwd prompt
  prompt=$(<"$prompt_file")
  version=$("$bin" --version 2>/dev/null || printf unknown)
  commit=$(git rev-parse HEAD 2>/dev/null || printf unknown)
  cwd=${fixture_workspace:-$PWD}
  if [[ -n "$agent" ]]; then target="agent:$agent"; else target="$model"; fi

  start=$(date +%s%3N)
  set +e
  if [[ -n "$agent" ]]; then
    ( cd "$cwd" && timeout --preserve-status "$timeout_seconds" \
        "$bin" run --agent "$agent" --format json "$prompt" ) >"$raw" 2>&1
  else
    ( cd "$cwd" && timeout --preserve-status "$timeout_seconds" \
        "$bin" run --model "$model" --variant "$variant" --format json "$prompt" ) >"$raw" 2>&1
  fi
  status=$?
  set -e
  end=$(date +%s%3N)

  # Extract response text, cost, tokens and any provider error from the raw stream.
  RAW="$raw" python3 - "$outdir/response.txt" "$outdir/.parsed.json" <<'PY'
import json
import os
import sys

texts = []
cost = None
tokens = None
error_message = ""
error_status = None
for line in open(os.environ["RAW"], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    part = event.get("part", {})
    if event.get("type") == "text":
        texts.append(part.get("text", ""))
    elif event.get("type") == "step_finish":
        cost = part.get("cost")
        tokens = part.get("tokens")
    elif event.get("type") == "error":
        data = event.get("error", {}).get("data", {})
        if isinstance(data, dict):
            error_message = str(data.get("message", ""))
            error_status = data.get("statusCode")
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("\n".join(texts))
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({"cost": cost, "tokens": tokens,
               "error_text": error_message or None,
               "status_code": error_status}, handle)
PY

  local cost credits failure_class classification
  cost=$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["cost"]; print("null" if v is None else v)' "$outdir/.parsed.json")
  credits=null
  if [[ -n "$model" ]]; then
    credits=$(ledger_credits_from_cost "${model%%/*}" "$cost")
  else
    credits=$(ledger_credits_from_cost github-copilot "$cost")
  fi
  if [[ -n "$ledger" && "$credits" != null ]]; then
    ledger_append "$ledger" "$account" "$label" "${model%%/*}" "$credits"
  fi

  failure_class=$(classify_capability_failure "$outdir/.parsed.json")
  if (( status == 124 )); then
    classification=TIMEOUT
  elif (( status != 0 )); then
    if [[ "$(capability_stop_class "$failure_class")" == CAPABILITY_REGRESSION ]]; then
      classification=CAPABILITY_REGRESSION
    else
      classification=INVALID_ENVIRONMENT
    fi
  elif [[ ! -s "$outdir/response.txt" ]]; then
    classification=EMPTY_RESPONSE
  else
    classification=OK
  fi

  LABEL="$label" TARGET="$target" VARIANT="${variant:-resolved}" ATTEMPT="$attempt" \
    VERSION="$version" COMMIT="$commit" STATUS="$status" START="$start" END="$end" \
    CREDITS="$credits" CLASSIFICATION="$classification" FAILURE_CLASS="$failure_class" \
    PARSED="$outdir/.parsed.json" TIMEOUT_SECONDS="$timeout_seconds" \
    python3 - "$outdir/dispatch.json" <<'PY'
import datetime
import json
import os
import sys

parsed = json.load(open(os.environ["PARSED"], encoding="utf-8"))
credits = os.environ["CREDITS"]
document = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "label": os.environ["LABEL"],
    "attempt": int(os.environ["ATTEMPT"]),
    "routing_profile_id": "v1-restored-2026-09",
    "routing_profile_commit": os.environ["COMMIT"],
    "runtime_version": os.environ["VERSION"].strip(),
    "eval_runner_version": "phase-r-dispatch-v1",
    "environment": f"{os.uname().sysname} {os.uname().release} {os.uname().machine}",
    "dispatch_target": os.environ["TARGET"],
    "variant": os.environ["VARIANT"],
    "timeout_seconds": int(os.environ["TIMEOUT_SECONDS"]),
    "exit_status": int(os.environ["STATUS"]),
    "classification": os.environ["CLASSIFICATION"],
    "failure_class": os.environ["FAILURE_CLASS"] if os.environ["CLASSIFICATION"] != "OK" else None,
    "provider_error_text": parsed.get("error_text"),
    "provider_status_code": parsed.get("status_code"),
    "observed_cost": parsed.get("cost"),
    "derived_credits": None if credits == "null" else float(credits),
    "normalized_steady_state_cost": None,
    "tokens": parsed.get("tokens"),
    "wall_clock_ms": int(os.environ["END"]) - int(os.environ["START"]),
    "retry_count": 0,
    "raw_evidence": "raw.jsonl",
    "decides_gate_outcome": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
  rm -f "$outdir/.parsed.json"
  [[ "$classification" == OK ]]
}

dispatch_classification() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["classification"])' "$1/dispatch.json"
}

dispatch_response_text() {
  cat "$1/response.txt"
}

dispatch_extract_json() {
  python3 - "$1/response.txt" <<'PY'
import json
import sys

text = open(sys.argv[1], encoding="utf-8").read()
candidates = []
depth = 0
start = None
in_string = False
escaped = False
for index, char in enumerate(text):
    if in_string:
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = False
        continue
    if char == '"':
        in_string = True
    elif char == "{":
        if depth == 0:
            start = index
        depth += 1
    elif char == "}":
        if depth:
            depth -= 1
            if depth == 0 and start is not None:
                candidates.append(text[start:index + 1])
for candidate in reversed(candidates):
    try:
        json.dump(json.loads(candidate), sys.stdout, indent=2)
    except json.JSONDecodeError:
        continue
    sys.stdout.write("\n")
    raise SystemExit(0)
raise SystemExit("no parseable JSON object in response")
PY
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh \
         models/routing/opencode/eval/tests/dispatch-fixture-test.sh
bash models/routing/opencode/eval/tests/dispatch-fixture-test.sh
```

Expected: `PASS: shared fixture dispatch primitive`. Zero credits consumed — every case used a fake binary.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh \
        models/routing/opencode/eval/tests/dispatch-fixture-test.sh
git commit -m "test(opencode): add shared OpenCode fixture dispatch primitive"
```

---

### Task 9: Build runner (thin adapter)

Wraps the committed `build-restoration-gate` fixture. It executes one attempt and records the **committed `oracle.sh`** verdict. It does not implement the 3→5 state machine, does not classify failures, and does not erase anything — `eval/decision-rules/build-gate.sh` owns all of that and is unmodified.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-build-restoration-gate.sh`
- Test: `models/routing/opencode/eval/tests/build-restoration-runner-test.sh`

**Interfaces:**
- Consumes: `dispatch_fixture` (Task 8); `eval/fixtures/build-workloads/build-restoration-gate/{snapshot,task.md,oracle.sh}`.
- Produces: `run_build_restoration_gate --outdir DIR --ledger L --attempt N [--model M --variant V]` — materializes the snapshot, asserts the acceptance test starts red, dispatches `build` (or an explicit model for the Sonnet fixture control), runs `oracle.sh`, writes `DIR/attempt.json`. Exit 0 iff the committed oracle passed **and** dispatch was healthy.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/build-restoration-runner-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"

make_fake() { local n=$1; cat >"$workspace/$n"; chmod +x "$workspace/$n"; }

make_fake opencode-solves <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$PWD" >"${BUILD_CWD_SINK:-/dev/null}"
printf '%s\n' "$*" >"${BUILD_ARGS_SINK:-/dev/null}"
cat >>lib/math.sh <<'SH'

double() {
  printf '%s\n' $(( $1 * 2 ))
}
SH
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"added double"}}\n'
FAKE

make_fake opencode-idle <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":10}}}\n'
printf '{"type":"text","part":{"text":"nothing to do"}}\n'
FAKE

make_fake opencode-scope <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
cat >>lib/math.sh <<'SH'

double() {
  printf '%s\n' $(( $1 * 2 ))
}
SH
printf 'tampered\n' >>README.md
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"done"}}\n'
FAKE

make_fake opencode-regress <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
cat >lib/math.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
double() { printf '%s\n' $(( $1 * 2 )); }
SH
printf '{"type":"step_finish","part":{"cost":0.4,"tokens":{"total":900}}}\n'
printf '{"type":"text","part":{"text":"done"}}\n'
FAKE

pass_dir="$workspace/pass"
BUILD_CWD_SINK="$workspace/cwd.txt" BUILD_ARGS_SINK="$workspace/args.txt" \
  OPENCODE_BIN="$workspace/opencode-solves" \
  run_build_restoration_gate --outdir "$pass_dir" --ledger "$ledger" --attempt 1 \
  || fail "a correct implementation did not satisfy the committed oracle"
assert_contains "$(<"$workspace/args.txt")" '--agent build'
assert_contains "$(<"$pass_dir/attempt.json")" '"oracle_passed": true'
assert_contains "$(<"$pass_dir/attempt.json")" '"acceptance_initially_failing": true'
assert_contains "$(<"$pass_dir/attempt.json")" '"fixture": "build-restoration-gate"'
assert_contains "$(<"$pass_dir/attempt.json")" '"runner_decides_gate_outcome": false'
assert_file "$pass_dir/dispatch/raw.jsonl"

for fake in idle scope regress; do
  target="$workspace/fail-$fake"
  if OPENCODE_BIN="$workspace/opencode-$fake" \
       run_build_restoration_gate --outdir "$target" --ledger "$ledger" --attempt 1; then
    fail "oracle accepted the '$fake' outcome"
  fi
  assert_contains "$(<"$target/attempt.json")" '"oracle_passed": false'
done

model_dir="$workspace/control"
BUILD_ARGS_SINK="$workspace/control-args.txt" OPENCODE_BIN="$workspace/opencode-solves" \
  run_build_restoration_gate --outdir "$model_dir" --ledger "$ledger" --attempt 1 \
    --model github-copilot/claude-sonnet-5 --variant high \
  || fail "explicit fixture-control dispatch failed"
assert_contains "$(<"$workspace/control-args.txt")" '--model github-copilot/claude-sonnet-5 --variant high'

# The adapter must not re-implement the state machine or classification.
runner="$root/runtime/opencode-v1-adapter/run-build-restoration-gate.sh"
for forbidden in VALID_CONTROLLER_FAILURE FIXTURE_DEFECT build_gate 'n=5' '4/5' '3/3'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "build runner re-implements committed decision logic: $forbidden"
  fi
done

printf 'PASS: build restoration gate runner\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/build-restoration-runner-test.sh
```

Expected: `FAIL: missing file: .../run-build-restoration-gate.sh`.

- [ ] **Step 3: Write the adapter**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-build-restoration-gate.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
build_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$build_runner_root/dispatch-fixture.sh"

run_build_restoration_gate() {
  local outdir="" ledger="" attempt=1 model="" variant="" timeout_seconds=1800
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --attempt) attempt=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_build_restoration_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture sandbox prompt oracle_status dispatch_status initially_failing
  fixture=$(cd "$build_runner_root/../../fixtures/build-workloads/build-restoration-gate" && pwd)
  mkdir -p "$outdir"
  sandbox="$outdir/sandbox"
  rm -rf "$sandbox"
  mkdir -p "$sandbox"
  cp -R "$fixture/snapshot/." "$sandbox/"
  prompt="$outdir/prompt.txt"
  cp "$fixture/task.md" "$prompt"

  # Fixture precondition: the acceptance suite must start red.
  if ( cd "$sandbox" && bash tests/acceptance.sh >/dev/null 2>&1 ); then
    initially_failing=false
  else
    initially_failing=true
  fi

  set +e
  if [[ -n "$model" ]]; then
    dispatch_fixture --outdir "$outdir/dispatch" --label "build-restoration-gate" \
      --prompt-file "$prompt" --model "$model" --variant "$variant" \
      --workspace "$sandbox" --timeout "$timeout_seconds" \
      ${ledger:+--ledger "$ledger"} --attempt "$attempt"
  else
    dispatch_fixture --outdir "$outdir/dispatch" --label "build-restoration-gate" \
      --prompt-file "$prompt" --agent build \
      --workspace "$sandbox" --timeout "$timeout_seconds" \
      ${ledger:+--ledger "$ledger"} --attempt "$attempt"
  fi
  dispatch_status=$?
  set -e

  # The committed mechanical oracle is the sole verdict on the work product.
  set +e
  bash "$fixture/oracle.sh" "$sandbox" >"$outdir/oracle.log" 2>&1
  oracle_status=$?
  set -e

  ATTEMPT="$attempt" INITIAL="$initially_failing" ORACLE="$oracle_status" \
    DISPATCH_STATUS="$dispatch_status" DISPATCH="$outdir/dispatch/dispatch.json" \
    python3 - "$outdir/attempt.json" <<'PY'
import json
import os
import sys

dispatch = json.load(open(os.environ["DISPATCH"], encoding="utf-8"))
document = {
    "fixture": "build-restoration-gate",
    "phase": "R-operational-viability",
    "attempt": int(os.environ["ATTEMPT"]),
    "acceptance_initially_failing": os.environ["INITIAL"] == "true",
    "dispatch": dispatch,
    "dispatch_healthy": int(os.environ["DISPATCH_STATUS"]) == 0,
    "oracle": "eval/fixtures/build-workloads/build-restoration-gate/oracle.sh",
    "oracle_exit_status": int(os.environ["ORACLE"]),
    "oracle_passed": int(os.environ["ORACLE"]) == 0,
    "human_or_llm_judgment_in_oracle": False,
    "runner_decides_gate_outcome": False,
    "classification": None,
    "classification_owner": "eval/decision-rules/build-gate.sh",
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  rm -rf "$sandbox"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); raise SystemExit(0 if d["oracle_passed"] and d["dispatch_healthy"] and d["acceptance_initially_failing"] else 1)' "$outdir/attempt.json"
}
```

`classification` is deliberately left `null`. Only a human, following `eval/decision-rules/build-gate.sh`, writes `INVALID_ENVIRONMENT`, `VALID_CONTROLLER_FAILURE` or `FIXTURE_DEFECT` into the append-only ledger in Task 18.

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/run-build-restoration-gate.sh \
         models/routing/opencode/eval/tests/build-restoration-runner-test.sh
bash models/routing/opencode/eval/tests/build-restoration-runner-test.sh
```

Expected: `PASS: build restoration gate runner`. Zero credits.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/run-build-restoration-gate.sh \
        models/routing/opencode/eval/tests/build-restoration-runner-test.sh
git commit -m "test(opencode): add build restoration gate runner"
```

---

### Task 10: Reviewer runner (thin adapter)

Materializes the five committed seeded cases and the clean control, dispatches `reviewer` against each, and normalizes the reported findings into the exact schema `reviewer_structured_gate` already consumes. It invents no defect taxonomy and makes no detection ruling.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-reviewer-gate.sh`
- Test: `models/routing/opencode/eval/tests/reviewer-runner-test.sh`

**Interfaces:**
- Consumes: `dispatch_fixture` (Task 8); `eval/fixtures/reviewer-seeded-defects/{clean,cases/*}`.
- Produces: `run_reviewer_gate --outdir DIR --ledger L` — writes `DIR/findings.json` in the shape `{"seeded":[{"id","severity","file","summary"}...],"clean":[{"severity","file","summary"}...]}` plus `DIR/<case>/dispatch/` raw evidence. Exit 0 iff every dispatch was healthy. **Gate outcome is decided later by `reviewer_structured_gate`.**

**Normalization rule** (mechanical, no adjudication): each case's `ground-truth.json` names exactly one `overrides` file. The adapter records the **highest severity the reviewer itself reported against that file** — ordering `blocking > material > suggestion > none` — as that case's severity, and preserves the verbatim summary. Whether that constitutes detection is `reviewer_structured_gate`'s decision, not the adapter's.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/reviewer-runner-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/reviewer.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"

# A fake reviewer that flags the overridden file in every seeded sandbox and
# stays silent on the clean control. It infers the case from the files present.
cat >"$workspace/opencode-detects" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "$*" >>"${REVIEWER_ARGS_SINK:-/dev/null}"
marker=$(cat .case 2>/dev/null || printf clean)
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
case "$marker" in
  R-CONCURRENCY) file=counter.sh ;;
  R-AUTH) file=authorization.sh ;;
  R-API) file=api.sh ;;
  R-BOUNDARY) file=pagination.sh ;;
  R-ERROR) file=storage.sh ;;
  *) printf '{"type":"text","part":{"text":"{\"findings\":[]}"}}\n'; exit 0 ;;
esac
printf '{"type":"text","part":{"text":"{\"findings\":[{\"file\":\"%s\",\"severity\":\"material\",\"summary\":\"seeded defect\"}]}"}}\n' "$file"
FAKE
chmod +x "$workspace/opencode-detects"

out="$workspace/run"
REVIEWER_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-detects" \
  run_reviewer_gate --outdir "$out" --ledger "$ledger" \
  || fail "healthy reviewer dispatch reported failure"

assert_contains "$(<"$workspace/args.txt")" '--agent reviewer'
assert_file "$out/findings.json"

python3 - "$out/findings.json" <<'PY'
import json
import sys

findings = json.load(open(sys.argv[1], encoding="utf-8"))
seeded = {item["id"]: item for item in findings["seeded"]}
expected = {"R-CONCURRENCY", "R-AUTH", "R-API", "R-BOUNDARY", "R-ERROR"}
assert set(seeded) == expected, f"seeded ids {sorted(seeded)} != {sorted(expected)}"
assert all(item["severity"] == "material" for item in seeded.values()), seeded
assert all(item.get("summary") for item in seeded.values()), "verbatim summaries not preserved"
assert findings["clean"] == [], f"clean control should be empty, got {findings['clean']}"
PY

# The committed scorer — not the adapter — decides the outcome.
assert_eq 'pass' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$out/findings.json")"

# A reviewer that misses one defect still yields a healthy run; the scorer blocks it.
cat >"$workspace/opencode-misses" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
marker=$(cat .case 2>/dev/null || printf clean)
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
if [[ "$marker" == R-AUTH || "$marker" == clean ]]; then
  printf '{"type":"text","part":{"text":"{\"findings\":[]}"}}\n'; exit 0
fi
case "$marker" in
  R-CONCURRENCY) file=counter.sh ;; R-API) file=api.sh ;;
  R-BOUNDARY) file=pagination.sh ;; R-ERROR) file=storage.sh ;;
esac
printf '{"type":"text","part":{"text":"{\"findings\":[{\"file\":\"%s\",\"severity\":\"blocking\",\"summary\":\"seeded defect\"}]}"}}\n' "$file"
FAKE
chmod +x "$workspace/opencode-misses"

miss="$workspace/miss"
OPENCODE_BIN="$workspace/opencode-misses" run_reviewer_gate --outdir "$miss" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
assert_eq 'block' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$miss/findings.json")"

# A false positive on the clean control is recorded faithfully.
cat >"$workspace/opencode-noisy" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '{"type":"step_finish","part":{"cost":0.02,"tokens":{"total":300}}}\n'
printf '{"type":"text","part":{"text":"{\"findings\":[{\"file\":\"counter.sh\",\"severity\":\"material\",\"summary\":\"imagined\"}]}"}}\n'
FAKE
chmod +x "$workspace/opencode-noisy"
noisy="$workspace/noisy"
OPENCODE_BIN="$workspace/opencode-noisy" run_reviewer_gate --outdir "$noisy" --ledger "$ledger" || true
assert_eq 'block' "$(reviewer_structured_gate "$root/fixtures/reviewer-seeded-defects/oracle.json" "$noisy/findings.json")"

# The adapter must not embed the gate thresholds or the expected id list.
runner="$root/runtime/opencode-v1-adapter/run-reviewer-gate.sh"
for forbidden in 'required_seeded_detections' 'allowed_clean_material_findings' 'R-CONCURRENCY' 'material_severities'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "reviewer runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: reviewer gate runner\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/reviewer-runner-test.sh
```

Expected: `FAIL: missing file: .../run-reviewer-gate.sh`.

- [ ] **Step 3: Write the adapter**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-reviewer-gate.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
reviewer_runner_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$reviewer_runner_root/dispatch-fixture.sh"

reviewer_request() {
  cat <<'PROMPT'
Review every shell script in the current directory as an independent reviewer.

Report your findings and nothing else, as a single JSON object on the final
line, in exactly this form:

{"findings":[{"file":"<file name>","severity":"blocking|material|suggestion","summary":"<one sentence>"}]}

Use "blocking" or "material" only for a defect that would cause incorrect
behavior, data loss, or a security exposure. Use "suggestion" for anything
stylistic or non-consequential. If you find nothing, return {"findings":[]}.
PROMPT
}

run_reviewer_gate() {
  local outdir="" ledger="" timeout_seconds=900 healthy=0
  while (( $# )); do
    case "$1" in
      --outdir) outdir=$2; shift 2 ;;
      --ledger) ledger=$2; shift 2 ;;
      --timeout) timeout_seconds=$2; shift 2 ;;
      *) printf 'run_reviewer_gate: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$outdir" ]] || return 2

  local fixture prompt sandbox case_dir case_id
  fixture=$(cd "$reviewer_runner_root/../../fixtures/reviewer-seeded-defects" && pwd)
  mkdir -p "$outdir"
  prompt="$outdir/prompt.txt"
  reviewer_request >"$prompt"

  run_one() {
    local label=$1 sandbox=$2
    set +e
    dispatch_fixture --outdir "$outdir/$label/dispatch" --label "reviewer-$label" \
      --prompt-file "$prompt" --agent reviewer --workspace "$sandbox" \
      --timeout "$timeout_seconds" ${ledger:+--ledger "$ledger"} --attempt 1
    local status=$?
    set -e
    (( status == 0 )) || healthy=1
    set +e
    dispatch_extract_json "$outdir/$label/dispatch" >"$outdir/$label/reported.json" 2>/dev/null
    if (( $? != 0 )); then printf '{"findings":[]}\n' >"$outdir/$label/reported.json"; healthy=1; fi
    set -e
  }

  # Clean control.
  sandbox="$outdir/clean/sandbox"
  mkdir -p "$sandbox"
  find "$fixture/clean" -maxdepth 1 -name '*.sh' -exec cp {} "$sandbox/" \;
  run_one clean "$sandbox"

  # Seeded cases: clean snapshot plus that case's single override.
  for case_dir in "$fixture"/cases/*/; do
    case_id=$(basename "$case_dir")
    sandbox="$outdir/$case_id/sandbox"
    mkdir -p "$sandbox"
    find "$fixture/clean" -maxdepth 1 -name '*.sh' -exec cp {} "$sandbox/" \;
    python3 - "$case_dir/ground-truth.json" "$case_dir" "$sandbox" <<'PY'
import json
import shutil
import sys

ground_truth_path, case_dir, sandbox = sys.argv[1:]
for override in json.load(open(ground_truth_path, encoding="utf-8"))["overrides"]:
    shutil.copy(f"{case_dir}/{override}", f"{sandbox}/{override}")
PY
    printf '%s\n' "$case_id" >"$sandbox/.case"
    run_one "$case_id" "$sandbox"
  done

  # Normalize into the schema the committed scorer already consumes.
  python3 - "$outdir" "$fixture" <<'PY'
import glob
import json
import os
import sys

outdir, fixture = sys.argv[1:]
RANK = {"blocking": 3, "material": 2, "suggestion": 1}

def reported(label):
    path = f"{outdir}/{label}/reported.json"
    try:
        payload = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    items = payload.get("findings", payload if isinstance(payload, list) else [])
    return [item for item in items if isinstance(item, dict)]

seeded = []
for case_dir in sorted(glob.glob(f"{fixture}/cases/*/")):
    case_id = os.path.basename(case_dir.rstrip("/"))
    overrides = set(json.load(open(f"{case_dir}/ground-truth.json", encoding="utf-8"))["overrides"])
    candidates = [item for item in reported(case_id)
                  if os.path.basename(str(item.get("file", ""))) in overrides]
    if candidates:
        best = max(candidates, key=lambda item: RANK.get(str(item.get("severity")), 0))
        severity = str(best.get("severity"))
        summary = str(best.get("summary", ""))
    else:
        severity, summary = "none", ""
    seeded.append({"id": case_id, "severity": severity, "files": sorted(overrides),
                   "summary": summary, "all_reported": reported(case_id)})

clean = [{"severity": str(item.get("severity")),
          "file": str(item.get("file", "")),
          "summary": str(item.get("summary", ""))}
         for item in reported("clean")]

document = {"seeded": seeded, "clean": clean,
            "normalization": "highest severity the reviewer reported against the case's override file",
            "runner_decides_gate_outcome": False,
            "scorer": "eval/scoring/reviewer.sh::reviewer_structured_gate"}
with open(f"{outdir}/findings.json", "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  return "$healthy"
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/run-reviewer-gate.sh \
         models/routing/opencode/eval/tests/reviewer-runner-test.sh
bash models/routing/opencode/eval/tests/reviewer-runner-test.sh
```

Expected: `PASS: reviewer gate runner`. Zero credits.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/run-reviewer-gate.sh \
        models/routing/opencode/eval/tests/reviewer-runner-test.sh
git commit -m "test(opencode): add reviewer seeded-defect gate runner"
```

---

### Task 11: Explore runner (thin adapter)

Dispatches `explore` at the committed dependency-chain snapshot and copies the model's own structured answer into `actual.json` verbatim. The ordered chain, hop count, terminal symbol and terminal value are all validated by `explore_gate` — finding `v3` alone is not sufficient and the adapter never checks it.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-explore-gate.sh`
- Test: `models/routing/opencode/eval/tests/explore-runner-test.sh`

**Interfaces:**
- Consumes: `dispatch_fixture` (Task 8); `eval/fixtures/explore-dependency-chain/snapshot/`.
- Produces: `run_explore_gate --outdir DIR --ledger L` — writes `DIR/actual.json` with `ordered_path`, `reported_hops`, `terminal_symbol`, `terminal_value` copied verbatim (missing fields become `null`). Exit 0 iff dispatch was healthy.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/explore-runner-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/explore.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
oracle="$root/fixtures/explore-dependency-chain/oracle.json"

fake_with() {
  cat >"$workspace/opencode-fake" <<FAKE
#!/usr/bin/env bash
if [[ "\${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
printf '%s\n' "\$*" >"\${EXPLORE_ARGS_SINK:-/dev/null}"
ls entry.sh >/dev/null || exit 3
printf '{"type":"step_finish","part":{"cost":0.01,"tokens":{"total":200}}}\n'
printf '{"type":"text","part":{"text":"$1"}}\n'
FAKE
  chmod +x "$workspace/opencode-fake"
}

correct='{\"ordered_path\":[\"entry\",\"facade\",\"service\",\"adapter\",\"protocol\"],\"reported_hops\":4,\"terminal_symbol\":\"PROTOCOL_VERSION\",\"terminal_value\":\"v3\"}'
fake_with "$correct"
good="$workspace/good"
EXPLORE_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-fake" \
  run_explore_gate --outdir "$good" --ledger "$ledger" || fail "healthy explore dispatch reported failure"
assert_contains "$(<"$workspace/args.txt")" '--agent explore'
assert_eq 'pass' "$(explore_gate "$oracle" "$good/actual.json")"

# Terminal value alone must not pass: the oracle checks the whole chain.
partial='{\"ordered_path\":[\"entry\",\"protocol\"],\"reported_hops\":1,\"terminal_symbol\":\"PROTOCOL_VERSION\",\"terminal_value\":\"v3\"}'
fake_with "$partial"
short="$workspace/short"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$short" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
assert_eq 'block' "$(explore_gate "$oracle" "$short/actual.json")"

# Right chain, wrong hop count still blocks.
miscount='{\"ordered_path\":[\"entry\",\"facade\",\"service\",\"adapter\",\"protocol\"],\"reported_hops\":5,\"terminal_symbol\":\"PROTOCOL_VERSION\",\"terminal_value\":\"v3\"}'
fake_with "$miscount"
bad="$workspace/bad"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$bad" --ledger "$ledger" || true
assert_eq 'block' "$(explore_gate "$oracle" "$bad/actual.json")"

# Unparseable prose produces a null-filled record, not a repaired one.
fake_with 'I traced it and the answer is v3.'
prose="$workspace/prose"
OPENCODE_BIN="$workspace/opencode-fake" run_explore_gate --outdir "$prose" --ledger "$ledger" || true
python3 - "$prose/actual.json" <<'PY'
import json
import sys
actual = json.load(open(sys.argv[1], encoding="utf-8"))
assert actual["ordered_path"] is None, actual
assert actual["reported_hops"] is None, actual
assert actual["terminal_value"] is None, actual
PY
assert_eq 'block' "$(explore_gate "$oracle" "$prose/actual.json")"

runner="$root/runtime/opencode-v1-adapter/run-explore-gate.sh"
for forbidden in 'PROTOCOL_VERSION' 'required_hops' '"v3"' 'facade'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "explore runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: explore gate runner\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/explore-runner-test.sh
```

Expected: `FAIL: missing file: .../run-explore-gate.sh`.

- [ ] **Step 3: Write the adapter**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-explore-gate.sh`:

```bash
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

  set +e
  dispatch_fixture --outdir "$outdir/dispatch" --label explore-dependency-chain \
    --prompt-file "$prompt" --agent explore --workspace "$sandbox" \
    --timeout "$timeout_seconds" ${ledger:+--ledger "$ledger"} --attempt 1
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
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/run-explore-gate.sh \
         models/routing/opencode/eval/tests/explore-runner-test.sh
bash models/routing/opencode/eval/tests/explore-runner-test.sh
```

Expected: `PASS: explore gate runner`. Zero credits.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/run-explore-gate.sh \
        models/routing/opencode/eval/tests/explore-runner-test.sh
git commit -m "test(opencode): add explore dependency-chain gate runner"
```

---

### Task 12: Compaction runner (thin adapter)

Dispatches `compaction` at the committed noisy corpus and extracts the `[INV-ID] value` pairs **from the model's own summary**, verbatim. It does not repair, rewrite, or search for expected values. `compaction_structured_gate` owns the 4/4 preservation and zero-contradiction decision, including alias equivalence.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-compaction-gate.sh`
- Test: `models/routing/opencode/eval/tests/compaction-runner-test.sh`

**Interfaces:**
- Consumes: `dispatch_fixture` (Task 8); `eval/fixtures/compaction-invariants/context.md`.
- Produces: `run_compaction_gate --outdir DIR --ledger L` — writes `DIR/actual.json` as `{"invariants":{"INV-X":"<verbatim value>"|null,...},"contradictions":[...]}` plus `DIR/summary.txt` (the full compacted summary, preserved for audit). Exit 0 iff dispatch was healthy.

**Extraction rule** (mechanical): every occurrence of `[INV-<NAME>] <value>` up to end of line is collected. The first occurrence's value becomes `invariants["INV-<NAME>"]`. An ID whose occurrences carry more than one distinct value is listed in `contradictions`. IDs never emitted are `null`. The adapter has no knowledge of which values are correct.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/compaction-runner-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
source "$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
source "$root/runtime/opencode-v1-adapter/budget-ledger.sh"
source "$root/scoring/compaction.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
ledger="$workspace/ledger.json"
ledger_init "$ledger" "$root/manifests/phase-0-budgets.json"
oracle="$root/fixtures/compaction-invariants/oracle.json"

fake_with() {
  python3 - "$workspace/opencode-fake" "$1" <<'PY'
import json
import sys
path, summary = sys.argv[1:]
script = f'''#!/usr/bin/env bash
if [[ "${{1:-}}" == --version ]]; then printf '1.18.27\\n'; exit 0; fi
printf '%s\\n' "$*" >"${{COMPACTION_ARGS_SINK:-/dev/null}}"
printf '{{"type":"step_finish","part":{{"cost":0.01,"tokens":{{"total":500}}}}}}\\n'
printf '%s\\n' {json.dumps(json.dumps({"type": "text", "part": {"text": summary}}))}
'''
open(path, "w", encoding="utf-8").write(script)
PY
  chmod +x "$workspace/opencode-fake"
}

all_four='Summary. [INV-RUNTIME] target_runtime=opencode-v1
[INV-BREAKGLASS] breakglass=primary-human-only
[INV-BUDGET] phase-r-recovery-budget=250-credits-non-reclaimable
[INV-FAILURE] valid-controller-failure=remains-in-denominator'
fake_with "$all_four"
good="$workspace/good"
COMPACTION_ARGS_SINK="$workspace/args.txt" OPENCODE_BIN="$workspace/opencode-fake" \
  run_compaction_gate --outdir "$good" --ledger "$ledger" || fail "healthy compaction dispatch reported failure"
assert_contains "$(<"$workspace/args.txt")" '--agent compaction'
assert_file "$good/summary.txt"
assert_eq 'pass' "$(compaction_structured_gate "$oracle" "$good/actual.json")"

# An alias emitted inside the tag is the scorer's call, not the runner's.
aliased='[INV-RUNTIME] OpenCode V1
[INV-BREAKGLASS] human-selected primary only
[INV-BUDGET] 250 credits reserved; evaluation cannot reclaim them
[INV-FAILURE] valid controller failures stay in the denominator'
fake_with "$aliased"
alias_dir="$workspace/alias"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$alias_dir" --ledger "$ledger" || true
assert_eq 'pass' "$(compaction_structured_gate "$oracle" "$alias_dir/actual.json")"

# A dropped invariant blocks; the runner must not invent it.
three='[INV-RUNTIME] target_runtime=opencode-v1
[INV-BREAKGLASS] breakglass=primary-human-only
[INV-BUDGET] phase-r-recovery-budget=250-credits-non-reclaimable'
fake_with "$three"
short="$workspace/short"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$short" --ledger "$ledger" \
  || fail "runner must report dispatch health, not gate outcome"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); assert a["invariants"]["INV-FAILURE"] is None, a' "$short/actual.json"
assert_eq 'block' "$(compaction_structured_gate "$oracle" "$short/actual.json")"

# A contradictory restatement is recorded, not silently deduplicated.
contradictory="$all_four
Correction: [INV-BUDGET] phase-r-recovery-budget=0-credits"
fake_with "$contradictory"
conflict="$workspace/conflict"
OPENCODE_BIN="$workspace/opencode-fake" run_compaction_gate --outdir "$conflict" --ledger "$ledger" || true
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); assert "INV-BUDGET" in a["contradictions"], a' "$conflict/actual.json"
assert_eq 'block' "$(compaction_structured_gate "$oracle" "$conflict/actual.json")"

runner="$root/runtime/opencode-v1-adapter/run-compaction-gate.sh"
for forbidden in 'opencode-v1' 'primary-human-only' '250-credits' 'required_preserved' 'aliases'; do
  if grep -qF "$forbidden" "$runner"; then
    fail "compaction runner embeds committed ground truth: $forbidden"
  fi
done

printf 'PASS: compaction gate runner\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/compaction-runner-test.sh
```

Expected: `FAIL: missing file: .../run-compaction-gate.sh`.

- [ ] **Step 3: Write the adapter**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-compaction-gate.sh`:

```bash
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

  set +e
  dispatch_fixture --outdir "$outdir/dispatch" --label compaction-invariants \
    --prompt-file "$prompt" --agent compaction \
    --timeout "$timeout_seconds" ${ledger:+--ledger "$ledger"} --attempt 1
  status=$?
  set -e

  cp "$outdir/dispatch/response.txt" "$outdir/summary.txt"

  # Extract the model's own tagged values verbatim. No repair, no lookup.
  python3 - "$outdir/summary.txt" "$outdir/actual.json" <<'PY'
import json
import re
import sys

source, destination = sys.argv[1:]
text = open(source, encoding="utf-8").read()
occurrences = {}
for identifier, value in re.findall(r"\[(INV-[A-Z0-9_-]+)\]\s*([^\n]*)", text):
    occurrences.setdefault(identifier, []).append(value.strip())

invariants = {identifier: values[0] for identifier, values in occurrences.items()}
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
```

Note that `compaction_structured_gate` reads `actual["invariants"].get(key)`, so an identifier the model never emitted resolves to `None` and counts as not preserved — exactly the intended behavior, with no adapter involvement.

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/run-compaction-gate.sh \
         models/routing/opencode/eval/tests/compaction-runner-test.sh
bash models/routing/opencode/eval/tests/compaction-runner-test.sh
```

Expected: `PASS: compaction gate runner`. Zero credits.

- [ ] **Step 5: Run the full deterministic suite before any live gate execution**

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
```

Expected: every test `PASS`, installer suite green, no whitespace errors. **Live model calls for the behavioral gates begin only after this is green.**

- [ ] **Step 6: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/run-compaction-gate.sh \
        models/routing/opencode/eval/tests/compaction-runner-test.sh
git commit -m "test(opencode): add compaction invariant gate runner"
```

---

### Task 13: Activation tooling — backup and routing-owned merge

Merges **only** routing-owned keys into the user-global JSONC after a fresh timestamped backup. Never replaces the whole file. Built and tested entirely against a fake config root; the real workstation is not touched until Task 16.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh`
- Test: `models/routing/opencode/eval/tests/activation-merge-test.sh`

**Interfaces:**
- Consumes: `select_activation_target` (existing), `load_routing_profile` (Task 1), `phase-r-routing-targets.json` (Task 2).
- Produces: `activate_profile --repo-profile P --targets M --config-root DIR --backup-root DIR [--dry-run]` — prints the backup directory, the activated path and both SHA-256 values. **Routing-owned keys are exactly** `model`, `permission.task`, and `agent.<role>` for each of the eleven declared roles. Every other key is preserved verbatim.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/activation-merge-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/activate-profile.sh"
source "$root/runtime/opencode-v1-adapter/activate-profile.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
config_root="$workspace/config"
backup_root="$workspace/backups"
mkdir -p "$config_root"

cat >"$config_root/opencode.jsonc" <<'JSONC'
{
  // a user comment that will not survive the rewrite
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".opencode/model-routing.md", "docs/house-style.md"],
  "model": "github-copilot/claude-opus-4.6",
  "permission": { "websearch": "allow" },
  "agent": {
    "plan": { "mode": "primary", "model": "github-copilot/claude-opus-4.6", "variant": "max" },
    "scout": { "model": "github-copilot/gpt-5.3-codex", "variant": "high" }
  },
  "plugin": ["superpowers@git+https://github.com/obra/superpowers.git#v6.3.0"],
  "mcp": { "example": { "type": "remote", "url": "https://example.invalid/mcp" } },
  "theme": "opencode"
}
JSONC

activate_profile --repo-profile "$root/../opencode.jsonc" \
                 --targets "$root/manifests/phase-r-routing-targets.json" \
                 --config-root "$config_root" --backup-root "$backup_root" >"$workspace/out.txt"

assert_contains "$(<"$workspace/out.txt")" "$config_root/opencode.jsonc"
backup_dir=$(grep '^backup_dir=' "$workspace/out.txt" | cut -d= -f2-)
assert_file "$backup_dir/opencode.jsonc"
assert_file "$backup_dir/manifest.json"
assert_contains "$(basename "$backup_dir")" 'phase-r-'

python3 - "$config_root/opencode.jsonc" "$root/manifests/phase-r-routing-targets.json" \
         "$backup_dir/opencode.jsonc" "$root/runtime/opencode-v1-adapter/load-routing-profile.sh" <<'PY'
import json
import re
import subprocess
import sys

activated_path, targets_path, backup_path, loader = sys.argv[1:]

def load(path):
    out = subprocess.run(["bash", "-c", f'source "{loader}"; load_routing_profile "{path}"'],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)

activated = load(activated_path)
targets = json.load(open(targets_path, encoding="utf-8"))

# Routing-owned keys are replaced.
assert activated["model"] == targets["default_model"], activated["model"]
for role, target in targets["agents"].items():
    row = activated["agent"][role]
    assert row["model"] == target["model"], (role, row)
    assert row["variant"] == target["variant"], (role, row)
assert activated["permission"]["task"]["breakglass"] == "deny", activated["permission"]

# Everything unrelated is preserved verbatim.
assert activated["plugin"] == ["superpowers@git+https://github.com/obra/superpowers.git#v6.3.0"]
assert activated["mcp"]["example"]["url"] == "https://example.invalid/mcp"
assert activated["theme"] == "opencode"
assert activated["permission"]["websearch"] == "allow"
assert activated["instructions"] == [".opencode/model-routing.md", "docs/house-style.md"]

# Forbidden references are gone from the activated file.
serialized = json.dumps(activated)
for forbidden in targets["forbidden_model_references"]:
    assert forbidden not in serialized, forbidden

# The backup retains the original text verbatim, comment included.
original = open(backup_path, encoding="utf-8").read()
assert "a user comment that will not survive the rewrite" in original
assert "claude-opus-4.6" in original

# A provenance header is written into the activated file.
activated_text = open(activated_path, encoding="utf-8").read()
assert re.search(r"//\s*profile_id:\s*v1-restored-2026-09", activated_text), activated_text[:400]
PY

# Ambiguous root must block, per the committed activation contract.
touch "$config_root/opencode.json"
if activate_profile --repo-profile "$root/../opencode.jsonc" \
                    --targets "$root/manifests/phase-r-routing-targets.json" \
                    --config-root "$config_root" --backup-root "$backup_root" >/dev/null 2>&1; then
  fail "activated against an ambiguous config root"
fi
rm "$config_root/opencode.json"

# Dry run must not modify anything.
before=$(sha256sum "$config_root/opencode.jsonc" | cut -d' ' -f1)
activate_profile --repo-profile "$root/../opencode.jsonc" \
                 --targets "$root/manifests/phase-r-routing-targets.json" \
                 --config-root "$config_root" --backup-root "$backup_root" --dry-run >/dev/null
assert_eq "$before" "$(sha256sum "$config_root/opencode.jsonc" | cut -d' ' -f1)"

printf 'PASS: activation routing-owned merge\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/activation-merge-test.sh
```

Expected: `FAIL: missing file: .../activate-profile.sh`.

- [ ] **Step 3: Write the activator**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
activate_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$activate_root/select-activation-target.sh"
source "$activate_root/load-routing-profile.sh"

activate_profile() {
  local repo_profile="" targets="" config_root="" backup_root="" dry_run=0
  while (( $# )); do
    case "$1" in
      --repo-profile) repo_profile=$2; shift 2 ;;
      --targets) targets=$2; shift 2 ;;
      --config-root) config_root=$2; shift 2 ;;
      --backup-root) backup_root=$2; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) printf 'activate_profile: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$repo_profile" && -n "$targets" && -n "$config_root" && -n "$backup_root" ]] || return 2

  local target stamp backup_dir before_hash after_hash commit
  target=$(select_activation_target "$config_root") || {
    printf 'activate_profile: ambiguous activation root — both opencode.json and opencode.jsonc exist\n' >&2
    return 1
  }
  [[ -f "$target" ]] || { printf 'activate_profile: no existing global config at %s\n' "$target" >&2; return 1; }

  stamp=$(date +%Y%m%dT%H%M%S%z)
  backup_dir="$backup_root/phase-r-$stamp"
  before_hash=$(sha256sum "$target" | cut -d' ' -f1)
  commit=$(git rev-parse HEAD 2>/dev/null || printf unknown)

  if (( dry_run )); then
    printf 'dry_run=1\ntarget=%s\nbefore_sha256=%s\n' "$target" "$before_hash"
    return 0
  fi

  mkdir -p "$backup_dir"
  cp "$target" "$backup_dir/$(basename "$target")"
  printf '%s  %s\n' "$before_hash" "$(basename "$target")" >"$backup_dir/SHA256SUMS"

  local merged
  merged=$(mktemp)
  REPO_JSON=$(load_routing_profile "$repo_profile") \
  GLOBAL_JSON=$(load_routing_profile "$target") \
  TARGETS="$targets" COMMIT="$commit" STAMP="$stamp" \
    python3 - "$merged" <<'PY'
import datetime
import json
import os
import sys

repo = json.loads(os.environ["REPO_JSON"])
document = json.loads(os.environ["GLOBAL_JSON"])
targets = json.load(open(os.environ["TARGETS"], encoding="utf-8"))
roles = list(targets["agents"])

# Routing-owned keys, and only these.
document["model"] = repo["model"]
document.setdefault("permission", {})
document["permission"]["task"] = repo["permission"]["task"]
document.setdefault("agent", {})
for role in roles:
    document["agent"][role] = repo["agent"][role]

undeclared = sorted(set(document["agent"]) - set(roles))
header = [
    "// OpenCode V1 routing — ACTIVATED BY PHASE R. Generated file.",
    "//",
    f"// profile_id: {targets['profile_id']}",
    f"// source_commit: {os.environ['COMMIT']}",
    f"// activated_at: {datetime.datetime.now().astimezone().isoformat()}",
    f"// activation_stamp: {os.environ['STAMP']}",
    "//",
    "// Routing-owned keys (model, permission.task, and the eleven agent rows)",
    "// come from the repository profile. Every other setting was preserved from",
    "// the previous user-global configuration. The pre-activation file, with its",
    "// original comments, is retained verbatim in the Phase-R backup directory.",
]
if undeclared:
    header += ["//", f"// NOTE: undeclared agent rows preserved unchanged: {', '.join(undeclared)}"]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("\n".join(header) + "\n")
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  mv "$merged" "$target"
  after_hash=$(sha256sum "$target" | cut -d' ' -f1)

  BACKUP_DIR="$backup_dir" TARGET="$target" BEFORE="$before_hash" AFTER="$after_hash" \
    COMMIT="$commit" python3 - "$backup_dir/manifest.json" <<'PY'
import datetime
import json
import os
import sys

document = {
    "created_at": datetime.datetime.now().astimezone().isoformat(),
    "purpose": "Phase R operational safety copy — not a supported rollback strategy",
    "backup_dir": os.environ["BACKUP_DIR"],
    "activation_target": os.environ["TARGET"],
    "pre_activation_sha256": os.environ["BEFORE"],
    "post_activation_sha256": os.environ["AFTER"],
    "source_commit": os.environ["COMMIT"],
    "committed_to_repository": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY

  printf 'backup_dir=%s\ntarget=%s\nbefore_sha256=%s\nafter_sha256=%s\n' \
    "$backup_dir" "$target" "$before_hash" "$after_hash"
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh \
         models/routing/opencode/eval/tests/activation-merge-test.sh
bash models/routing/opencode/eval/tests/activation-merge-test.sh
```

Expected: `PASS: activation routing-owned merge`. The real `~/.config/opencode/` was never touched.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh \
        models/routing/opencode/eval/tests/activation-merge-test.sh
git commit -m "test(opencode): add routing-owned activation merge"
```

---

### Task 14: Effective-routing verification tooling

Verifies the **effective resolved routing**, not file contents, for all eleven roles — from a neutral working directory and again from the repository, so a project override is detected rather than silently accepted.

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/verify-effective-routing.sh`
- Test: `models/routing/opencode/eval/tests/effective-routing-test.sh`

**Interfaces:**
- Consumes: `phase-r-routing-targets.json` (Task 2).
- Produces: `verify_effective_routing --targets M --outdir DIR --neutral-cwd DIR [--project-cwd DIR]` — resolves every role via `opencode debug agent`, writes `DIR/effective-routing.json`, exits 0 only when every role matches, no project override differs, and the forbidden Reviewer/Expert state is absent.

- [ ] **Step 1: Write the failing test**

Create `models/routing/opencode/eval/tests/effective-routing-test.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
assert_file "$root/runtime/opencode-v1-adapter/verify-effective-routing.sh"
source "$root/runtime/opencode-v1-adapter/verify-effective-routing.sh"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
targets="$root/manifests/phase-r-routing-targets.json"
mkdir -p "$workspace/neutral" "$workspace/project"

# A fake runtime that resolves each role from a JSON table, optionally with a
# project-local override when invoked from the project directory.
write_fake() {
  local overrides=$1
  cat >"$workspace/opencode" <<FAKE
#!/usr/bin/env bash
if [[ "\${1:-}" == --version ]]; then printf '1.18.27\n'; exit 0; fi
TARGETS="$targets" OVERRIDES='$overrides' PROJECT="$workspace/project" \\
  python3 -c '
import json, os, sys
role = sys.argv[1]
targets = json.load(open(os.environ["TARGETS"]))["agents"]
row = dict(targets[role])
overrides = json.loads(os.environ["OVERRIDES"] or "{}")
if os.getcwd() == os.environ["PROJECT"] and role in overrides:
    row.update(overrides[role])
provider, model = row["model"].split("/", 1)
print(json.dumps({"name": role, "mode": row["mode"] or "subagent",
                  "model": {"providerID": provider, "modelID": model},
                  "variant": row["variant"],
                  "permission": [{"permission": "task", "action": "deny", "pattern": "breakglass"}]}))
' "\$3"
FAKE
  chmod +x "$workspace/opencode"
}

write_fake '{}'
good="$workspace/good"
OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
  --outdir "$good" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project" \
  || fail "matching effective routing reported failure"
assert_contains "$(<"$good/effective-routing.json")" '"status": "PASS"'
assert_eq '11' "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["roles"]))' "$good/effective-routing.json")"

# A project override on any role must fail the routing-resolution gate.
write_fake '{"scout": {"variant": "medium"}}'
override="$workspace/override"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$override" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted a project routing override"
fi
assert_contains "$(<"$override/effective-routing.json")" '"status": "PROJECT_OVERRIDE"'

# A wrong effective value anywhere must fail.
write_fake '{}'
sed -i 's/"variant": row\["variant"\]/"variant": ("low" if role == "compaction" else row["variant"])/' "$workspace/opencode"
wrong="$workspace/wrong"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$wrong" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted compaction resolving to the wrong variant"
fi
assert_contains "$(<"$wrong/effective-routing.json")" 'compaction'

# The forbidden Reviewer/Expert state must fail even if each row looks plausible.
write_fake '{}'
sed -i 's/row = dict(targets\[role\])/row = dict(targets[role])\nif role == "expert": row["variant"] = "high"/' "$workspace/opencode"
forbidden="$workspace/forbidden"
if OPENCODE_BIN="$workspace/opencode" verify_effective_routing --targets "$targets" \
     --outdir "$forbidden" --neutral-cwd "$workspace/neutral" --project-cwd "$workspace/project"; then
  fail "accepted Reviewer Sol high together with Expert Sol high"
fi

printf 'PASS: effective routing verification\n'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash models/routing/opencode/eval/tests/effective-routing-test.sh
```

Expected: `FAIL: missing file: .../verify-effective-routing.sh`.

- [ ] **Step 3: Write the verifier**

Create `models/routing/opencode/eval/runtime/opencode-v1-adapter/verify-effective-routing.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

verify_effective_routing() {
  local targets="" outdir="" neutral_cwd="" project_cwd="" bin=${OPENCODE_BIN:-opencode}
  while (( $# )); do
    case "$1" in
      --targets) targets=$2; shift 2 ;;
      --outdir) outdir=$2; shift 2 ;;
      --neutral-cwd) neutral_cwd=$2; shift 2 ;;
      --project-cwd) project_cwd=$2; shift 2 ;;
      *) printf 'verify_effective_routing: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$targets" && -n "$outdir" && -n "$neutral_cwd" ]] || return 2

  mkdir -p "$outdir/neutral" "$outdir/project"
  local role version
  version=$("$bin" --version 2>/dev/null || printf unknown)
  while read -r role; do
    ( cd "$neutral_cwd" && "$bin" debug agent "$role" ) >"$outdir/neutral/$role.json" 2>/dev/null || true
    if [[ -n "$project_cwd" ]]; then
      ( cd "$project_cwd" && "$bin" debug agent "$role" ) >"$outdir/project/$role.json" 2>/dev/null || true
    fi
  done < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["agents"]))' "$targets")

  VERSION="$version" NEUTRAL="$outdir/neutral" PROJECT="$outdir/project" \
    python3 - "$targets" "$outdir/effective-routing.json" <<'PY'
import datetime
import json
import os
import sys

targets_path, output = sys.argv[1:]
targets = json.load(open(targets_path, encoding="utf-8"))
declared = targets["agents"]

def resolve(directory, role):
    path = os.path.join(directory, f"{role}.json")
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    model = data.get("model", {})
    task_rules = [rule for rule in data.get("permission", [])
                  if rule.get("permission") == "task"]
    breakglass = [rule.get("action") for rule in task_rules
                  if rule.get("pattern") == "breakglass"]
    return {
        "name": data.get("name"),
        "mode": data.get("mode"),
        "model": f'{model.get("providerID")}/{model.get("modelID")}',
        "variant": data.get("variant"),
        "breakglass_task_action": breakglass[-1] if breakglass else None,
    }

roles = []
mismatches = []
overrides = []
for role, target in declared.items():
    neutral = resolve(os.environ["NEUTRAL"], role)
    project = resolve(os.environ["PROJECT"], role) if os.path.isdir(os.environ["PROJECT"]) else None
    row = {"role": role, "expected": target, "neutral": neutral, "project": project}
    roles.append(row)
    if neutral is None:
        mismatches.append(f"{role}: could not resolve")
        continue
    if neutral["model"] != target["model"]:
        mismatches.append(f"{role}: model {neutral['model']} != {target['model']}")
    if neutral["variant"] != target["variant"]:
        mismatches.append(f"{role}: variant {neutral['variant']} != {target['variant']}")
    if target["mode"] is not None and neutral["mode"] != target["mode"]:
        mismatches.append(f"{role}: mode {neutral['mode']} != {target['mode']}")
    if project is not None and project != neutral:
        overrides.append(f"{role}: project resolution differs from neutral resolution")

lookup = {row["role"]: (row["neutral"] or {}) for row in roles}
forbidden = targets["forbidden_effective_state"]
if (lookup.get("reviewer", {}).get("model") == forbidden["reviewer"]["model"]
        and lookup.get("reviewer", {}).get("variant") == forbidden["reviewer"]["variant"]
        and lookup.get("expert", {}).get("model") == forbidden["expert"]["model"]
        and lookup.get("expert", {}).get("variant") == forbidden["expert"]["variant"]):
    mismatches.append("forbidden effective state: Reviewer Sol high together with Expert Sol high")

breakglass = lookup.get("breakglass", {})
if breakglass.get("mode") != "primary":
    mismatches.append(f"breakglass mode {breakglass.get('mode')} != primary")
for role in ("plan", "build", "general"):
    if lookup.get(role, {}).get("breakglass_task_action") != "deny":
        mismatches.append(f"{role}: effective Task permission does not deny breakglass")

status = "PASS"
if overrides:
    status = "PROJECT_OVERRIDE"
elif mismatches:
    status = "MISMATCH"
document = {
    "captured_at": datetime.datetime.now().astimezone().isoformat(),
    "runtime_version": os.environ["VERSION"].strip(),
    "evidence_mechanism": "opencode debug agent, neutral and project working directories",
    "prompt_behavior_used_as_oracle": False,
    "status": status,
    "mismatches": mismatches,
    "project_overrides": overrides,
    "roles": roles,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
raise SystemExit(0 if status == "PASS" else 1)
PY
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
chmod +x models/routing/opencode/eval/runtime/opencode-v1-adapter/verify-effective-routing.sh \
         models/routing/opencode/eval/tests/effective-routing-test.sh
bash models/routing/opencode/eval/tests/effective-routing-test.sh
```

Expected: `PASS: effective routing verification`.

- [ ] **Step 5: Commit**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/verify-effective-routing.sh \
        models/routing/opencode/eval/tests/effective-routing-test.sh
git commit -m "test(opencode): verify effective resolved routing"
```

---

### Task 15: Pre-activation validation gate

The last checkpoint before the workstation is touched. If anything here fails, **fix the repository state forward and do not activate.**

**Files:** none modified.

- [ ] **Step 1: Run every required check**

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
bash -n environments/linux/install.sh
shellcheck models/routing/opencode/eval/runtime/opencode-v1-adapter/*.sh \
           models/routing/opencode/eval/tests/*-test.sh || true
```

Expected: every eval test `PASS`, installer suite green, no whitespace errors, installer syntax clean. Treat shellcheck output as advisory here — the existing harness is not shellcheck-clean by contract — but fix anything it reports in files this plan created.

- [ ] **Step 2: Confirm the repository target profile is structurally correct**

```bash
bash models/routing/opencode/eval/tests/routing-profile-test.sh
source models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh
load_routing_profile models/routing/opencode/opencode.jsonc \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for role,row in d["agent"].items():
    print(f"{role:11} {row.get(\"model\"):32} {row.get(\"variant\")}")
print("default:", d["model"])
'
```

Expected: eleven rows exactly matching the target table, default `github-copilot/claude-opus-5`.

- [ ] **Step 3: Confirm the workstation is still in the preflight-approved state**

```bash
opencode --version
ls ~/.config/opencode/opencode.json 2>/dev/null && echo "STOP: opencode.json present" || echo "opencode.json absent (correct)"
sha256sum ~/.config/opencode/opencode.jsonc
for v in OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR; do printf '%s=%s\n' "$v" "${!v-<unset>}"; done
source models/routing/opencode/eval/runtime/opencode-v1-adapter/select-activation-target.sh
select_activation_target ~/.config/opencode && echo "selector READY"
```

Expected: `1.18.27`; `opencode.json absent (correct)`; SHA-256 `b996dc7d596b164337aca23cf60e00d4c5dcc5e4852d7475bcab3a8f1cc15e32`; all three variables `<unset>`; selector prints the JSONC path and `selector READY`.

**STOP condition:** any deviation. Do not re-run configuration normalization inside Phase R.

- [ ] **Step 4: Dry-run the activation and inspect the diff before committing to it**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh
activate_profile --repo-profile models/routing/opencode/opencode.jsonc \
                 --targets models/routing/opencode/eval/manifests/phase-r-routing-targets.json \
                 --config-root ~/.config/opencode \
                 --backup-root ~/.config/opencode/backups --dry-run
```

Expected: `dry_run=1`, the target path, and the unchanged `before_sha256`. Confirm the file on disk is untouched.

---

### Task 16: Activate the complete restored profile

One write. Eleven rows, the Expert bump and Breakglass land together; there is no supported partial state.

**Files:**
- Modify (uncommitted, local only): `~/.config/opencode/opencode.jsonc`
- Create (uncommitted, local only): `~/.config/opencode/backups/phase-r-<timestamp>/`
- Modify: `models/routing/opencode/eval/manifests/installed-profile.json`

- [ ] **Step 1: Take the fresh Phase-R backup and activate**

The Phase-0 preflight backup at `~/.config/opencode/backups/pre-phase-r-20260903T190513+0200/` is historical evidence and must remain untouched. `activate_profile` creates a **new** timestamped directory.

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/activate-profile.sh
activate_profile --repo-profile models/routing/opencode/opencode.jsonc \
                 --targets models/routing/opencode/eval/manifests/phase-r-routing-targets.json \
                 --config-root ~/.config/opencode \
                 --backup-root ~/.config/opencode/backups \
  | tee "$SCRATCH/activation.txt"
```

Expected output: `backup_dir=`, `target=`, `before_sha256=`, `after_sha256=`. Record all four locally. **Do not commit any of them into the repository, and do not commit the global file or the backup contents.**

- [ ] **Step 2: Verify the backup is complete and the historical one is intact**

```bash
backup_dir=$(grep '^backup_dir=' "$SCRATCH/activation.txt" | cut -d= -f2-)
ls -la "$backup_dir"
cat "$backup_dir/SHA256SUMS"
sha256sum -c "$backup_dir/SHA256SUMS" 2>/dev/null || (cd "$backup_dir" && sha256sum -c SHA256SUMS)
ls ~/.config/opencode/backups/
```

Expected: the new `phase-r-*` directory contains `opencode.jsonc`, `SHA256SUMS` and `manifest.json`; the checksum verifies; `pre-phase-r-20260903T190513+0200/` is still present and unmodified.

- [ ] **Step 3: Confirm unrelated global settings survived**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh
load_routing_profile ~/.config/opencode/opencode.jsonc \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("plugin:", d.get("plugin"))
print("instructions:", d.get("instructions"))
print("permission.websearch:", d.get("permission",{}).get("websearch"))
print("permission.task:", d.get("permission",{}).get("task"))
print("agent rows:", sorted(d.get("agent",{})))
'
```

Expected: the `superpowers@...#v6.3.0` plugin entry intact, `instructions` intact, `websearch: allow` intact, `task` now denying `breakglass`, and exactly the eleven declared agent rows.

- [ ] **Step 4: Update the installed-profile manifest**

Rewrite `models/routing/opencode/eval/manifests/installed-profile.json`, filling in the real values recorded above:

```json
{
  "profile_id": "v1-restored-2026-09",
  "source_commit": "<the Phase-R routing commit SHA from Task 7>",
  "installed_at": "<ISO-8601 activation timestamp>",
  "opencode_version": "1.18.27",
  "activation_target": "~/.config/opencode/opencode.jsonc",
  "activation_scope": "user-global",
  "effective_resolved_routing": null,
  "effective_routing_evidence": "eval/records/phase-r/effective-routing.json",
  "canonical": false,
  "provenance_ceiling": "Ordinary sessions are attributable only to the profile known to be installed at the time.",
  "global_configuration_contents_committed": false
}
```

`canonical` stays `false` and `effective_resolved_routing` stays `null` until Task 17 fills them in. Do not mark the profile canonical yet.

- [ ] **Step 5: Commit the manifest only**

```bash
git add models/routing/opencode/eval/manifests/installed-profile.json
git commit -m "chore(opencode): record Phase R activation in the installed-profile manifest"
git status --short
```

Expected: clean tree. Confirm no global-configuration or backup file was staged.

---

### Task 17: Verify effective routing and revalidate security boundaries

Effective routing, not file contents, is authoritative. Then re-prove every security boundary against the **real activated profile** using structured permission and inventory evidence — prompt behavior is never the oracle.

**Files:**
- Create: `models/routing/opencode/eval/records/phase-r/effective-routing.json`
- Create: `models/routing/opencode/eval/records/phase-r/security/{reviewer,expert,breakglass-non-exposure,breakglass-primary}.json`
- Modify: `models/routing/opencode/eval/manifests/installed-profile.json`

- [ ] **Step 1: Verify effective resolved routing from a neutral context**

Use the neutral-context approach the activation preflight established.

```bash
mkdir -p /tmp/opencode models/routing/opencode/eval/records/phase-r
source models/routing/opencode/eval/runtime/opencode-v1-adapter/verify-effective-routing.sh
set +e
verify_effective_routing \
  --targets models/routing/opencode/eval/manifests/phase-r-routing-targets.json \
  --outdir "$SCRATCH/effective" \
  --neutral-cwd /tmp/opencode \
  --project-cwd "$PWD"
echo "exit=$?"
set -e
cp "$SCRATCH/effective/effective-routing.json" models/routing/opencode/eval/records/phase-r/
python3 -c '
import json
d = json.load(open("models/routing/opencode/eval/records/phase-r/effective-routing.json"))
print("status:", d["status"])
for m in d["mismatches"]: print("MISMATCH:", m)
for o in d["project_overrides"]: print("OVERRIDE:", o)
for row in d["roles"]:
    n = row["neutral"] or {}
    print(f"{row[\"role\"]:11} {n.get(\"model\"):32} {n.get(\"variant\"):7} {n.get(\"mode\")}")
'
```

Expected: `status: PASS`, no mismatches, no overrides, eleven rows matching the target table.

**STOP conditions:** `status: PROJECT_OVERRIDE` → the routing-resolution gate FAILS; stop the normal Phase-R sequence and diagnose forward. `status: MISMATCH` → the routing-resolution gate FAILS; correct the repository forward and re-activate. Never edit the global file by hand to make the gate pass.

- [ ] **Step 2: Revalidate the Reviewer and Expert read-only boundaries**

```bash
mkdir -p models/routing/opencode/eval/records/phase-r/security
source models/routing/opencode/eval/runtime/opencode-v1-adapter/capture-permissions.sh
for role in reviewer expert; do
  ( cd /tmp/opencode && OPENCODE_BIN=opencode bash -c "
      source $PWD/models/routing/opencode/eval/runtime/opencode-v1-adapter/capture-permissions.sh
      capture_agent_permissions $role /dev/stdout" ) \
    >"models/routing/opencode/eval/records/phase-r/security/$role.json"
  validate_agent_permissions "$role" "models/routing/opencode/eval/records/phase-r/security/$role.json" \
    && echo "$role boundary PASS" || echo "$role boundary FAIL"
done
cat models/routing/opencode/eval/records/phase-r/security/reviewer.json
cat models/routing/opencode/eval/records/phase-r/security/expert.json
```

Expected: both `PASS`. Reviewer must show `model: github-copilot/gpt-5.6-sol`, `variant: high`, `edit: deny`, `task: deny`, bash wildcard `deny` with exactly the four `git` allowlist patterns. Expert must show `model: openai/gpt-5.6-sol`, `variant: xhigh`, and `bash`/`webfetch`/`websearch`/`task`/`apply_patch` all denied or false.

Any security regression **BLOCKS Phase R**. Diagnose forward.

- [ ] **Step 3: Revalidate the Breakglass boundary against the activated profile**

```bash
( cd /tmp/opencode && opencode debug agent build ) >"$SCRATCH/build-resolved.json"
( cd /tmp/opencode && opencode debug agent breakglass ) >"$SCRATCH/breakglass-resolved.json"
python3 - "$SCRATCH/build-resolved.json" "$SCRATCH/breakglass-resolved.json" \
         models/routing/opencode/eval/records/phase-r/security/breakglass-non-exposure.json <<'PY'
import datetime, fnmatch, json, sys
build_path, breakglass_path, output = sys.argv[1:]
build = json.load(open(build_path, encoding="utf-8"))
breakglass = json.load(open(breakglass_path, encoding="utf-8"))
actions = [r.get("action") for r in build.get("permission", [])
           if r.get("permission") == "task" and fnmatch.fnmatchcase("breakglass", r.get("pattern", ""))]
action = actions[-1] if actions else None
model = breakglass.get("model", {})
resolved_primary = (breakglass.get("name") == "breakglass"
                    and breakglass.get("mode") == "primary"
                    and model.get("providerID") == "openai"
                    and model.get("modelID") == "gpt-5.6-sol"
                    and breakglass.get("variant") == "max")
passed = action == "deny" and resolved_primary
record = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "profile": "v1-restored-2026-09 (activated user-global)",
    "evidence_mechanism": "resolved_permission_and_inventory",
    "task_schema_directly_exposed": False,
    "normal_agent_breakglass_task_action": action,
    "breakglass_mode": breakglass.get("mode"),
    "breakglass_model": f'{model.get("providerID")}/{model.get("modelID")}',
    "breakglass_variant": breakglass.get("variant"),
    "normal_agent_non_exposure": passed,
    "hidden_used_as_security_control": False,
    "prompt_behavior_used_as_oracle": False,
}
json.dump(record, open(output, "w", encoding="utf-8"), indent=2)
open(output, "a", encoding="utf-8").write("\n")
print("breakglass non-exposure:", "PASS" if passed else "FAIL")
raise SystemExit(0 if passed else 1)
PY
```

Expected: `breakglass non-exposure: PASS`, `normal_agent_breakglass_task_action: "deny"`, `breakglass_mode: "primary"`, `breakglass_model: "openai/gpt-5.6-sol"`, `breakglass_variant: "max"`.

- [ ] **Step 4: Confirm explicit human primary selection still works**

This is one model-bearing call on direct OpenAI. Admit it against the ledger first.

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger=models/routing/opencode/eval/records/phase-r/budget-ledger.json
ledger_admit "$ledger" evaluation 5 && echo "admitted" || echo "STOP: budget exhausted"

source models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh
printf 'Reply with exactly: BREAKGLASS_PRIMARY_OK\n' >"$SCRATCH/bg-prompt.txt"
( cd /tmp/opencode && OPENCODE_BIN=opencode bash -c "
    source $PWD/models/routing/opencode/eval/runtime/opencode-v1-adapter/dispatch-fixture.sh
    dispatch_fixture --outdir '$SCRATCH/bg' --label breakglass-primary \
      --prompt-file '$SCRATCH/bg-prompt.txt' --agent breakglass --ledger '$PWD/$ledger'" )
grep -c 'BREAKGLASS_PRIMARY_OK' "$SCRATCH/bg/response.txt"
cp "$SCRATCH/bg/dispatch.json" models/routing/opencode/eval/records/phase-r/security/breakglass-primary.json
```

Expected: `classification: "OK"` and the response containing exactly `BREAKGLASS_PRIMARY_OK`.

If this fails with a provider/quota/auth error, `dispatch.json` records `failure_class` — that is an external block, not a security regression. Record it and report; do not retry until green.

- [ ] **Step 5: Fill in the installed-profile manifest**

Set `effective_resolved_routing` to the eleven resolved rows from `effective-routing.json` (role → provider/model, variant, mode). Leave `canonical: false` — the profile becomes canonical only after every gate in Tasks 18–21 passes.

- [ ] **Step 6: Commit the evidence**

```bash
git add models/routing/opencode/eval/records/phase-r/effective-routing.json \
        models/routing/opencode/eval/records/phase-r/security/ \
        models/routing/opencode/eval/manifests/installed-profile.json
git commit -m "test(opencode): record Phase R routing and security revalidation"
git status --short
```

Expected: clean tree, and no global configuration or backup content staged.

---

### Task 18: Execute the deterministic Build restoration gate

Runs the committed fixture against the activated `build` agent (Opus 5 high). The **committed state machine in `eval/decision-rules/build-gate.sh` decides the outcome** — this task executes attempts and records classifications; it never reruns until three green results appear.

**Files:**
- Create: `models/routing/opencode/eval/records/phase-r/build/attempt-N/`
- Create: `models/routing/opencode/eval/records/phase-r/build/classification-ledger.txt`
- Create: `models/routing/opencode/eval/records/phase-r/build/outcome.json`

- [ ] **Step 1: Prepare the append-only classification ledger**

```bash
mkdir -p models/routing/opencode/eval/records/phase-r/build
: >models/routing/opencode/eval/records/phase-r/build/classification-ledger.txt
source models/routing/opencode/eval/decision-rules/build-gate.sh
```

- [ ] **Step 2: Check budget admission before each attempt**

Before **every** attempt, run:

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger=models/routing/opencode/eval/records/phase-r/budget-ledger.json
spent=$(ledger_spent "$ledger" evaluation)
echo "evaluation spent: $spent / 100"
ledger_admit "$ledger" evaluation 15 && echo "admitted" || echo "STOP: evaluation budget exhausted"
```

If admission fails, **STOP Phase R** and report the budget exhaustion. Do not charge planned gate runs to the recovery budget: recovery is only for diagnosis after a genuine gate failure.

- [ ] **Step 3: Run the first three valid attempts**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-build-restoration-gate.sh
for n in 1 2 3; do
  set +e
  run_build_restoration_gate \
    --outdir "models/routing/opencode/eval/records/phase-r/build/attempt-$n" \
    --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json \
    --attempt "$n"
  echo "attempt $n exit=$?"
  set -e
done
python3 -c '
import glob, json
for path in sorted(glob.glob("models/routing/opencode/eval/records/phase-r/build/attempt-*/attempt.json")):
    d = json.load(open(path))
    print(f"attempt {d[\"attempt\"]}: oracle_passed={d[\"oracle_passed\"]} dispatch={d[\"dispatch\"][\"classification\"]} credits={d[\"dispatch\"][\"derived_credits\"]}")
'
```

- [ ] **Step 4: Classify every failed attempt BEFORE any retry or extension**

For each attempt where `oracle_passed` is `false`, choose exactly one class from the committed taxonomy and append it to the hash-chained ledger **before** running anything else:

- `INVALID_ENVIRONMENT` — harness failure, authentication failure, provider/network outage, corrupted workspace, external dependency failure. Requires evidence. Excluded from the model result; a replacement run is allowed. `dispatch.classification` of `TIMEOUT`, `INVALID_ENVIRONMENT` or `CAPABILITY_REGRESSION` is the evidence.
- `VALID_CONTROLLER_FAILURE` — environment healthy (`dispatch.classification == "OK"`), fixture unchanged, mechanical oracle failed. **Permanently counts in the denominator and may not be erased by retrying.**
- `FIXTURE_DEFECT` — broken or contradictory task, incorrect test or oracle, impossible requirement. **Invalidates the whole fixture evaluation.** Repair the fixture and restart the gate from zero.

A task being difficult is never an invalidation reason.

```bash
append_classification models/routing/opencode/eval/records/phase-r/build/classification-ledger.txt \
  VALID_CONTROLLER_FAILURE "attempt-2 dispatch classification OK; oracle exit 1; acceptance suite red"
validate_classification_ledger models/routing/opencode/eval/records/phase-r/build/classification-ledger.txt \
  && echo "ledger intact"
next_run_action models/routing/opencode/eval/records/phase-r/build/classification-ledger.txt
```

- [ ] **Step 5: Ask the committed state machine for the verdict**

```bash
successes=$(python3 -c '
import glob, json
print(sum(json.load(open(p))["oracle_passed"] for p in glob.glob("models/routing/opencode/eval/records/phase-r/build/attempt-*/attempt.json")))
')
valid=3
build_gate "$successes" "$valid"
```

Apply the printed verdict exactly:

- `pass` (3/3) → the Build gate PASSES. Go to Step 7.
- `classify_then_extend` (2/3) → the failure must already be classified. If it is `VALID_CONTROLLER_FAILURE`, extend the **same** evaluation to five total valid runs (Step 6). If it is `INVALID_ENVIRONMENT`, exclude that run and take one replacement attempt, then re-evaluate at `valid=3`. If it is `FIXTURE_DEFECT`, repair the fixture and restart the whole gate from zero.
- `block_fixture_control` (0/3 or 1/3) → **BLOCK Phase R.** Run the fixture control (Step 8) before any conclusion about Opus 5.

- [ ] **Step 6: n=5 escalation, only from a genuine 2/3**

The original valid failure stays in the denominator, so `5/5` is unreachable by construction.

```bash
for n in 4 5; do
  ledger_admit models/routing/opencode/eval/records/phase-r/budget-ledger.json evaluation 15 \
    || { echo "STOP: evaluation budget exhausted"; break; }
  set +e
  run_build_restoration_gate \
    --outdir "models/routing/opencode/eval/records/phase-r/build/attempt-$n" \
    --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json --attempt "$n"
  set -e
done
successes=$(python3 -c '
import glob, json
print(sum(json.load(open(p))["oracle_passed"] for p in glob.glob("models/routing/opencode/eval/records/phase-r/build/attempt-*/attempt.json")))
')
build_gate "$successes" 5
```

`pass` (≥4/5) → the Build gate PASSES. `block_fixture_control` (≤3/5) → BLOCK; run the fixture control.

- [ ] **Step 7: Record the outcome**

Write `models/routing/opencode/eval/records/phase-r/build/outcome.json`:

```json
{
  "fixture": "build-restoration-gate",
  "target": {"role": "build", "model": "github-copilot/claude-opus-5", "variant": "high"},
  "valid_runs": 3,
  "successes": 3,
  "individual_results": [{"attempt": 1, "oracle_passed": true}],
  "classifications": [],
  "escalated_to_n5": false,
  "state_machine": "eval/decision-rules/build-gate.sh::build_gate",
  "verdict": "pass",
  "fixture_control_run": false,
  "interpretation_note": "Passing establishes minimum operational viability, not a reliability estimate. Three to five valid runs cannot distinguish a 95% reliable controller from an 85% reliable one and must not be used as an SLO or success-rate claim.",
  "phase_3_admissible": false
}
```

Fill in the real counts, the real per-attempt results, and every recorded classification.

- [ ] **Step 8: Fixture control — only if Opus is blocked**

Before concluding Opus 5 is unsuitable, run the **same** deterministic gate against Sonnet 5 at n=3. This is diagnostic evidence only and is **inadmissible as Phase-3 model-selection evidence**. It does not authorize switching production Build to Sonnet.

```bash
source models/routing/opencode/eval/scoring/build-control.sh
for n in 1 2 3; do
  ledger_admit models/routing/opencode/eval/records/phase-r/budget-ledger.json recovery 20 \
    || { echo "STOP: recovery budget exhausted"; break; }
  set +e
  run_build_restoration_gate \
    --outdir "models/routing/opencode/eval/records/phase-r/build-control/attempt-$n" \
    --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json --attempt "$n" \
    --model github-copilot/claude-sonnet-5 --variant high
  set -e
done
sonnet_passes=$(python3 -c '
import glob, json
print(sum(json.load(open(p))["oracle_passed"] for p in glob.glob("models/routing/opencode/eval/records/phase-r/build-control/attempt-*/attempt.json")))
')
build_control_interpretation blocked "$sonnet_passes"
```

Interpretations, applied exactly: `practically-passable-open-remediation` (Sonnet ≥2/3) — the fixture is passable, Opus remains blocked, open an explicit Build remediation decision. `ambiguous-fixture-difficulty` (1/3) — diagnose; do not conclude Opus is unsuitable. `strong-fixture-finding-repair` (0/3) — inspect and repair the fixture, then restart the Build restoration gate from zero.

Fixture-control runs are charged to the **recovery** budget because they follow a genuine gate failure.

- [ ] **Step 9: Commit**

```bash
git add models/routing/opencode/eval/records/phase-r/build/
git commit -m "test(opencode): record Phase R build restoration gate"
```

---

### Task 19: Execute the Reviewer gate

**Files:**
- Create: `models/routing/opencode/eval/records/phase-r/reviewer/`

- [ ] **Step 1: Note the pricing regime before running**

```bash
date +%F
```

If the date is **before** `2026-09-04`: the Reviewer/Sol run is `promotional`. The quality evidence is valid; the observed cost is **not** the canonical steady-state Reviewer cost reference. If the date is **on or after** `2026-09-04`: record the post-promotional regime, and this observation may become the canonical Reviewer/Sol steady-state cost reference. Do not re-run quality fixtures solely to obtain a different cost regime when the cost can be measured separately.

- [ ] **Step 2: Admit the budget and run the gate**

Six dispatches: five seeded cases plus the clean control.

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger_admit models/routing/opencode/eval/records/phase-r/budget-ledger.json evaluation 6 \
  || { echo "STOP: evaluation budget exhausted"; exit 1; }
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-reviewer-gate.sh
set +e
run_reviewer_gate --outdir models/routing/opencode/eval/records/phase-r/reviewer \
                  --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json
echo "dispatch health exit=$?"
set -e
```

- [ ] **Step 3: Let the committed scorer decide**

```bash
source models/routing/opencode/eval/scoring/reviewer.sh
reviewer_structured_gate \
  models/routing/opencode/eval/fixtures/reviewer-seeded-defects/oracle.json \
  models/routing/opencode/eval/records/phase-r/reviewer/findings.json
python3 -c '
import json
f = json.load(open("models/routing/opencode/eval/records/phase-r/reviewer/findings.json"))
for item in f["seeded"]:
    print(f"{item[\"id\"]:14} {item[\"severity\"]:10} {item[\"summary\"][:70]}")
print("clean material findings:", [c for c in f["clean"] if c["severity"] in ("material","blocking")])
'
```

Required: `pass` — 5/5 seeded material defects detected against the ground-truth IDs `R-CONCURRENCY`, `R-AUTH`, `R-API`, `R-BOUNDARY`, `R-ERROR`, and 0 material or blocking findings on the clean control. Non-material suggestions on the clean control may be recorded but are not gating.

`block` → **BLOCK Phase R.** Do not change Reviewer to `xhigh` inside Phase R; a Reviewer effort experiment belongs to Phase 3 under its approved conditions. Classify the failure, diagnose forward, and rerun the anchored gate.

- [ ] **Step 4: Record the outcome and commit**

Write `models/routing/opencode/eval/records/phase-r/reviewer/outcome.json` with the target (`github-copilot/gpt-5.6-sol` `high`), the per-ID detections, the clean-control result, the scorer's `pass`/`block` string as `verdict` (read by Task 23), the pricing regime, and `canonical_cost_reference: false` if the run predates 2026-09-04.

```bash
git add models/routing/opencode/eval/records/phase-r/reviewer/
git commit -m "test(opencode): record Phase R reviewer seeded-defect gate"
```

---

### Task 20: Execute the Explore gate

**Files:**
- Create: `models/routing/opencode/eval/records/phase-r/explore/`

- [ ] **Step 1: Admit the budget and run the gate**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger_admit models/routing/opencode/eval/records/phase-r/budget-ledger.json evaluation 2 \
  || { echo "STOP: evaluation budget exhausted"; exit 1; }
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-explore-gate.sh
set +e
run_explore_gate --outdir models/routing/opencode/eval/records/phase-r/explore \
                 --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json
echo "dispatch health exit=$?"
set -e
cat models/routing/opencode/eval/records/phase-r/explore/actual.json
```

- [ ] **Step 2: Let the committed oracle decide**

```bash
source models/routing/opencode/eval/scoring/explore.sh
explore_gate models/routing/opencode/eval/fixtures/explore-dependency-chain/oracle.json \
             models/routing/opencode/eval/records/phase-r/explore/actual.json
```

PASS requires **all four** simultaneously: the ordered path `entry -> facade -> service -> adapter -> protocol`, exactly 4 hops, terminal symbol `PROTOCOL_VERSION`, terminal value `v3`. Prose quality is not scored, and finding `v3` alone is not sufficient.

`block` → **BLOCK Phase R.** Diagnose forward and rerun the anchored gate.

- [ ] **Step 3: Record the outcome and commit**

Write `models/routing/opencode/eval/records/phase-r/explore/outcome.json` with the target (`github-copilot/gpt-5.6-luna` `medium`), the reported ordered path, hop count, terminal symbol and terminal value, the scorer's `pass`/`block` string as `verdict` (read by Task 23), and `prose_quality_scored: false`.

```bash
git add models/routing/opencode/eval/records/phase-r/explore/
git commit -m "test(opencode): record Phase R explore dependency-chain gate"
```

---

### Task 21: Execute the Compaction gate

**Files:**
- Create: `models/routing/opencode/eval/records/phase-r/compaction/`

- [ ] **Step 1: Admit the budget and run the gate**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger_admit models/routing/opencode/eval/records/phase-r/budget-ledger.json evaluation 2 \
  || { echo "STOP: evaluation budget exhausted"; exit 1; }
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-compaction-gate.sh
set +e
run_compaction_gate --outdir models/routing/opencode/eval/records/phase-r/compaction \
                    --ledger models/routing/opencode/eval/records/phase-r/budget-ledger.json
echo "dispatch health exit=$?"
set -e
cat models/routing/opencode/eval/records/phase-r/compaction/actual.json
```

- [ ] **Step 2: Let the committed scorer decide**

```bash
source models/routing/opencode/eval/scoring/compaction.sh
compaction_structured_gate \
  models/routing/opencode/eval/fixtures/compaction-invariants/oracle.json \
  models/routing/opencode/eval/records/phase-r/compaction/actual.json
```

Required: `pass` — `INV-RUNTIME`, `INV-BREAKGLASS`, `INV-BUDGET` and `INV-FAILURE` all 4/4 semantically preserved (canonical value or a committed alias), with 0 contradictions.

`block` → **BLOCK Phase R.** Do not weaken the gate for cost or latency, and do not edit the oracle. Diagnose forward and rerun.

- [ ] **Step 3: Record the outcome and commit**

Write `models/routing/opencode/eval/records/phase-r/compaction/outcome.json` with the target (`github-copilot/gpt-5.6-terra` `medium`), the per-invariant preservation result for all four IDs, the contradiction list, the scorer's `pass`/`block` string as `verdict` (read by Task 23), and `gate_weakened_for_cost_or_latency: false`.

```bash
git add models/routing/opencode/eval/records/phase-r/compaction/
git commit -m "test(opencode): record Phase R compaction invariant gate"
```

---

### Task 22: Budget, pricing and the Phase-R evidence record

**Files:**
- Create: `models/routing/opencode/docs/evidence/2026-09-03-phase-r-execution.md`
- Modify: `models/routing/opencode/eval/records/phase-r/budget-ledger.json` (final accounting)

- [ ] **Step 1: Close the budget accounting**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/budget-ledger.sh
ledger=models/routing/opencode/eval/records/phase-r/budget-ledger.json
echo "evaluation: $(ledger_spent "$ledger" evaluation) / 100"
echo "recovery:   $(ledger_spent "$ledger" recovery) / 250"
python3 -c '
import json
d = json.load(open("models/routing/opencode/eval/records/phase-r/budget-ledger.json"))
for e in d["entries"]:
    print(f"{e[\"account\"]:11} {e[\"label\"]:28} {e[\"provider\"]:15} {e[\"credits\"]}")
print("organization guardrail:", d["organization_guardrail_credits"], "-", d["at_guardrail"])
'
```

Record both totals. The organization guardrail is externally enforced by GitHub billing; this repository holds no current billing snapshot, so report guardrail status as "externally enforced; no current headroom snapshot available". Do not create an OpenCode-native spending cap.

- [ ] **Step 2: Record non-gating observations**

Collect wall-clock, credits, tokens, turns, retries and cold/warm cache behavior from every `dispatch.json`. These are **recorded, not gating**. Do not retune the frozen thresholds in `eval/thresholds/continuous.json` after seeing Phase-R results — the very high comparable-credit separation threshold (`2194.8831%`) remains valid evidence that cost is currently weak and non-discriminating under the measured cache regime. If units are incompatible, record `cost comparison: unavailable` rather than synthesizing compatibility.

- [ ] **Step 3: Write the Phase-R evidence record**

Create `models/routing/opencode/docs/evidence/2026-09-03-phase-r-execution.md` covering, at minimum:

```
Phase R status
OpenCode version
routing profile ID and commit
activation timestamp and target path
exact effective routing map (11 rows, with variants and modes)

capability-forced rows:  plan, build, general
  reason: github-copilot/claude-opus-4.6 MODEL_UNRESOLVABLE / ProviderModelNotFoundError
risk-decision rows:      explore, scout, reviewer, compaction, title, summary
  reason: explicit decision not to depend on GPT-5.3-Codex for the staged
          migration; Codex still resolved at the recorded capability check

Expert bump result (high -> xhigh) and the atomic ordering guarantee
Breakglass row: openai/gpt-5.6-sol max primary, Task-denied to normal agents

fresh capability preflight results (11 combinations)
Build individual valid run outcomes, classifications, any n=5 escalation,
  any Sonnet fixture control
Reviewer outcomes (per seeded ID + clean control)
Explore outcome
Compaction outcome
security outcomes (Reviewer, Expert, Breakglass non-exposure, Breakglass primary)

evaluation credits consumed / 100
recovery credits consumed / 250
organization guardrail status

pricing regime and canonical Reviewer cost-reference status
installed-profile manifest state
the runner architecture note: one shared dispatch primitive, four thin
  adapters, committed oracles unmodified
the Reviewer normalization limitation stated in Known Risks
```

Also quote the pre-restoration failure output captured in Task 2 Step 3, as the §5 evidence that the invariants genuinely failed before the change.

**Do not commit** user-global configuration contents, resolved-config dumps, backup contents, or any secret.

- [ ] **Step 4: Commit**

```bash
git add models/routing/opencode/docs/evidence/2026-09-03-phase-r-execution.md \
        models/routing/opencode/eval/records/phase-r/budget-ledger.json
git commit -m "docs(opencode): record Phase R execution evidence"
```

---

### Task 23: Establish the restored reference profile

**Only after every Phase-R gate has passed.** If any gate is blocked, skip this task and leave the system in the documented forward-recovery state.

**Files:**
- Create: `models/routing/opencode/profiles/v1-restored-2026-09.jsonc`
- Modify: `models/routing/opencode/eval/manifests/installed-profile.json`
- Modify: `models/routing/opencode/README.md`

- [ ] **Step 1: Confirm every gate passed**

```bash
python3 -c '
import json, pathlib
base = pathlib.Path("models/routing/opencode/eval/records/phase-r")
print("routing:   ", json.load(open(base/"effective-routing.json"))["status"])
print("build:     ", json.load(open(base/"build/outcome.json"))["verdict"])
for name in ("reviewer", "explore", "compaction"):
    p = base/name/"outcome.json"
    print(f"{name+\":\":11}", json.load(open(p))["verdict"] if p.exists() else "MISSING")
print("breakglass:", json.load(open(base/"security/breakglass-non-exposure.json"))["normal_agent_non_exposure"])
'
```

Required: routing `PASS`, build `pass`, reviewer `pass`, explore `pass`, compaction `pass`, breakglass `true`, plus the Reviewer and Expert permission boundaries `PASS` from Task 17.

- [ ] **Step 2: Capture the restored profile**

```bash
cp models/routing/opencode/opencode.jsonc models/routing/opencode/profiles/v1-restored-2026-09.jsonc
```

Prepend this header above the existing first line:

```jsonc
// RESTORED REFERENCE PROFILE — the exact production routing that passed Phase R.
//
// profile_id:     v1-restored-2026-09
// source_commit:  <Phase-R routing commit SHA>
// opencode:       1.18.27
// passed:         routing resolution, Reviewer/Expert permission boundaries,
//                 Breakglass boundary, Build restoration gate, Reviewer
//                 seeded-defect and clean-control gate, Explore four-hop
//                 dependency gate, Compaction 4/4 invariant gate
//
// This is the forward quality reference, the forward operational reference,
// the rollback target for FUTURE optimization changes, and the Phase-3
// starting baseline. It is NOT retroactively a Phase-R rollback target:
// Phase R had no supported rollback.
//
// profiles/baseline-2026-08.jsonc remains the untouched historical record.
```

- [ ] **Step 3: Confirm the historical baseline was not rewritten**

```bash
git log --oneline -- models/routing/opencode/profiles/baseline-2026-08.jsonc
git diff --stat main -- models/routing/opencode/profiles/baseline-2026-08.jsonc
```

Expected: exactly one commit (Task 3), and no further modification.

- [ ] **Step 4: Mark the installed profile canonical**

In `models/routing/opencode/eval/manifests/installed-profile.json`, set `canonical: true` and add `restored_profile: "profiles/v1-restored-2026-09.jsonc"`.

- [ ] **Step 5: Point the README at the restored reference**

Add a short section noting that `profiles/v1-restored-2026-09.jsonc` is the forward quality and operational reference and the Phase-3 starting baseline, that `profiles/baseline-2026-08.jsonc` is preserved historical evidence, and that Phase R itself had no supported rollback.

- [ ] **Step 6: Commit**

```bash
git add models/routing/opencode/profiles/v1-restored-2026-09.jsonc \
        models/routing/opencode/eval/manifests/installed-profile.json \
        models/routing/opencode/README.md
git commit -m "docs(opencode): establish restored V1 routing reference"
```

---

### Task 24: Independent review, verification, and pull request

- [ ] **Step 1: Run the complete verification set**

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
git status --short
```

Expected: every test `PASS`, installer suite green, no whitespace errors, clean tree.

- [ ] **Step 2: Verify each required claim explicitly, with output**

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/load-routing-profile.sh
echo "=== repository restored target committed ==="
load_routing_profile models/routing/opencode/opencode.jsonc | python3 -c '
import json,sys
d=json.load(sys.stdin)
for r,row in d["agent"].items(): print(f"{r:11} {row.get(\"model\"):32} {row.get(\"variant\")}")
'
echo "=== effective user-global routing matches ==="
python3 -c '
import json
d=json.load(open("models/routing/opencode/eval/records/phase-r/effective-routing.json"))
print("status:", d["status"])
for row in d["roles"]:
    n=row["neutral"]; print(f"{row[\"role\"]:11} {n[\"model\"]:32} {n[\"variant\"]:7} {n[\"mode\"]}")
'
echo "=== Opus 4.6 absent / Codex absent from effective production routing ==="
grep -c 'claude-opus-4.6\|gpt-5.3-codex' models/routing/opencode/eval/records/phase-r/effective-routing.json || echo "0 (correct)"
echo "=== markdown agents carry no routing fields ==="
grep -n 'model:\|variant:' models/routing/opencode/.opencode/agents/*.md || echo "none (correct)"
echo "=== committed oracles unmodified ==="
git diff --stat main -- models/routing/opencode/eval/scoring/ \
                        models/routing/opencode/eval/decision-rules/ \
                        models/routing/opencode/eval/fixtures/ \
                        models/routing/opencode/eval/thresholds/
```

Verify explicitly: Scout `Luna low`; Compaction `Terra medium`; Reviewer `Copilot Sol high`; Expert `direct OpenAI Sol xhigh`; Breakglass `direct OpenAI Sol max, primary, human-only boundary preserved`; the six migrated rows no longer route through Codex; no row references Opus 4.6; the installed-profile manifest is consistent; and the scoring, decision-rule, fixture and threshold trees show **zero** diff against `main`.

- [ ] **Step 3: Request independent review**

Use `superpowers:requesting-code-review`. The reviewer must specifically check the failure modes listed in the Self-Review Checklist below, and must confirm that no committed ground truth, scorer, threshold or state machine was modified.

- [ ] **Step 4: Run verification-before-completion**

Use `superpowers:verification-before-completion`. Every success claim must be backed by pasted command output. No claim of "passing" without the output that shows it.

- [ ] **Step 5: Open the pull request**

```bash
git push -u origin feat/opencode-routing-phase-r
gh pr create --base main --title "feat(opencode): restore V1 multi-model routing" --body "$(cat <<'BODY'
## Summary

Executes Phase R of the approved OpenCode V1 multi-model routing migration.

Restores the nine Copilot-hosted routing rows, raises direct OpenAI Expert from
Sol high to Sol xhigh, installs Breakglass as the eleventh production routing
row, centralizes routing authority in `opencode.jsonc`, activates the restored
routing in the user-global OpenCode configuration, and validates it against the
committed Phase-R ground-truth gates.

## Capability-forced migration

- plan
- build
- general

Reason: `github-copilot/claude-opus-4.6` — MODEL_UNRESOLVABLE /
ProviderModelNotFoundError.

## Migrated by explicit risk decision

- explore
- scout
- reviewer
- compaction
- title
- summary

Reason: explicit decision not to depend on GPT-5.3-Codex for the staged
migration. Codex still resolved at the recorded capability check; it is not
described as retired or unavailable.

## Routing authority

`opencode.jsonc` is now the single source of truth for role to model, variant
and mode. `.opencode/agents/reviewer.md` and `expert.md` carry prompts and
non-routing metadata only.

## Gate architecture

One shared dispatch primitive over the existing OpenCode V1 runtime adapter,
with four thin role adapters. The committed oracles, scorers, thresholds and
Build state machine are unmodified and remain the sole authority on pass/fail.

## Phase-R validation

- effective routing resolution
- Reviewer/Expert permission boundaries
- Breakglass boundary
- deterministic Build restoration gate
- Reviewer seeded-defect + clean-control gate
- Explore four-hop dependency gate
- Compaction 4/4 invariant gate

## Recovery semantics

- no supported rollback to historical routing
- forward-only diagnosis/bisection
- dedicated recovery budget preserved
- emergency Codex hybrid not used unless explicitly reported

## Cost/pricing

[Report actual pricing regime and canonical Reviewer cost-reference status.]

## Explicitly out of scope

- Phase 3 Build Opus-vs-Sonnet A/B
- Reviewer effort optimization
- General challengers
- Phase 4 Expert experiments

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

Do not merge automatically unless explicitly authorized.

---

## Failure Handling — Forward Only

Phase R has no supported rollback profile. If any genuine gate fails:

1. STOP the normal Phase-R sequence.
2. Preserve the failed evidence — never erase a valid failed run.
3. Classify the failure using the committed taxonomy.
4. Identify the affected role.
5. Diagnose and bisect, charging to the **250-credit recovery budget** only after a genuine failure enters recovery.
6. Correct forward.
7. Rerun the affected anchored gate.
8. Rerun any downstream evidence the change invalidated.

Never restore Opus 4.6. Never use Codex as an ordinary rollback. Never create an undocumented hybrid. Never lower a threshold, reinterpret a capability failure, or use Phase-3 evidence to make Phase R pass.

**Emergency Codex hybrid** is an exceptional incident mitigation only, considered when Phase R materially blocks development or operations, forward recovery cannot restore operation inside the required window, and Codex passes a fresh capability gate. **Do not activate it autonomously.** It requires an incident record, a committed and tagged exact hybrid profile, a named incident owner, an explicit exit date, a forward-remediation task, and explicit human authorization. Default maximum lifetime is 2 business days. It must never become canonical, the Phase-3 baseline, or silent permanent routing.

## Hard Stops

STOP instead of improvising if: a required model or variant loses capability; the effective target routing cannot be established; the global config state is no longer the preflight-approved state; a security boundary fails; Build blocks after the committed state machine; the Reviewer, Explore or Compaction gate fails; the evaluation budget is exhausted; the recovery budget is exhausted; or a fix would require changing the approved routing architecture.

## Phase-R Success Criteria

Phase R passes only when **all** of these pass, and no others are added:

```
effective routing-resolution gate
Reviewer permission boundary
Expert permission boundary
Breakglass boundary
Build restoration gate
Reviewer seeded-defect gate
Reviewer clean-control gate
Explore dependency-chain gate
Compaction invariant gate
```

No subjective gating metrics. Non-gating observations are recorded, never promoted to gates.

## Self-Review Checklist

Verified against the plan before presenting it. Every item must be **absent**:

| Failure mode | Status |
|---|---|
| Breakglass missing from the production target table | **Absent** — eleventh row in the target table, the manifest, the profile, the invariant test (model/variant/mode plus Task-denial), the effective-routing verifier, the installed manifest, the restored snapshot and the evidence record. |
| Reviewer/Expert model authority duplicated between JSONC and markdown | **Absent** — Task 7 removes `model:`/`variant:` from both markdown files; the invariant test fails if either reappears; Task 24 greps for them. |
| Runner logic duplicating scorer/oracle logic | **Absent** — every adapter emits `runner_decides_gate_outcome: false`, and each runner test greps the adapter source for the relevant ground truth and thresholds and fails if found. |
| Four independent runtime implementations | **Absent** — one `dispatch-fixture.sh` owns invocation, workspace, capture, timeout, exit status, failure classification, provenance, cost and raw evidence. The four adapters only select a fixture, build a request, call it, and normalize. |
| Fixture ground truth redefined by runner tasks | **Absent** — `eval/fixtures/**`, `eval/scoring/**`, `eval/decision-rules/**` and `eval/thresholds/**` are listed as unmodified by contract, and Task 24 asserts a zero diff against `main`. |
| Live model calls used to test basic runner plumbing | **Absent** — Tasks 8–12 use fake `opencode` binaries exclusively; Task 12 Step 5 requires the whole deterministic suite green before any behavioral gate runs. The only pre-gate model calls are the §4-mandated capability preflight. |
| A partial production profile treated as supported | **Absent** — Task 7 commits all eleven rows plus the Expert bump atomically; Task 16 performs a single activation write; the invariant test rejects any missing or undeclared row. |
| Phase 3 accidentally included | **Absent** — no Build A/B, no Reviewer effort experiment, no General challenger, no Phase-4 Expert work. The Sonnet run in Task 18 Step 8 is fixture control only and is marked `phase_3_admissible: false`. |

Additional checks run: every spec requirement in the task prompt maps to a task; no `TBD`/`TODO` placeholders; interface names are consistent across tasks (`load_routing_profile`, `ledger_admit`, `dispatch_fixture`, `dispatch_extract_json`, `run_*_gate`, `activate_profile`, `verify_effective_routing`); the Expert-before-or-atomic-with-Reviewer ordering invariant is asserted in both the profile test and the effective-routing verifier; and every frozen value (Scout `low`, Compaction `medium`, plan `max`, budgets `100`/`250`/`7600`) is copied from committed evidence rather than from prose.
