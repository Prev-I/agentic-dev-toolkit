# Cost-Optimized Build, General, And Reviewer Routing

## Decision

The user approved a tracked-bundle routing update on 2026-09-24:

| Role | Model | Variant |
|---|---|---|
| Build | `github-copilot/gpt-6-sol` | `high` |
| General | `github-copilot/gpt-6-luna` | `high` |
| Reviewer | `github-copilot/claude-opus-5.5` | `high` |

The default model follows Build. All modes, permissions, prompts, variants, and
unlisted role assignments remain unchanged. In particular, Plan remains Copilot
Opus 5/max, Expert remains direct OpenAI Astra/xhigh, and Breakglass remains
direct OpenAI GPT-5.6 Sol/max and human-only.

This decision updates the tracked source bundle only. It does not activate or
edit the user-global OpenCode configuration; activation remains a separate
backup-and-merge operation followed by a fresh OpenCode restart.

## Rationale And Evidence Boundary

The objective is lower inference cost while preserving role specialization.
Two role-specific screenings supply the observations behind the user override:

- Build: GPT-6 Sol and GPT-5.6 Sol both passed the completed bugfix workload;
  GPT-6 Sol was faster and used fewer observed credits. The experiment formally
  kept the incumbent because neither model satisfied both frozen workloads; the
  shared feature non-completion came from both obeying the mandatory approval
  gate, so the user treats that workload as non-discriminating for this override.
- General: GPT-6 Luna and GPT-5.6 Terra both passed the completed bugfix
  workload; GPT-6 Luna had a favorable cost and latency signal. The experiment
  formally kept the incumbent because neither model satisfied both workloads;
  the user applies the same approval-gate interpretation here.
- Reviewer: Opus 5.5 and Opus 5 produced the same deterministic blocked quality
  result. Opus 5.5 was faster, cheaper at catalog rates, used fewer final tokens,
  and followed the JSON-only output request more consistently.
- Explore: GPT-6 Luna medium tied on correctness, cost less, and ran slower than
  GPT-5.6 Luna medium. This mixed result does not support changing Explore, so it
  remains on GPT-5.6 Luna medium.

These are monitored cost-first choices, not claims that the selected models are
generally superior. One attempt per workload does not establish reliability,
observed credits vary with cache state, and the Reviewer incumbent also failed
its quality gate. Historical profiles, decisions, and evidence remain unchanged.

The screening records are:

- `eval/records/gpt6-role-screening/`
- `eval/records/opus55-reviewer-screening/`

## Relationship To The Screening Adjudications

The GPT-6 screening adjudicated `KEEP_INCUMBENT` for Build, General, and Explore.
The Reviewer screening adjudicated `KEEP_OPUS_5`. Their frozen protocols make
functional quality decisive and forbid efficiency from selecting a challenger
after the quality threshold blocks.

This routing decision deliberately overrides those outcomes for Build, General,
and Reviewer. It is an explicit user cost-management choice made outside the
experiments' decision rules, not a re-scoring of their evidence. The original
verdicts stand unamended. Because none of the promoted pairings cleared every
frozen quality criterion, the rollback triggers below and monitored observation
substitute for a benchmark promotion claim.

## Rollback Triggers

Revert a role to its previous target if observation shows a material correctness
regression, repeated human correction, increased Reviewer misses or false
positives, unexpected approval behavior, or operationally unacceptable latency.

Previous targets:

| Role | Model | Variant |
|---|---|---|
| Build | `github-copilot/gpt-5.6-sol` | `high` |
| General | `github-copilot/gpt-5.6-terra` | `high` |
| Reviewer | `github-copilot/claude-opus-5` | `high` |

## Verification Contract

`opencode.jsonc` remains the routing authority.
`eval/manifests/current-routing-targets.json` declares profile
`v2-cost-optimized-2026-09-24`, and the current-routing test compares the full
parsed source with the historical restored profile while permitting only the
approved current model substitutions. Permissions and unaffected roles remain
pinned by full-structure equality.
