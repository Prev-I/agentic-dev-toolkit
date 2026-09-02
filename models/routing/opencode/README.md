# OpenCode multi-model routing starter

This bundle uses OpenCode's built-in agents for normal work and adds only two custom subagents: `reviewer` and `expert`.

Routing is split deliberately into two layers:

- `opencode.jsonc`: deterministic model/variant assignment per agent.
- `.opencode/model-routing.md`: semantic rules telling the controller when Superpowers work should go to `general`, `reviewer`, or `expert`.

The routing policy is loaded through OpenCode's `instructions` setting; it does not need to be merged into the project's `AGENTS.md`.

## Model map

| Role | OpenCode agent | Model | Variant |
|---|---|---|---|
| Planning/design | `plan` | `github-copilot/claude-opus-4.6` | `max` |
| Primary build/controller | `build` | `github-copilot/claude-opus-4.6` | `high` |
| Delegated implementation/debugging | `general` | `github-copilot/claude-opus-4.6` | `xhigh` |
| Local codebase exploration | `explore` | `github-copilot/gpt-5.3-codex` | `high` |
| External/upstream research | `scout` | `github-copilot/gpt-5.3-codex` | `high` |
| Independent review | `reviewer` | `github-copilot/gpt-5.3-codex` | `max` |
| Escalation-only expert | `expert` | `openai/gpt-5.6` | `high` |

The design intentionally keeps `build` and `general` on the same Opus family but gives them different jobs and reasoning levels. Review is deliberately assigned to a different model family (Codex) to ensure adversarial diversity.

## Routing migration

The current OpenCode V1 multi-model routing restoration is governed by:

- [Approved routing plan](docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md)
- [First implementation actions](docs/runbooks/2026-09-02-migration-first-actions.md)

The decision document is the source of truth for migration gates,
evaluation rules, recovery constraints, and model-routing decisions.

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
lists the named Copilot, OpenAI, and OpenCode V2 RFC ownership decisions still
required before Phase 0 can complete.

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

Confirm these model IDs exist:

```text
github-copilot/gpt-5.3-codex
github-copilot/claude-opus-4.6
openai/gpt-5.6
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

`reviewer` is independent and read-only. `expert` is hidden, read-only, cannot spawn subagents, and is capped at six agentic steps. It is the only intended path to GPT-5.6 Sol.

## 4. Merge the OpenCode configuration

Merge `opencode.jsonc` into your existing project or global OpenCode configuration. Treat it as a fragment and do not replace unrelated configuration.

If your existing configuration already has an `instructions` array, append `.opencode/model-routing.md` to it rather than replacing the existing entries.

The fragment pins the built-in agents as follows:

```text
plan    -> Opus 4.6 max
build   -> Opus 4.6 high
general -> Opus 4.6 xhigh
explore -> GPT-5.3 Codex high
scout   -> GPT-5.3 Codex high
```

It also permits `build` to invoke subagents via the Task tool (`"task": "allow"`).

## 5. Superpowers routing

`.opencode/model-routing.md` provides the semantic mapping:

```text
Superpowers implementation subagent -> general  -> Opus xhigh
Superpowers review / re-review       -> reviewer -> Codex max
high-risk / disputed judgment        -> expert   -> GPT-5.6 Sol
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

Do not switch `build`, `plan`, `general`, `explore`, `scout`, or `reviewer` to GPT-5.6 for normal work. Keep GPT-5.6 isolated behind the hidden `expert` agent so ordinary delegation cannot accidentally inherit the scarce model.
