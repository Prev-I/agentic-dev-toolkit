# Build Retry With 500-Credit Ceiling

## Result

**Astra completed the real implementation task and passed independent correctness
checks. Opus was budget-stopped while writing regression tests.** Astra is a
viable Build contender under explicit implementation authorization, with one
important test-coverage finding. This is not a general coding-quality win over
Opus, whose implementation was never completed under the available budget.

Production routing remains unchanged. Candidate submissions are preserved as
evidence, not applied to the production installer or repaired by the evaluator.

## Authorization and Method

The user requested a retry and raised the ceiling to 500 credits. This was
interpreted as a revised total, not 500 additional credits. Recorded spend before
the retry was 292.657475, leaving 207.342525.

Both interrupted sessions still existed and their workspaces were byte-identical
to the saved snapshots. Rather than buy the same discovery again, both received
the identical continuation prompt in `eval/records/astra-build-retry/prompt.txt`.
It supplied no implementation feedback, preserved the original scope and
explicit approval waiver, and asked them to continue from pending test-first
implementation. Order was reversed: Opus, then Astra. Model variants remained
`high`; the original fixture, independent oracle, global skills, and runtime
were unchanged. This is a resumed-task comparison, not a fresh-run benchmark.

The frozen retry protocol and experiment-local wrapper are retained beside the
results. Each continuation had a 90-new-credit completed-step stop threshold,
with 27.342525 beyond the two thresholds reserved for reporting lag. A fake
stream confirmed session-argument forwarding and termination at 95 credits
before completion. Real `opencode run --session` selected the recorded sessions;
`opencode export` returned truncated invalid JSON, so a complete context export
is not available. Raw run transcripts and session IDs remain available.

## Measurements

| Model | Continuation Credits | Continuation Seconds | PATH Task Total Credits | PATH Task Active Seconds | Outcome |
|---|---:|---:|---:|---:|---|
| Astra high | 85.447050 | 126.489 | 157.695250 | 165.966 | Completed |
| Opus high | 95.766225 | 83.313 | 169.517375 | 208.883 | Budget-stopped |

Task totals add the initial interrupted PATH run and its continuation, excluding
idle time between sessions and the earlier tiny-fixture screening. Opus's raw
dispatcher label is `TIMEOUT` because the legacy parser maps exit 143 that way;
the raw `EVAL_BUDGET_STOP` marker establishes the actual cause. It was well below
480 seconds. This metadata is preserved, not silently rewritten.

Astra modified only `environments/linux/install.sh` and `tests/install.sh`.
Its production patch replaces all three unconditional PATH prepends with guarded
exact-entry checks, preserving priority and existing entries. Opus modified only
the tests, reproduced the historical bug, and stopped before implementation.
Neither asked for approval or delegated the task.

## Independent Scoring

Astra:

- Independent behavioral oracle: PASS, five scenarios at all three PATH sites.
- Untouched historical test suite against candidate implementation: PASS.
- Candidate-authored suite: PASS.
- Candidate tests against the historical broken installer: FAIL for the expected
  missing-directory bootstrap behavior, demonstrating regression sensitivity.
- Syntax checks: PASS; only the two permitted files changed.

Opus:

- Independent oracle: FAIL because production remains historically broken.
- Candidate suite: expected RED, detecting missing directories added to PATH.
- No completed implementation to score; budget interruption is not coded as a
  model correctness failure.

### Review Finding

Independent review found no blocking production-code defect, but flagged an
important regression in test coverage. Astra adds disposable `HOME` isolation
and globally exports `ADT_FORCE_WSL=0` at candidate `tests/install.sh:1095-1097`.
That fixes a test-environment issue it encountered, but prevents existing
`verify_installation` calls from exercising the WSL credential-wrapper
verification branch (`environments/linux/install.sh:1289-1307`). Later tests force
WSL for configuration, not for this verification path.

The recommended revision is to scope credential skipping to unrelated tests
and retain isolated forced-WSL verification coverage, rather than globally
disabling WSL detection. **This revision was not made to the submission.** The
candidate is correct on the requested PATH behavior but should not be described
as an unqualified, review-clean patch. This issue also limits claims of complete
test-invariant preservation, even though the immutable original suite passes.

## Budget

- Retry continuations: **181.213275 credits**.
- All preceding evaluation dispatches: **292.657475 credits**.
- Combined recorded dispatch spend: **473.870750 / 500 credits**.
- Remaining recorded allowance: **26.129250 credits**; no additional paid runs.

All figures sum raw completed-step costs multiplied by 100, using the existing
accounting convention. Continuation streams contain newly emitted steps only;
historical streams are added separately, not counted twice. They are not a
billing-UI reconciliation. Interrupted requests may have unreported cost, and
parent orchestration/review usage is not exposed by the ledger. The stop
threshold is not a provider-enforced hard cap and was overshot by Opus's last
reported step.

## Interpretation

The follow-up now supplies positive evidence that Astra can perform real Build
work without an approval pause when the prompt explicitly authorizes it. It
completed within a lower observed task cost than the unfinished Opus arm under
these particular interrupted/resumed conditions. That is bounded completion
evidence, not proof of a stable speed advantage or superior general coding
quality. The test-coverage finding remains part of Astra's result.

The sample is one historical Bash task. The original patch was co-authored by
Opus; neither arm saw its history or patch, but historical exposure cannot be
excluded. Cache behavior, model-specific context size, interrupted reasoning,
and resumption affect cost and timing. A routing promotion would require broader
completed evidence and a separate controller/reviewer family-separation decision.

## Verification and Evidence

`eval/records/astra-build-retry/` retains the common prompt, protocol, wrapper,
ledger, adjudication, raw continuations, final work products, oracle results,
candidate suite results, Astra's immutable-suite and mutation-check logs, and
repository verification logs. Prior phases remain unchanged.

All four repository suites were run again; logs are `verification-*.log` in that
directory. Production files and routing have no tracked diff. Secret scanning
covers the new evidence. Candidate work products remain experiment-only.
