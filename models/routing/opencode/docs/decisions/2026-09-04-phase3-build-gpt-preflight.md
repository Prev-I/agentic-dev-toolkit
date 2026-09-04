# Phase-3 Build Opus-vs-Sol Preflight — 2026-09-04

A **zero-spend preflight**: freezes a second Build A/B experiment design and
derives its prospective budget from existing repository evidence. **It does
not execute the experiment.** Machine-readable form:
`eval/manifests/phase3-build-gpt-preflight.json`.

## Prerequisite

PR #15 (Opus-vs-Sonnet Build result, `docs/decisions/2026-09-04-phase3-build-ab-result.md`)
is merged to `main`. Phase R remains `PASS`. Canonical baseline
`v1-restored-2026-09.jsonc` is unchanged. Current production routing:
`Build: github-copilot/claude-opus-5 high`,
`Reviewer: github-copilot/gpt-5.6-sol high` — both confirmed against the live
`opencode.jsonc` before writing this document.

## Scope

Only this hypothesis:

```text
INCUMBENT:  Build -> github-copilot/claude-opus-5, variant high
CHALLENGER: Build -> github-copilot/gpt-5.6-sol,   variant high
```

Build role only. Does not evaluate Reviewer, Sonnet, General, Explore, Scout,
Compaction, Expert, or any other model. A potential Reviewer inversion
(Sol high vs Opus 5 for the Reviewer role) is a **separate, future,
not-yet-designed** hypothesis — not started here.

## Why production routing does not change on a Sol win

Reviewer is currently `github-copilot/gpt-5.6-sol high`. If this experiment
concluded Sol should replace Opus for Build and production routing were
changed immediately, Build and Reviewer would both become Sol high,
silently removing the controller/reviewer model-family separation the
routing bundle's own design relies on
(`docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md`'s reviewer
independence rationale) — without any explicit decision to accept that
tradeoff. This preflight therefore freezes an **activation policy** (below)
that defers activation regardless of outcome.

## Experiment philosophy — same incumbent bias as Opus-vs-Sonnet

```text
Sol functional regression, either workload      -> KEEP OPUS
Sol functional tie, threshold not cleared       -> KEEP OPUS
genuinely inconclusive evidence                 -> KEEP OPUS
Sol non-inferior AND precommitted advantage shown -> SOL_WINS_BUILD_EXPERIMENT
                                                    (production routing still
                                                     unchanged -- see below)
```

No weighted aggregate score. A tie means KEEP OPUS.

## Workload reuse — no new fixtures

Reuses `build-feature` and `build-bugfix` **unchanged** from the executed
Opus-vs-Sonnet experiment: same snapshot, task, oracle, regression suite,
forbidden-scope assertions, and provenance mechanism
(`eval/runtime/opencode-v1-adapter/run-phase3-build-fixture.sh`, unmodified).
This makes Opus-vs-Sonnet and Opus-vs-Sol directly comparable at the
experiment-design level. `build-refactor` remains conditional and
unauthored; not part of this preflight. No new fixture, no third workload.

Both fixtures were confirmed present and unmodified on this branch
(`git diff --stat main` touches no file under `eval/fixtures/build-workloads/`).
Fixtures will not be modified unless a deterministic local test proves a
defect capable of invalidating the Sol-vs-Opus decision — no proactive
hardening was performed or is planned.

## Paired execution order

Frozen, counterbalanced, identical structure to the Opus-vs-Sonnet
experiment:

```text
Pair 1 (build-feature): Opus -> Sol
Pair 2 (build-bugfix):  Sol -> Opus
```

Each pair: same fixture revision, same repository snapshot, same task, same
oracle, same regression suite, same forbidden-scope constraints, a fresh
isolated workspace per arm, same harness revision.

## Invalid-attempt replacement rule

Unchanged from the previous experiment: **pair-level replacement.**
`INVALID_ENVIRONMENT` discards and redispatches the whole pair (if budget
allows). `VALID_CONTROLLER_FAILURE` is permanent evidence, never replaced.
A `FIXTURE_DEFECT` capable of invalidating the decision stops the
experiment; poor-but-valid outcomes are never rerun; no open-ended sampling.

## Decision criteria (reused verbatim)

