# OpenCode multi-model routing starter

This bundle uses OpenCode's built-in agents for normal work and adds only two custom subagents: `reviewer` and `expert`.

Routing is split deliberately into two layers:

- `opencode.jsonc`: deterministic model/variant assignment per agent.
- `.opencode/model-routing.md`: semantic rules telling the controller when Superpowers work should go to `general`, `reviewer`, or `expert`.

The routing policy is loaded through OpenCode's `instructions` setting; it does not need to be merged into the project's `AGENTS.md`.

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

## Routing migration

The current OpenCode V1 multi-model routing restoration is governed by:

- [Approved routing plan](docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md)
- [First implementation actions](docs/runbooks/2026-09-02-migration-first-actions.md)

The decision document is the source of truth for migration gates,
evaluation rules, recovery constraints, and model-routing decisions.

The [Phase-R ground-truth readiness record](docs/evidence/2026-09-03-phase-r-ground-truth-readiness.md)
adds the approved exact Scout `low` and Compaction `medium` variants, executable
Reviewer/Explore/Compaction fixture ground truth, and the user-global activation
contract. It does not change or activate the published routing profile.

Phase R executed against every committed gate; **status:
`BLOCKED_REVIEWER_RERUN`**, not PASS — see the
[Phase-R execution evidence](docs/evidence/2026-09-04-phase-r-execution.md)
for the full record. Build, Explore, Compaction, routing resolution and
security boundaries passed and are not re-run by this correction; the
Reviewer seeded-defect gate is blocked (see I1/I2, the
[Reviewer fixture-integrity remediation](docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md),
and the
[Reviewer observability/attribution remediation](docs/evidence/2026-09-04-reviewer-observability-attribution-remediation.md)).
The Reviewer fixture and scorer are now mechanically admissible offline;
a fresh live 5/5 + clean-zero rerun and its own budget approval are still
required. The routing profile is restored and active on the real,
user-global OpenCode configuration (`operational_state: active-provisional`)
— that activation stands independent of the Reviewer gate's status — but is
**not** currently a `canonical_quality_reference`.

## Restored reference profile

[`profiles/v1-restored-2026-09.jsonc`](profiles/v1-restored-2026-09.jsonc) is
a snapshot of the exact routing that was actively installed during Phase R.
It is **not currently** the forward quality reference, the Phase-3 starting
baseline, or a rollback target — see the corrected header comment in that
file — pending a clean Reviewer gate rerun against an integrity-proven
fixture.

[`profiles/baseline-2026-08.jsonc`](profiles/baseline-2026-08.jsonc) remains
the preserved, untouched historical record of the pre-Phase-R profile.

## Capability status (Track A)

The [2026-09-02 capability closure](docs/evidence/2026-09-02-capability-closure.md)
found that the committed Claude Opus 4.6 targets failed the runtime capability
check in the audited environment: the explicit model ID was not resolvable.
The same check found the old Claude Sonnet 4.6 ID was not resolvable.

GPT-5.3-Codex resolves in the audited environment as of the recorded
capability check. This is discovery evidence only; the closure does not claim
that a Codex request executed successfully. The migration away from Codex is
an explicit risk decision, not a capability finding.

Use this evidence hierarchy before activating a profile:

```text
documentation / policy
    -> candidate information

opencode models
    -> discovery / resolution signal

successful trivial call
    -> usable capability

role fixture
    -> routing fitness
```

The organization policy page is authoritative for policy state, not runtime
capability state.

The [governance blocker record](docs/evidence/2026-09-02-governance-blockers.md)
records the resolved local Copilot, OpenAI, and OpenCode V2 RFC ownership
decisions and distinguishes external organizational controls.

## Phase 0 evaluation harness

Run the dependency-free Phase 0 gate tests from the repository root:

```bash
bash models/routing/opencode/eval/run-tests.sh
```

The harness is evidence infrastructure only. It does not install or activate a
routing profile, call candidate models during tests, or authorize Phase R. See
the [Phase 0 gate record](docs/evidence/2026-09-02-phase-0-gates.md) for the
implemented gates and unresolved budget inputs.

## 1. Verify model IDs and variants

Connect GitHub Copilot and OpenAI in OpenCode, then inspect the models and variants available to your accounts:

```text
/connect
/models
/variants
```

Or list models from the CLI where appropriate:

```bash
opencode models
```

Do not assume a model ID in this historical profile is currently available.
The capability closure above found that `github-copilot/claude-opus-4.6` was
not resolvable in the audited environment. In that audit,
`github-copilot/gpt-5.3-codex` was listed as a discovery signal only.

For any profile you activate, verify the configured model IDs against the
installed runtime and then confirm usable capability with a trivial successful
call:

```text
github-copilot/claude-opus-5
github-copilot/gpt-5.6-terra
github-copilot/gpt-5.6-luna
github-copilot/gpt-5.6-sol
openai/gpt-5.6-sol
```

