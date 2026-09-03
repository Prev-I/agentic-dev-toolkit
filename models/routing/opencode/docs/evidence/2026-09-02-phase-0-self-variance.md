# Phase 0 Harness Self-Variance Method

## Status

The measurement mechanism and three-run repeated dataset are complete.
Continuous thresholds remain blocked until they are derived and committed from
this evidence. Candidate A/B results remain hidden.

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

## Measured run set

Three valid non-candidate instrumentation runs used
`github-copilot/gpt-5.6-luna` at `low` on OpenCode `1.18.27`. All used fixture
digest `sha256:e73d235d29ddb246244f72fc752bfb7475652076915824083b80779da7c1636d`,
routing profile commit `3bde30f0d606ebf21e622f697d9c920f0e3a4453`, and runner version
`phase0-self-variance-v1`. No environment-invalid attempts occurred.

| Attempt | Wall-clock ms | Tokens | Derived Copilot credits |
|---:|---:|---:|---:|
| 1 | 7142 | 10660 | 0.267245 |
| 2 | 7652 | 10660 | 0.022318 |
| 3 | 6299 | 10660 | 0.022318 |

Total measured consumption was `0.311881` derived credits and `31980` tokens,
within the approved 100-credit evaluation budget.

The measured checks all pass:

- fixture determinism: `true`;
- scoring repeatability: `true`;
- instrumentation consistency: `true`;
- credit-report consistency: `true`;
- candidate results used: `false`.

Wall-clock median was `7142 ms`, range `1353 ms`, and relative range
`18.9443%`. Derived-credit median was `0.022318`, range `0.244927`, and relative
range `1097.4415%`. The cost spread is retained rather than discarded: the
first uncached call was materially more expensive than the two cache-read
calls. Threshold derivation must account for this observed warm-cache effect.

This three-run operational measurement does not support a statistical
significance claim.