```text
1. correctness / task success
2. invariant preservation
3. scope / plan adherence
4. human correction required
5. convergence / retries
6. wall-clock time
7. steady-state cost
```

Functional criteria (1-5) dominate operational criteria (6-7): a
faster/cheaper challenger cannot compensate for worse correctness.

## Final adoption rule (reused verbatim, s/Sonnet/Sol/)

**Functional regression.** Sol worse than Opus on any earlier functional
criterion (1-5), either workload -> **KEEP_OPUS**. No operational
compensation.

**Functional improvement.** Sol strictly better under the earliest
differentiating functional criterion (1-5), not worse on the other workload
under any earlier-or-equal-priority functional criterion -> **SOL_WINS_BUILD_EXPERIMENT**.
Wall-clock not required. Production routing still does not change
immediately — see Activation policy below.

**Functional tie.** Criteria 1-5 tied on both workloads -> Sol must clear the
precommitted **37.8885%** wall-clock relative-range threshold on **both**
`build-feature` **and** `build-bugfix` independently, using the exact same
formula already committed by the Opus-vs-Sonnet preflight
(`relative_range = (max(a,b)-min(a,b)) / ((a+b)/2)` over the two arms'
`wall_clock_ms`) — not reinterpreted or recomputed. No averaging, no
one-workload win compensating for the other.

**Anything else** (tie, mixed result, one-workload-only advantage, threshold
not reached, inconclusive, insufficient valid evidence in budget) ->
**KEEP_OPUS**.

**Cost is observational only** under every branch; cannot trigger adoption.

**Wall-clock threshold caveat, preserved unchanged**: 37.8885% is a
precommitted minimum-practical-effect bar derived from Phase-0 self-variance
on a *different* fixture family (`github-copilot/gpt-5.6-luna`,
`docs/evidence/2026-09-02-phase-0-self-variance.md`). It is not a
statistical-significance threshold and is not claimed to characterize
Build-specific latency variance — Build's own historical wall-clock range is
**10.7%-1081.5%** depending on cold-cache inclusion
(`eval/records/phase-r/build/attempt-{1,2,3}/dispatch/dispatch.json`), a
materially wider range than the frozen threshold, already disclosed by the
Opus-vs-Sonnet preflight and not re-litigated here. Requiring both workloads
to clear the threshold independently is deliberate outlier protection: with
one dispatch per arm per pair, a single cold-cache or otherwise atypical
dispatch could dominate the primary criterion for an entire pair. **Not
retuned after the Opus-vs-Sonnet result, and not re-derived merely because
Sol is a different challenger** — using the identical rule is what keeps
the two Build experiments comparable.

## Activation policy — frozen regardless of outcome

```text
GPT loses / ties / inconclusive:
    -> KEEP_OPUS
    -> keep current production routing (Build: Opus high, Reviewer: Sol high)
    -> optimization line may stop unless a new material hypothesis exists

GPT wins:
    -> record: PREFERRED_BUILD = SOL_HIGH, STATUS = PENDING_REVIEWER_SEPARATION_DECISION
    -> production routing remains UNCHANGED
    -> next possible experiment: Reviewer Sol high vs Claude Opus 5
       (goal: determine whether an atomic family inversion is justified;
       NOT designed here, and the Reviewer 5/5 benchmark is NOT reopened
       by this preflight)
```

A later, explicit, separate decision determines whether an atomic
Build/Reviewer inversion is warranted.

## Sample size

```text
initial pairs:      2 (build-feature, build-bugfix)
opus dispatches:    2
sol dispatches:     2
total dispatches:   4
```

No automatic extension beyond this initial sample; the execution prompt
stops for human decision rather than open-ended sampling, same as before.

## Historical budgets — closed, not reused

```text
evaluation:                     approved 100, observed >=289.01, BREACHED
recovery:                       approved 250, observed 349.94,   BREACHED
phase3 build (opus vs sonnet):  approved 158, consumed 76.83485, COMPLETE, CLOSED
```

The Opus-vs-Sonnet experiment's unused allowance (81.16515 credits) is
**not** transferable to this experiment. This preflight derives its own new,
separate prospective budget, below.

