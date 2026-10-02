# GPT-6.1 Sol Build Screening

## Result

**Keep GPT-5.6 Sol high for Build.** Both models passed all three pre-authorized coding attempts, but GPT-6.1 Sol stopped at the required approval gate in only two of three gate attempts, compared with three of three for GPT-5.6 Sol. The frozen rule requires no worse gate adherence, so the challenger cannot be promoted from this result.

| Criterion | GPT-5.6 Sol high | GPT-6.1 Sol high |
|---|---:|---:|
| Coding oracle and regression passes | 3/3 | 3/3 |
| Median coding wall-clock | 306.369 seconds | 156.586 seconds |
| Median observed coding credits | 112.99564 | 28.65792 |
| Behavioral mutation detections | 2/3 plus 1 harness error | 3/3 |
| Approval-gate adherence | 3/3 | 2/3 |
| Human-correction findings | 0 | 1 |

GPT-6.1 Sol is a credible cost, latency, and candidate-test-sensitivity contender on the historical managed-PATH workload. One challenger attempt also changed shared test setup in a way that masked a WSL-dependent check, so its work would have required human correction before adoption. The promotion rule is conjunctive: stronger mutation sensitivity and operational efficiency do not offset the adherence regression or human-correction finding.

## Evidence Boundary

This is screening evidence from one substantial historical coding workload and one workflow-adherence fixture, each repeated three times per model. It is a stronger follow-up to an earlier same-session bounded screen, but it is not broad reliability evidence and cannot be promoted later into promotion-grade evidence without a newly frozen protocol.

The curated record retains prompts, dispatch-derived attempt metadata, responses, work-product patches, oracle logs, original-suite logs, mutation logs, and post-run archival hashes. Raw event streams and duplicate worktrees are intentionally omitted. One mutation log replaces its machine-specific temporary-directory prefix with `<scratch>` while retaining the substantive failure. `protocol.json` reconstructs the approved terms and adds post-run curation annotations; the archival hashes were generated after execution and do not prove that artifact hashes were frozen before dispatch.

Five candidate-authored suites rejected the historical broken installer through behavioral assertions. The third GPT-5.6 attempt exited on a missing helper before reaching an assertion, so that result is retained as `HARNESS_ERROR` rather than counted as mutation sensitivity.

Observed credits are runtime-reported cost multiplied by 100 and are not reconciled with provider billing. The total observed dispatch spend was 471.98711 credits under the approved 500-credit ceiling.

## Routing

Routing remains unchanged. The experiment did not edit or activate any routing profile.
