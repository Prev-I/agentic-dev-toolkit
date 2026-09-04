# Phase-3 Build Optimization Cycle — Closure — 2026-09-04

Documentation/status closure only. **No routing change, no new experiment,
no live model call.** Records the outcome of the two completed Build
challenger experiments and closes this hypothesis-driven optimization
cycle. Source records: `docs/decisions/2026-09-04-phase3-build-ab-result.md`
(Opus vs Sonnet) and `docs/decisions/2026-09-04-phase3-build-gpt-result.md`
(Opus vs Sol), both merged to `main`.

## Final routing status (unchanged, verified against live evidence)

```text
Build:      github-copilot/claude-opus-5, variant high
Reviewer:   github-copilot/gpt-5.6-sol,   variant high
```

Confirmed directly against the live `opencode.jsonc` (the loaded, active
user-global configuration) at the time of writing; cross-checked against
`eval/records/phase-r/effective-routing.json` (`status: "PASS"`,
`mismatches: []`), which was itself captured before either Build experiment
ran and so is corroborating evidence, not a post-hoc verification of these
specific experiments. Neither role changed as a result of either
experiment.

**Evidence base for both experiments below, stated once rather than
per-section**: each rests on 2 workloads, 1 dispatch per arm, no
repetition, no replacement pairs needed (n=4 dispatches each) — the frozen
initial sample per experiment, not extended. Both conclusions below should
be read at that scale.

## Build: Opus vs Sonnet — COMPLETE, KEEP_OPUS

Functional result: **tie** (both models passed correctness, invariant
preservation, and scope adherence on both workloads; no human correction;
zero retries). Decision: **KEEP_OPUS**, because Sonnet cleared the frozen
37.8885% wall-clock threshold on only one of the two workloads
(`build-feature`, 67.86%) and not the other (`build-bugfix`, 11.07%) — the
frozen rule requires both, independently, with no averaging.

**Durable secondary observation, preserved rather than discarded**: Sonnet
showed substantially lower observed cost and a favorable latency signal on
the workload where it won, but did not clear the frozen operational
threshold on both workloads. This is not reinterpreted as a Sonnet failure.
Its meaning going forward: **Sonnet remains a credible efficiency-oriented
challenger, but did not meet the current incumbent-replacement bar.** A
future experiment could reasonably revisit Sonnet under a new material
trigger (see "Future optimization policy" below), without needing to treat
this result as a permanent verdict on Sonnet's general capability.

Full detail: `docs/decisions/2026-09-04-phase3-build-ab-result.md`.

## Build: Opus vs Sol — COMPLETE, KEEP_OPUS

Decision: **KEEP_OPUS**. Sol regressed on the earliest functional criterion
(correctness/task success) on `build-feature`: a genuine
`VALID_CONTROLLER_FAILURE`, not a harness or environment defect — the
dispatch itself was healthy (exit 0, no provider error, no timeout, 8
completed turns ending in a natural `stop`). Sol invoked a
design-confirmation skill and stopped to request human approval, which a
non-interactive, single-shot dispatch cannot provide, and so never
implemented the required change. Per the frozen adoption rule, a
functional regression on either workload is dispositive on its own;
wall-clock and cost were correctly not consulted as decision inputs.
**Correction, per independent review**: Sol was cheaper on both workloads,
but not faster overall — it was faster only on the `build-feature` dispatch
it never completed (stopping early is, unsurprisingly, quick), and 42.9%
*slower* on `build-bugfix`, the one workload it actually finished. This
sample is 2 workloads, one dispatch per arm, no repetition — too small to
generalize a latency profile from regardless, and none of it changes the
decision either way.

**The supported conclusion is scoped narrowly, on purpose**:

```text
SUPPORTED:
    Sol high did not satisfy the current non-interactive Build execution
    contract well enough to replace Opus high.

NOT CLAIMED:
    Sol is generally worse than Opus for software engineering.
```

This distinction is load-bearing if the Build execution contract changes in
the future (for example, an interactive approval channel, or a harness that
pre-approves bounded designs) — such a change would constitute a new,
material trigger for revisiting Sol, not a reason to consider this result
already settled against a different contract.

Full detail: `docs/decisions/2026-09-04-phase3-build-gpt-result.md`.

## Reviewer inversion path — NOT_TRIGGERED

The Reviewer-inversion hypothesis (Reviewer Sol high vs Claude Opus 5,
motivated by the possibility of an atomic Build/Reviewer family inversion)
was explicitly conditional on Build Sol defeating Build Opus. That
condition did not occur.

