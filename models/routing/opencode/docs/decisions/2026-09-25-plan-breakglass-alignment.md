# Plan And Breakglass Model Alignment

## Decision

The user approved two current-profile model updates:

| Role | Model | Variant |
|---|---|---|
| Plan | `github-copilot/claude-opus-5.5` | `max` |
| Breakglass | `openai/gpt-6-sol` | `max` |

Plan now uses the same Opus generation as Reviewer while retaining its higher
planning effort. Breakglass now uses the direct-OpenAI generation corresponding
to the GPT-6 Sol Build family while preserving provider isolation.
Build and Breakglass therefore share the same underlying model generation; the
recovery boundary provides provider and credential separation, not protection
from a model-specific GPT-6 Sol regression.

Only model assignments change. Plan remains primary and read-only with delegated
task access. Breakglass remains human-selected primary, read-only, shell-denied,
and inaccessible through Task delegation. All other roles, variants, modes,
permissions, prompts, and the top-level default remain unchanged.

This decision extends
`docs/decisions/2026-09-24-cost-optimized-routing.md`; it does not revise the
screening adjudications or historical profiles.

This updates the tracked source bundle only. It does not activate or edit the
user-global OpenCode configuration; activation remains a separate operation.

## Capability Evidence

Both exact targets returned `CAPABILITY_OK` with no provider error on OpenCode
1.18.32:

- `eval/records/plan-breakglass-alignment/capability/plan-opus55-max/`
- `eval/records/plan-breakglass-alignment/capability/breakglass-sol6-max/`

Capability establishes successful inference, not role-quality superiority. Plan
and Breakglass fitness should be monitored through normal use, with rollback on
material correctness regressions or repeated human correction.

The historical Phase-0 Breakglass probe scripts remain pinned to GPT-5.6 Sol and
must not be used to validate this v3 current profile. Current-profile identity is
checked by the full parsed-profile test and the capability records above.

Rollback targets are Plan `github-copilot/claude-opus-5` `max` and Breakglass
`openai/gpt-5.6-sol` `max`.

## Verification Contract

`opencode.jsonc` remains the routing authority. The current target manifest now
declares profile `v3-aligned-plan-breakglass-2026-09-25`; the full parsed-profile
test permits only the approved current substitutions while pinning every
permission, variant, mode, and unaffected role.
