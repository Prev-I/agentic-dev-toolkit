# Grok 4.6 vs Opus 5 Default Build Screening

Approved in chat on 2026-09-07: a new 300-credit allowance, two capability
checks, and four default workload dispatches. No automatic retries, replacement
pairs, extra workloads, routing changes, commits, or pull requests are authorized.

## Frozen Protocol

- Provider: GitHub Copilot for both models.
- Challenger: `github-copilot/grok-4.6`, variant `high`.
- Incumbent: `github-copilot/claude-opus-5`, variant `high`.
- Capability prompt: `Reply with exactly: CAPABILITY_OK`; 120-second timeout.
- Capability order: Grok, then Opus. Require successful exact response, no
  provider error, and known cost before proceeding.
- Workload order: feature Opus/Grok, then bugfix Grok/Opus.
- Use the unchanged `run-phase3-build-fixture.sh`, fixture task prompts,
  snapshots, acceptance oracles, and regression tests.
- Each arm receives a fresh isolated workspace; workload timeout is 480 seconds.
- Capability admission projection: 20 credits per call. Workload admission
  projection: 75 credits per call. These are conservative control values, not
  model-specific price predictions. Reconcile after every call; stop if cost is
  missing, a provider/environment failure occurs, or admission fails.
- Allowance is observed harness accounting, not a provider-enforced hard cap.
  A running request may exceed its projection; reported cost can lag.
- Preserve the default unattended contract. An approval stop is reported as
  non-completion under that contract, not general coding inability.
- Report per-workload correctness, invariants/scope, corrections, retries,
  elapsed time, and cost. A functional regression cannot be offset by savings.
- For functional ties, retain the historical screening threshold: each workload
  must independently favor Grok with `(max-min)/median > 0.378885` to clear
  the timing replacement criterion. No averaging across workloads.
- This is one attempt per model per workload, not a reliability estimate.
- Routing remains unchanged regardless of the screening result.

## Discovery

Before approval, `opencode models github-copilot --verbose` listed both exact
model IDs and their `high` variants. Catalog cost metadata (per million tokens):

| Model | Input USD | Output USD | Cache-read USD |
|---|---:|---:|---:|
| Grok 4.6 | 2 | 6 | 0.5 |
| Opus 5 | 5 | 25 | 0.5 |

Discovery does not establish capability. Live capability calls are charged to
this experiment. Credits are runtime-reported USD multiplied by 100, summed
across all `step_finish` events. Parent orchestration/review usage is not exposed
by this ledger; figures are not reconciled against the billing UI. No claim is
made about remaining organization-wide billing allowance.