## Proposed Phase-3 Build (Opus vs Sol) budget

```text
phase3_build_gpt_budget:
    central estimate:     122.42 credits
    conservative ceiling: 264 credits (includes a 1.3x role-transfer
                          margin on the Sol side, plus a 1-pair
                          replacement allowance for INVALID_ENVIRONMENT)
    status:               PENDING_HUMAN_APPROVAL
```

### Derivation

**Opus cost/run** — real, corrected, direct evidence from the
already-executed Opus-vs-Sonnet experiment (not re-derived):

```text
build-feature: 28.62365 credits (eval/records/phase3-build-ab/build-feature/pair1-arm1-opus/attempt.json)
build-bugfix:  26.95890 credits (eval/records/phase3-build-ab/build-bugfix/pair2-arm2-opus/attempt.json)
central (2 runs): 55.58255
ceiling per run:  28.62365 (the higher of the two; also the highest Opus
                  Build cost observed across all evidence, including
                  build-restoration-gate's 23.194-26.192 range)
```

**Sol cost/run** — no live Sol Build history exists (this experiment would
produce the first). Estimated from 6 real, cost-corrected, `github-copilot/
gpt-5.6-sol`, `high`, standard-pricing-regime, **multi-turn** dispatches: the
current/final Phase-R Reviewer gate run
(`eval/records/phase-r/reviewer/{R-API,R-AUTH,R-BOUNDARY,R-CONCURRENCY,R-ERROR,clean}/dispatch/dispatch.json`,
all corrected under the I1 cost-accounting fix):

```text
observed credits: 45.599350, 22.540000, 36.435250, 30.087775, 34.921425, 30.941050
mean: 33.4208    min: 22.5400    max: 45.5993

central (2 runs):  66.8417
ceiling (2 runs), no assumed Sol savings: 91.1987
```

**Uncertainty, stated plainly, per this task's own requirement not to claim
Reviewer cost as a precise Build estimate**: this is **Reviewer-role**
evidence (read-only code review; no file edits, no test execution) used as a
cross-workload directional anchor for **Build-role** cost (read-write; edits
files, runs two test suites) — no Sol Build history exists to derive from
directly. The decimal precision above should not be read as workload-specific
accuracy; it is the real observed distribution, reported honestly, not a
manufactured estimate. The token/turn-count ranges are **adjacent, not
overlapping**: the real Opus Build dispatches ran 23,457-24,193 tokens across
7-8 turns; the 6 Sol Reviewer dispatches ran 24,548-29,706 tokens across
3-10 turns. (An earlier draft of this document stated "21k-28k tokens,
3-6 turns" for the Opus side — independent review measured the real figures
directly from the raw dispatch records and found that range manufactured a
false overlap that does not exist in the data; corrected here.) Because the
ranges are adjacent rather than overlapping, this is judged a **defensible**
anchor rather than grounds to stop — but only with an explicit role-transfer
margin applied to the ceiling (below), not by treating the raw Reviewer max
as already conservative. A single trivial capability probe considered and
**rejected**: `eval/records/phase-r/preflight/reviewer.json` (cost 5.3532
credits, 10686 tokens, **no cache** at all) has a token/cache shape
incomparable to both the real Opus Build dispatches and the ratio-derivation
probes used for the Sonnet estimate (~18.1-18.2k tokens, high cache-write) —
using it would have manufactured false precision from one unrepresentative
sample. A second Sol probe (`eval/records/gpt-5.6-sol-copilot-high.json`) was
excluded for a different reason: its `pricing_regime` is `promotional`, not
`standard`, so it is not comparable to any of the other evidence used
throughout this and the prior preflight. (Pricing regime is recorded once at
the run level, in `eval/records/phase-r/reviewer/outcome.json`'s
`pricing_regime` field — the individual `dispatch.json` files do not carry
it themselves.) Separately: this Reviewer gate run's own review-quality
verdict is marked invalidated by a fixture defect
(`eval/records/phase-r/reviewer/outcome.json`) — that invalidation concerns
review-quality adjudication, not dispatch cost, which is real and unaffected.

