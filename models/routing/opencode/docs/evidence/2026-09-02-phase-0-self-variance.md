# Phase 0 Harness Self-Variance Method

## Status

The measurement mechanism is implemented and tested. Continuous thresholds are
not yet frozen because no approved repeated-run self-variance dataset has been
recorded. Candidate A/B results must remain hidden until that dataset is
measured and practical separation thresholds are committed.

## Input record

Each repeated harness run supplies:

- `fixture_digest`: digest of the immutable fixture input;
- `score`: complete scorer output for repeatability comparison;
- `instrumentation_schema`: version of the captured run instrumentation;
- `credit_report.observed_cost` and `credit_report.tokens`: required credit
  instrumentation fields.

At least three repeated records are required. The measurement refuses incomplete
records and records no candidate output.

## Measurements

`eval/scoring/self-variance.sh` computes four independent checks:

| Check | Meaning |
|---|---|
| `fixture_determinism` | Every repeated run used the same fixture digest. |
| `scoring_repeatability` | Re-scoring equivalent runs produced identical structured scores. |
| `instrumentation_consistency` | Every run used the same instrumentation schema. |
| `credit_report_consistency` | Credit reports retained the same required field/type shape; values may vary. |

The output retains the sample count and explicitly records
`candidate_results_used: false`. `freeze_thresholds` accepts only a completed
self-variance record with that exclusion intact and a `self-variance` source.
It rejects missing measurements and candidate-result input.

## Ordering gate

The required order remains:

1. Record repeated harness runs and measure self-variance.
2. Commit practical continuous-metric separation thresholds.
3. Only then expose candidate A/B results.

`eval/thresholds/continuous.json` therefore remains
`blocked_until_self_variance`; it contains no numerical thresholds. This is a
Phase-0 readiness boundary, not authority to execute Phase R or comparative
candidate evaluations.