```text
Reviewer Sol-vs-Opus experiment: NOT_TRIGGERED
reason: Build Sol did not win its prerequisite experiment
```

This is **not** a failed experiment — it was never designed, pre-registered,
or executed, and is not started by this closure. The Reviewer seeded-defect
benchmark (5/5 + clean-zero) is not reopened.

## Final Phase-3 state

```text
Phase R:                            PASS
Build Opus vs Sonnet:                COMPLETE, KEEP_OPUS
Build Opus vs Sol:                   COMPLETE, KEEP_OPUS
Reviewer inversion:                  NOT_TRIGGERED
Further proactive model optimization: STOPPED
```

This closes the **current hypothesis-driven optimization cycle** — not
Phase 3 globally, and not a claim that model optimization is exhaustive.
Future experiments may still be opened for new, evidence-driven hypotheses
under the policy below.

## Future optimization policy — observation-driven

```text
optimization mode: observation-driven
```

Proactive, exists-because-it's-new benchmarking of every model/version is
not the policy. A future experiment requires at least one material trigger:

- real-world correctness failures
- material Reviewer misses
- material Reviewer false positives
- repeated human correction
- unacceptable latency
- unacceptable cost
- a new credible model challenger, with a stated, specific reason to expect
  it changes a current routing decision (not merely that it is new)
- a material model/version change to an already-routed model
- a change to the Build execution contract

Governing principle, unchanged: **an experiment should exist only when its
result can change a real routing decision.**

## Evaluation-engineering scope stays bounded

Evaluation infrastructure (fixtures, oracles, dispatch harness, ledgers) is
supporting tooling, not a product goal. Harness/scorer limitations are
fixed only when they can materially change a *pending* routing decision.

The following non-blocking findings, already disclosed in the two
experiment result docs, are **not** opened as new work by this closure —
they may be reconsidered only if a future experiment actually requires it:

- sandbox git visibility — disclosed for the Opus-vs-Sol experiment in
  `2026-09-04-phase3-build-gpt-result.md`; this closure additionally
  confirms the same was true of the Opus-vs-Sonnet experiment's sandboxes
  (not disclosed in that result doc, verified here instead), and that
  neither outcome was affected in either experiment
- skill-version provenance (the installed Superpowers version is not
  recorded in `dispatch.json`)
- a reproducible experiment driver script
- Reviewer witness-perfection gaps (from the Reviewer
  observability/attribution remediation)
- Build-specific wall-clock variance modeling (the frozen 37.8885%
  threshold's cross-fixture-family origin, already disclosed in both Build
  preflights)

## Budget history — preserved, not rebased

```text
Phase-R evaluation:            >=289.01 / 100,  BREACHED (closed)
Phase-R recovery:               349.94 / 250,   BREACHED (closed)
Phase-3 Build (Opus vs Sonnet):  76.83485 / 158, COMPLETE (closed)
Phase-3 Build (Opus vs Sol):     94.038   / 264, COMPLETE (closed)
```

Figures taken from the authoritative ledgers: `eval/records/phase-r/budget-ledger.json`
(evaluation/recovery), `eval/records/phase3-build-ab/ledger.json` (Opus vs
Sonnet), `eval/records/phase3-build-gpt/ledger.json` (Opus vs Sol). None of
these figures are rebased or reinterpreted. Unused allowance from any of
the four is **not** reusable funding for a future experiment — each closed
budget stays closed. No new optimization budget is created by this closure;
a future experiment's budget is derived fresh from evidence current at that
time, per the same preflight discipline already established.

## Canonical baseline — unchanged

`profiles/v1-restored-2026-09.jsonc` remains the canonical restored Phase-R
baseline, unmodified by this closure or by either Build experiment (both
used direct `--model`/`--variant` overrides against isolated sandboxes,
never touching this file or the live `opencode.jsonc`). This closure records
later Phase-3 decisions in this document and in `README.md`'s status
pointer — it does not mutate the historical restored snapshot to encode
them.

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
42/42 PASS

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check
(clean)
```

Confirmed:

```text
production routing:        unchanged (Build: Opus 5 high, Reviewer: Sol high)
user-global config:        unchanged
fixtures:                  unchanged
scorers:                   unchanged
dispatch scripts:          unchanged
live model calls:          0
additional AI credits:     0
new benchmark opened:      none
```
