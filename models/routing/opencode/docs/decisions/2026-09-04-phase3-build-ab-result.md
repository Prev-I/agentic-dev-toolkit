# Phase-3 Build A/B Result — 2026-09-04

Executes the experiment frozen by `docs/decisions/2026-09-04-phase3-build-ab-preflight.md`
and approved (158 credits) by `docs/decisions/2026-09-04-phase3-build-ab-preflight.md`'s
approval amendment (PR #14). Machine-readable form:
`eval/records/phase3-build-ab/adjudication.json`. Raw provenance:
`eval/records/phase3-build-ab/{build-feature,build-bugfix}/pair*/`.

## Configuration (unchanged from the frozen preflight)

```text
incumbent:  github-copilot/claude-opus-5,   variant high
challenger: github-copilot/claude-sonnet-5, variant high
budget:     158 credits, APPROVED
workloads:  build-feature (pair 1), build-bugfix (pair 2)
order:      feature: opus -> sonnet
            bugfix:  sonnet -> opus
```

## Execution

All 4 planned dispatches completed `OK` on the first attempt. No
`INVALID_ENVIRONMENT`, no replacement pairs, no `FIXTURE_DEFECT`.

```text
Pair 1 / build-feature
  Opus:   OK, oracle PASS, regression PASS, wall-clock 51586 ms, 28.62365 credits
  Sonnet: OK, oracle PASS, regression PASS, wall-clock 25447 ms,  8.32915 credits

Pair 2 / build-bugfix
  Sonnet: OK, oracle PASS, regression PASS, wall-clock 39369 ms, 12.92315 credits
  Opus:   OK, oracle PASS, regression PASS, wall-clock 43981 ms, 26.95890 credits
```

Budget consumed: **76.83485 / 158 credits** (81.17 remaining, unused —
no replacement was needed).

## Functional adjudication (criteria 1-5)

```text
1. correctness/task success:      tied (4/4 OK, 4/4 oracle_passed)
2. invariant preservation:        tied (4/4 regression_passed)
3. scope/plan adherence:          tied (forbidden-scope oracle assertion held, all 4)
4. human correction required:     tied (0 -- single automated dispatch per arm)
5. convergence/retries:           tied (retry_count 0, all 4)
```

**Result: functional tie**, both workloads. No regression by Sonnet on
either workload; no advantage either. Per the frozen final adoption
rule, a functional tie requires the wall-clock branch.

## Wall-clock adjudication (frozen formula, applied independently per workload)

Using the same `relative_range = spread / median` formula already
committed by the preflight and self-variance evidence (`spread = max -
min`, `median` of the two arm values):

```text
build-feature: opus 51586 ms, sonnet 25447 ms
  relative_range = (51586-25447) / ((51586+25447)/2) = 0.678644 (67.8644%)
  clears 37.8885% threshold: YES (sonnet favorable)

build-bugfix:  sonnet 39369 ms, opus 43981 ms
  relative_range = (43981-39369) / ((43981+39369)/2) = 0.110666 (11.0666%)
  clears 37.8885% threshold: NO (sonnet nominally faster, not by enough)
```

**Required for adoption**: both workloads independently clear
37.8885%, favorable to Sonnet. `build-feature` clears it; `build-bugfix`
does not. Per the frozen rule — *"No aggregation. No averaging. Do not
let one large win compensate for one non-win."* — this is exactly the
scenario the rule exists to catch: `build-feature`'s large 67.9% win
does not rescue `build-bugfix`'s 11.1% non-win.

## Cost (observational only, not used for the decision)

```text
Opus total:   55.58255 credits (28.62365 + 26.95890)
Sonnet total: 21.25230 credits ( 8.32915 + 12.92315)
```

Sonnet was cheaper on both workloads, consistent with the preflight's
pricing-ratio estimate — recorded for visibility, but cost cannot
trigger adoption under the frozen rule regardless.

## Final decision

```text
FINAL DECISION: KEEP_OPUS
```

Functional criteria 1-5 tied on both workloads; the wall-clock branch's
"both workloads independently" requirement was not met (`build-bugfix`
fell short). Per the frozen rule's "anything else" branch — advantage
on only one workload — the result resolves to **KEEP_OPUS**.

## Routing impact

None. `Build: github-copilot/claude-opus-5 high` is unchanged. Production
routing was never modified during measurement: all 4 dispatches used
direct `--model`/`--variant` overrides against fresh, isolated,
per-arm sandboxes (`dispatch-fixture.sh`), never the routed `build`
agent identity or the user-global active profile. `v1-restored-2026-09.jsonc`
is unchanged.

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
39/39 PASS

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check
(clean)
```

Confirmed:

```text
other routing rows:        unchanged (Build only, no other role touched)
Reviewer experiment:       not executed
GPT experiment:            not executed
Phase 4:                   not started
live model calls:          4 (2 opus, 2 sonnet) -- exactly the frozen initial sample
additional AI credits:     76.83485 (within the 158-credit approved cap)
```
