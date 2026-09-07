# Grok 4.6 vs Opus 5 Default Build Result

## Result

**Both models passed both workloads. Grok was cheaper and nominally faster on
each, but neither timing difference cleared the frozen replacement threshold.
Screening decision: `KEEP_OPUS`. Routing is unchanged.**

This is the user-approved default feature/bugfix screening, not the larger PATH
task. The new 300-credit experiment allowance covered two capability checks and
four workload calls, with no retries, replacement pairs, or additional tasks.
The pre-dispatch protocol is `eval/records/grok-build/protocol.md`.

## Execution

Both exact Copilot model IDs passed `CAPABILITY_OK` with variant `high`.
OpenCode was `1.18.29`; the runner and unchanged fixtures came from repository
commit `baf8678c15df3bffffd9887da3fb08b57ecc7036`.

Each arm used a fresh sandbox, the existing fixture prompt, a 480-second timeout,
and the existing acceptance oracle and regression suite. Feature order was
Opus/Grok; bugfix order was Grok/Opus. All four dispatches completed `OK`, with
acceptance initially failing and oracle/regression checks passing afterward.
No approval stop, provider error, delegation, human correction, or retry occurred.

| Workload | Model / high | Oracle | Regression | Seconds | Credits |
|---|---|---|---|---:|---:|
| Feature | Opus 5 | PASS | PASS | 66.003 | 30.259650 |
| Feature | Grok 4.6 | PASS | PASS | 57.829 | 18.898200 |
| Bugfix | Grok 4.6 | PASS | PASS | 35.040 | 16.915400 |
| Bugfix | Opus 5 | PASS | PASS | 42.732 | 29.960175 |

Raw edit events target only the intended implementation file in each sandbox.
No edits to README or tests were found. Functional criteria are tied within the
coverage of these small fixtures.

## Timing And Cost

The frozen timing criterion requires each workload independently to favor Grok
with `(max-min)/median > 0.378885`. Neither does:

| Workload | Relative timing separation | Clears threshold |
|---|---:|---|
| Feature | 0.132018 | No |
| Bugfix | 0.197809 | No |

Grok's elapsed time was 12.4% lower on feature and 18.0% lower on bugfix. Those
percentages use Opus as denominator, unlike the threshold formula above.

| Model | Workload credits | Capability credits | Total credits |
|---|---:|---:|---:|
| Grok 4.6 | 35.813600 | 2.256800 | 38.070400 |
| Opus 5 | 60.219825 | 9.455375 | 69.675200 |
| Combined | 96.033425 | 11.712175 | 107.745600 |

Grok used **40.5% fewer workload credits** than Opus. Cost cannot independently
trigger replacement under this protocol. **192.254400 credits remain unused**;
no further paid calls are authorized by this result.

These are observed harness credits: runtime-reported USD multiplied by 100,
summed over every `step_finish` event. All six raw-stream sums reconcile with
dispatch records and ledger entries. They are not billing-UI reconciliation,
exclude parent orchestration/review usage, and are not normalized for caching.

## Interpretation And Limits

Grok is a credible lower-cost Build challenger on these two small fixtures, not
an established general replacement. One run per model per task cannot establish
reliability. Unlike earlier Sol/Astra screening attempts, Grok did not pause for
approval under the unchanged default prompts.

The existing runner deletes sandboxes after scoring. Retained evidence includes
raw tool activity, responses, prompts, oracle/regression logs, and dispatch
records, but no final sandbox snapshot for independent rerunning. Exact model
identity is recorded by the dispatcher invocation metadata; raw events contain
session IDs but do not independently attest model identity.

## Verification

- Independent read-only evidence audit: six distinct sessions, frozen order,
  successful capability checks, four passing task results, no hidden provider
  failures or out-of-scope edits found, and all costs reconciled.
- Installer suite: PASS.
- Repository policy suite: PASS.
- WSL toolchain doctor suite: 148 passed, 0 failed.
- Routing evaluation suite: PASS (exit 0).

Logs and machine-readable adjudication are retained under
`eval/records/grok-build/`. Only evidence and this report were added; production
code, routing configuration, fixtures, and the shared runner were not changed.
