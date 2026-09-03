# OpenCode V1 Routing Phase 0 Gates

## Outcome

Phase 0 establishes the evaluation and security mechanisms needed before any
routing restoration or comparative model work. It does not execute Phase R,
Phase 3, or Phase 4 and does not change the published routing profile.

## Implemented gates

- Runtime provenance and installed-profile manifest validation.
- Explicit model/variant capability probes with sanitized records.
- Pure n=3/n=5 count rules and append-only Build failure classification.
- Deterministic Build restoration fixture with a mechanical oracle.
- Phase-3 Build fixture metadata separated from Phase-R evidence.
- Reviewer seeded-defect, Expert unpooled, and exact compaction scorers.
- Measured self-variance mechanism with candidate-result exclusion.
- Resolved Reviewer/Expert permission checks.
- Non-production Breakglass Task denial and human-primary selection checks.

## Governance

Local operational, Copilot spend, direct OpenAI spend, credential, and future
OpenCode V2 RFC ownership are recorded in
`2026-09-02-governance-blockers.md`. Contract, retention, enterprise policy,
and GitHub billing enforcement remain external organizational controls. The
repository does not implement a spending-cap feature and must not represent the
external Copilot guardrail as locally enforced.

## Blocking budget inputs

Two separate numerical approvals are still absent:

| Input | Status | Consequence |
|---|---|---|
| Project evaluation budget | `UNRESOLVED` | No candidate evaluation program may begin. |
| Phase-R bisection/recovery budget | `UNRESOLVED` | Phase R may not begin or consume recovery attempts. |

The external organization-level Copilot guardrail is neither of these budgets.
No value is inferred from observed cost, historic credit use, or provider quota.

## Cost and provenance boundaries

Copilot Sol observations before 2026-09-04 are promotional and cannot establish
steady-state pricing. Direct OpenAI zero-cost telemetry is an observed runtime
value, not a claim of free service. Normalized steady-state cost remains unknown.

For ordinary sessions, provenance can attribute behavior only to the installed
profile manifest and runtime version. Without per-session runtime capture, it
cannot prove that the installed file was the effective merged configuration for
an individual session.

## Remaining Phase-R blockers

- Human approval of the project evaluation budget.
- Human approval of the distinct Phase-R bisection/recovery budget.
- Repeated-run self-variance evidence and committed practical continuous
  thresholds before candidate A/B results are exposed.
- Current provider quota sufficient for any approved direct OpenAI work.
- Explicit human authorization to begin Phase R after all gates are satisfied.

No statement in this record authorizes Phase R.
