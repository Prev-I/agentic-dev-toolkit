# Build Model Rollback

## Decision

The user approved restoring Build and the default model to
`github-copilot/gpt-5.6-sol`. Build retains variant `high`, primary mode, and
its existing permissions. Every other role remains unchanged.

This decision extends the current profile established by
`docs/decisions/2026-09-25-navigation-model-alignment.md`. It supersedes only
the cost-first Build selection in
`docs/decisions/2026-09-24-cost-optimized-routing.md`; neither historical
decision nor its evidence is rewritten.

Breakglass deliberately remains `openai/gpt-6-sol` `max`; this rollback does
not re-align the human-only recovery role with Build.

## Rationale And Evidence Boundary

The user reported dissatisfaction with GPT-6 Sol for Build and selected the
documented rollback target. The GPT-6 role screening formally adjudicated
`KEEP_INCUMBENT` for Build, where the incumbent was GPT-5.6 Sol high. Both
models passed the completed bugfix workload, while the feature workload was
non-discriminating because both stopped at the required approval gate.

This is an observation-driven rollback, not a new benchmark claim. The existing
screening used one attempt per workload and remains subject to its recorded
limitations.

GPT-5.6 Sol was slower and used more observed credits on the completed bugfix
workload. Reconsider GPT-6 Sol `high` only if that efficiency difference becomes
more important than the repeated human correction or quality concerns that
triggered this rollback.

## Verification Contract

`opencode.jsonc` remains the routing authority. The target manifest declares
profile `v5-build-quality-rollback-2026-09-29`; the full parsed-profile test
permits the Build and default-model rollback while pinning every other model,
permission, variant, and mode.

Activation is a separate backup-and-merge operation. It must preserve all
user-owned global configuration outside the routing-owned keys.