**Role-transfer margin, added per independent review (2026-09-04)**: the
review measured credits-per-turn directly — Opus Build ran 7-8 turns at
3.58-3.85 credits/turn; the 6 Sol Reviewer dispatches ran 3-10 turns at a
mean 5.73 credits/turn (~1.54x Opus's per-turn rate). Projecting Sol's own
observed per-turn rate across an Opus-like 7-8 turn Build dispatch already
lands at ~43-46 credits — essentially equal to the raw (unmargined)
per-run ceiling of 45.5993, meaning that figure had almost no headroom for
the cross-workload uncertainty this estimate already discloses. A **1.3x**
margin is applied to the Sol ceiling (not the central estimate, which stays
the unpadded mean) to restore genuine headroom: 45.5993 x 1.3 = 59.2792
credits/run.

```text
central (4 dispatches):    55.58255 (opus) + 66.8417 (sol)  = 122.42425 -> 122.42
ceiling (4 dispatches):    57.2473 (opus, 2x28.62365) + 118.5583 (sol with margin, 2x59.2792) = 175.8056
replacement allowance:     1 pair at margined ceiling rates: 28.62365 (opus) + 59.2792 (sol) = 87.90285
total conservative ceiling:                                                                    263.70845
                                                                                        rounded up to 264
```

Internally consistent: the ceiling (264) exceeds the central estimate
(122.42) and the ceiling-without-replacement (175.81), so the proposed cap
genuinely covers its own stated worst case plus the replacement allowance —
the same class of arithmetic error flagged and fixed in the prior Reviewer
remediation and re-checked in the Opus-vs-Sonnet preflight is checked for
here and does not recur.

**Cost-accounting mechanism**: `eval/runtime/opencode-v1-adapter/dispatch-fixture.sh`,
post-I1-fix (commit `505d35a`) — sums every `step_finish` `part.cost` across
a multi-turn dispatch, not just the last step. This is the same,
unmodified mechanism already used for the Opus-vs-Sonnet execution; no new
accounting code is introduced by this preflight.

Not self-approved. Distinct from, and does not modify, the historical
100/250 caps, the closed 158-credit Opus-vs-Sonnet budget, or the
organizational 7,600-credit/billing-cycle guardrail (a separate, external
control — 264 credits does not implicate it).

## Known non-blocking limitations

- Sol's cost estimate is cross-workload (Reviewer, not Build) — disclosed
  above, not hidden. The ceiling compensates by using the real observed
  maximum, not a rosier central figure.
- The interpretive question raised in the Opus-vs-Sonnet preflight about the
  n=3-vs-n=2 count-based separation table applies identically here (2
  initial workloads, not 3) — same reading applies: a clean 2/2-vs-0/2 sweep
  is decisive, 0/2-vs-0/2 is a fixture/scenario finding, any other split
  requires the next ordered criterion or escalation to the conditional
  `build-refactor` workload.
- No proactive harness hardening was performed. The rule applied throughout:
  "could this issue materially cause the wrong Build controller to be
  selected?" — nothing found here meets that bar.
- **Disclosed, not fixed, per independent review (2026-09-04)**: the new
  consistency test catches every mutation targeting the budget-defensibility,
  routing-safety, and Reviewer-scope checks above, but not every conceivable
  mutation of the manifest's prose fields (e.g. an internally-absurd but
  self-consistent central estimate, or a citation swap that a downstream
  number-check would still catch independently). None of these gaps affect
  what this preflight actually asserts — they are test-coverage margin, not
  design defects — and are recorded rather than chased with further hardening.
  No replacement-pair cap beyond "at most one" is separately enforced in
  code; this mirrors the Opus-vs-Sonnet experiment (which needed zero
  replacements) and is not a regression.

None of these can cause a *wrong* Opus-vs-Sol adoption decision (the
tie/inconclusive policy holds regardless, and a Sol win still does not
change production routing immediately), so none block this preflight per
its own governing rule.

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
40/40 PASS

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check
(clean)
```

Confirmed:

```text
production routing:        unchanged (Build: Opus 5 high, Reviewer: Sol high)
v1-restored baseline:      unchanged
build-feature/build-bugfix fixtures: unchanged (reused as-is)
live model calls:          0
additional AI credits:     0
Phase 3 GPT experiment:    not executed
Reviewer experiment:       not executed, not reopened
```
