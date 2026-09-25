# Explore And Scout Model Alignment

## Decision

The user approved two current-profile model updates:

| Role | Model | Variant |
|---|---|---|
| Explore | `github-copilot/gpt-6-luna` | `medium` |
| Scout | `github-copilot/gpt-6-luna` | `low` |

Only model assignments change. Explore remains medium-effort and Scout remains
low-effort. Both stay read-only navigation roles. Compaction remains
`github-copilot/gpt-5.6-terra` `medium`; Title and Summary remain
`github-copilot/gpt-5.6-luna` `low`.

This decision extends
`docs/decisions/2026-09-25-plan-breakglass-alignment.md`. It updates the tracked
source bundle only and does not activate the user-global OpenCode configuration.

## Evidence Boundary

Explore GPT-6 Luna medium passed the existing dependency-chain fixture and used
fewer observed credits, but ran slower than GPT-5.6 Luna medium. Its prior
screening adjudicated `KEEP_INCUMBENT`; this is an explicit user cost-management
override, not a re-scoring of that evidence.

Scout GPT-6 Luna low returned `CAPABILITY_OK` with no provider error on OpenCode
1.18.32. That establishes successful inference, not role-quality superiority.

Evidence:

- `eval/records/gpt6-role-screening/recovery/explore/pair1-arm2-luna6/`
- `eval/records/navigation-model-alignment/capability/scout-luna6-low/`

Rollback targets are Explore `github-copilot/gpt-5.6-luna` `medium` and Scout
`github-copilot/gpt-5.6-luna` `low`.

Rollback either role if observation shows material correctness misses, repeated
human correction, or operationally unacceptable latency. Explore deserves
specific latency monitoring because GPT-6 Luna medium was slower on the frozen
dependency-chain fixture even though it used fewer observed credits.

## Verification Contract

`opencode.jsonc` remains the routing authority. The target manifest declares
profile `v4-aligned-navigation-2026-09-25`; the full parsed-profile test permits
only the approved current substitutions while pinning Compaction, Title,
Summary, every permission, every variant, every mode, and every other role.