Variant availability can depend on the provider/model catalog exposed to your installation. Verify `high`, `xhigh`, and `max` before merging. If a requested variant is not exposed, use the highest available variant for that model without changing the role mapping.

## 2. Enable web search

The bundle enables the `websearch` permission so agents can search the web via Exa AI. The tool requires the `OPENCODE_ENABLE_EXA` environment variable to be set:

```bash
export OPENCODE_ENABLE_EXA=true
```

Add this to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) for persistence. No API key is required — the tool connects directly to Exa AI's hosted MCP service without authentication.

If you use the [agentic-dev-toolkit installer](../../../environments/linux/install.sh), this variable is set automatically in the managed `~/.bashrc` block.

## 3. Install the custom agents and routing policy

Copy these files from this bundle into the matching target paths:

```text
.opencode/agents/reviewer.md -> .opencode/agents/reviewer.md
.opencode/agents/expert.md -> .opencode/agents/expert.md
.opencode/model-routing.md -> .opencode/model-routing.md
```

`reviewer` is independent and read-only. `expert` is hidden, read-only, cannot spawn subagents, and is capped at six agentic steps. GPT-5.6 Sol is not confined to `expert`: `reviewer` runs it through Copilot at `high`, `expert` runs it direct on OpenAI at `xhigh`, and `breakglass` runs it direct on OpenAI at `max` as a human-selected primary.

## 4. Merge the OpenCode configuration

Merge `opencode.jsonc` into your existing project or global OpenCode configuration. Treat it as a fragment and do not replace unrelated configuration.

If your existing configuration already has an `instructions` array, append `.opencode/model-routing.md` to it rather than replacing the existing entries.

The fragment pins all eleven roles as follows:

```text
plan       -> Claude Opus 5 (Copilot)     max
build      -> Claude Opus 5 (Copilot)     high
general    -> GPT-5.6 Terra (Copilot)     high
explore    -> GPT-5.6 Luna (Copilot)      medium
scout      -> GPT-5.6 Luna (Copilot)      low
reviewer   -> GPT-5.6 Sol (Copilot)       high
expert     -> GPT-5.6 Sol (direct OpenAI) xhigh
breakglass -> GPT-5.6 Sol (direct OpenAI) max
compaction -> GPT-5.6 Terra (Copilot)     medium
title      -> GPT-5.6 Luna (Copilot)      low
summary    -> GPT-5.6 Luna (Copilot)      low
```

It also permits `plan`, `build`, and `general` to invoke subagents via the Task
tool, with `breakglass` explicitly denied at every one of those `task`
permission blocks and at the top level.

## 5. Superpowers routing

`.opencode/model-routing.md` provides the semantic mapping:

```text
Superpowers implementation subagent -> general    -> GPT-5.6 Terra high (Copilot)
Superpowers review / re-review       -> reviewer   -> GPT-5.6 Sol high (Copilot)
high-risk / disputed judgment        -> expert     -> GPT-5.6 Sol xhigh (direct OpenAI)
```

This layer is still an instruction to the controller, not a hard-coded Superpowers dispatcher. The deterministic parts are the agent-to-model mapping. If future observation shows Superpowers repeatedly dispatching review to the wrong subagent, the next escalation is a minimal Superpowers dispatch override rather than adding more prompt rules.

## 6. Why no AGENTS.md fragment

OpenCode supports project instruction files directly through the `instructions` field in `opencode.json`. Keeping the routing policy in `.opencode/model-routing.md` avoids mixing personal orchestration policy with the repository's general engineering rules in `AGENTS.md`.

Your existing `AGENTS.md`, if any, remains untouched and is still loaded by OpenCode alongside the configured instruction file.

## 7. Smoke tests

After merging the configuration, verify these scenarios:

1. Ask `build` to locate a local implementation before editing. Expected helper: `explore`.
2. Ask for comparison with current upstream/dependency documentation. Expected helper: `scout`.
3. Give a bounded multi-file implementation task. Expected delegated worker when delegation is useful: `general`.
4. Run a Superpowers task review. Expected reviewer: `reviewer`, not `general`.
5. Present an unresolved public API or security decision. Expected escalation: `expert` with a compact decision packet and no implementation by the expert.
6. Confirm `build` can invoke `general`, `explore`, `scout`, `reviewer`, and `expert` through Task.

## 8. GPT-5.6 quota rule

Do not switch `plan`, `build`, `general`, `explore`, `scout`, `reviewer`, `compaction`, `title`, or `summary` to direct OpenAI for normal work; all nine stay on GitHub Copilot. Keep direct OpenAI isolated behind `expert` and the human-selected `breakglass` agent so ordinary delegation cannot accidentally inherit the scarce, credential-gated provider.
