# Phase-3 Build A/B Preflight — 2026-09-04

A **zero-spend preflight**: this document freezes the Build Opus-vs-Sonnet
experiment design and derives its prospective budget from existing
repository evidence. **It does not execute the experiment.** Machine-
readable form: `eval/manifests/phase3-build-ab-preflight.json`.

## Prerequisite

Phase R is `PASS` (`docs/decisions/2026-09-04-phase-r-scope-amendment.md`,
merged PR #12). `v1-restored-2026-09.jsonc` is the canonical restored
baseline. Phase 3 has not started before this document.

## Scope

Only this hypothesis:

```text
INCUMBENT:  Build -> github-copilot/claude-opus-5,   variant high
CHALLENGER: Build -> github-copilot/claude-sonnet-5, variant high
```

No other role is in scope. This is the first approved Phase-3 candidate
per the scope amendment, chosen because Build's impact is high, its
fixture family is deterministic, and controller quality has direct
engineering value — not because every routing row is due for a
comparison.

## Experiment philosophy — incumbent-biased, no forced winner

The restored baseline is already operationally valid. The experiment is
deliberately biased toward keeping it:

```text
functional regression by Sonnet                    -> KEEP OPUS
functional equivalence, no demonstrated advantage   -> KEEP OPUS
genuinely inconclusive evidence                     -> KEEP OPUS
Sonnet non-inferior AND precommitted advantage shown -> ADOPT SONNET
```

No weighted aggregate score. A tie means KEEP OPUS.

## Workload selection

Repository-committed Build fixture family
(`eval/fixtures/build-workloads/`):

```text
build-restoration-gate   -- Phase-R mechanical gate, EXCLUDED from
                             Phase-3 comparative use (own metadata:
                             excluded_from_phase_3_selection: true)
build-feature            -- Phase-3 realistic scenario
build-bugfix             -- Phase-3 realistic scenario
build-refactor           -- Phase-3 realistic scenario, CONDITIONAL
```

**Deviation from a default 3-pair design, reported explicitly**: this
preflight uses 2 initial pairs (build-feature, build-bugfix), not 3, for
two independent reasons:

1. The governing decision document's own pre-registered design (section
   24, "Sequential scenario stopping") already specifies this: *"Run
   feature and bugfix first. Run `build-refactor` only if the first two
   scenarios do not produce a decision."* Repository evidence is
   authoritative; this preflight does not recreate a different rule.
2. `build-feature` and `build-bugfix` previously existed only as bare
   `fixture.json` manifests — no snapshot, oracle, task, or regression
   content, despite declaring properties like
   `acceptance_tests_initially_failing: true` as if they were already
   verified. This preflight authored minimal, deterministic content for
   both (mirroring `build-restoration-gate`'s exact shape), mechanically
   verified by `eval/tests/build-phase3-fixtures-test.sh`:
   - `build-feature`: add a `reverse` function to `lib/strings.sh`
     (a missing capability), regression-protecting `upper`.
   - `build-bugfix`: fix a real bug in `lib/validate.sh`'s
     `is_positive` (wrongly accepts `0`), regression-protecting the
     correct, pre-existing `is_blank`.

   `build-refactor` was deliberately **not** authored now — doing so
   before the sequential-stopping rule calls for it would be presumptive,
   and authoring it is itself non-trivial fixture work. **If the
   conditional trigger fires, `build-refactor`'s fixture content does not
   yet exist and must be authored at that time as separate follow-up
   work** — this preflight's budget does not cover that contingency.

## Paired execution order

Frozen before any result exists, counterbalanced:

```text
Pair 1 (build-feature): Opus -> Sonnet
Pair 2 (build-bugfix):  Sonnet -> Opus
Pair 3 (build-refactor, CONDITIONAL): Opus -> Sonnet
```

Each pair uses: the same fixture snapshot, the same task, the same oracle,
the same regression suite, the same forbidden-scope assertions, a fresh
isolated workspace per arm, the same harness revision, and the same
routing-profile baseline except the Build model — identical to how
`build-restoration-gate`'s 3 attempts were already run.

## Invalid-attempt replacement rule

Frozen: **pair-level replacement.** If either arm of a pair is classified
`INVALID_ENVIRONMENT`, the entire pair is discarded and replaced with a
fresh pair (both arms redispatched), not just the affected arm — this
preserves paired comparability (same fixture, same moment, same harness
revision for both arms), which single-arm replacement would not.

`VALID_CONTROLLER_FAILURE` and `FIXTURE_DEFECT` remain genuine evidence
and are never silently rerun.

## Decision criteria (already-approved, not invented)

From the governing decision document, section 21 — used verbatim, not
paraphrased:

```text
1. correctness / task success
2. invariant preservation
3. scope / plan adherence
4. human correction required
5. convergence / retries
6. wall-clock time
7. steady-state cost
```

Section 22's count/binary separation rules (n=3, extend to n=5 only under
its own precommitted conditions) apply to the count-based criteria.
Section 23's ordering requirement (measure self-variance, commit
thresholds, only then expose candidate results) is already satisfied —
see below. Functional criteria (1-3) dominate operational criteria (6-7):
a faster/cheaper challenger cannot compensate for worse correctness.

**Genuine open interpretive question, flagged rather than silently
resolved**: the committed n=3 gap table (section 22.1) is defined over 3
completed trials. With only 2 initial workloads, a clean 2/2-vs-0/2 sweep
is treated as decisive (analogous in strength to the committed 3/3-vs-0/3
"separates" case), and 0/2-vs-0/2 is treated as a fixture/scenario finding
(analogous to the committed defensive halt). Any other 2-workload split
(1/2-vs-1/2, 1/2-vs-0/2, etc.) is inconclusive on the correctness
criterion from the initial 2 pairs alone and requires either the next
ordered criterion (using the same 2 workloads' other evidence) or
escalation to the conditional 3rd workload — the document does not
explicitly define a 2-of-3 shortcut, and this preflight does not invent
one beyond what's stated here. Confirm or correct this reading before
execution.

## Primary operational advantage — frozen before results exist

**Wall-clock time**, per the task's own stated preference, using the
already-frozen self-variance threshold
(`docs/evidence/2026-09-02-phase-0-self-variance.md`): a
**37.8885% relative-range separation** is required before a wall-clock
difference counts as real, not harness noise. This preflight does not
retune that threshold.

**Cost is secondary/observational only, not primary.** The frozen
comparable-credits threshold is **2194.8831%** relative range — a
practically undischargeable bar given historical Build cost variance
(23.19-26.19 credits across 3 real Opus runs is nowhere near a
~22x-relative-range separation). Cost is recorded and reported in full,
never used to declare a winner.

**What Sonnet must demonstrate to justify adoption**: non-inferior
correctness and invariant preservation (criteria 1-3, per the ordered
separation rules) **AND** a wall-clock advantage that clears the frozen
37.8885% threshold. Absent both, per the tie/inconclusive policy: KEEP
OPUS.

## Sample size

```text
initial pairs:       2 (build-feature, build-bugfix)
opus dispatches:     2
sonnet dispatches:   2
total dispatches:    4
```

No automatic extension to a 3rd pair or to n=5 merely because an outcome
is inconvenient. Any extension requires (a) a precommitted rule — the
section-24 sequential-stopping trigger, or the section-22 n=3-to-n=5
count-based extension — **and** (b) remaining approved budget, **and**
(c) material expected information value. The execution prompt stops for
human decision rather than entering open-ended sampling.

## Historical budgets — closed, not reused

```text
evaluation: approved 100, observed >=289.01, BREACHED
recovery:   approved 250, observed 349.94,   BREACHED
```

Preserved unmodified (`eval/records/phase-r/budget-ledger.json`). Not
reused, reset, or enlarged. Phase 3 requires its own new budget, below.

## Proposed Phase-3 Build A/B budget

```text
phase3_build_ab_budget:
    central estimate:     68.97 credits
    conservative ceiling: 158 credits (includes a 1-pair replacement
                          allowance for INVALID_ENVIRONMENT)
    status:               PENDING_HUMAN_APPROVAL
```

### Derivation

**Opus cost/run** — real historical evidence, `build-restoration-gate`
attempts 1-3 (`eval/records/phase-r/build/attempt-{1,2,3}/dispatch/dispatch.json`):
mean 24.699, min 23.194, max 26.192 credits.

**Sonnet cost/run** — no live Sonnet Build history exists. Estimated via
a pricing ratio derived from two directly comparable, same-shape
capability-preflight probes (both single-turn, ~18.1-18.2k tokens, same
provider, same `standard` pricing regime):

```text
Opus:   eval/records/phase-r/preflight/build.json         cost 0.11422875
Sonnet: eval/records/claude-sonnet-5-high.json             cost 0.045259

ratio (sonnet/opus) = 0.3962
estimated Sonnet mean = 24.699 x 0.3962 = 9.786 credits/run
```

**Uncertainty, stated plainly**: this ratio comes from single-turn
trivial calls, not multi-turn agentic Build tasks. If Sonnet needs
materially more turns or retries to solve the same task, its true cost
could exceed this estimate despite a lower per-token rate. The
conservative ceiling therefore assumes **no** Sonnet cost savings —
priced at Opus's own historical maximum, not the ratio-scaled estimate.

```text
central (4 dispatches):    2x24.699 (opus) + 2x9.786 (sonnet)  = 68.97
ceiling (4 dispatches):    4x26.192 (opus max, no savings)     = 104.77
replacement allowance:     1 pair (2 dispatches) at ceiling    = 52.38
total conservative ceiling:                                     157.15
                                                        rounded to 158
```

Internally consistent: the ceiling (158) exceeds the central estimate
(68.97) and the ceiling-without-replacement (104.77), so the proposed
tranche genuinely covers its own stated worst case plus the replacement
allowance — the exact inconsistency flagged and corrected in the prior
Reviewer remediation (see
`docs/evidence/2026-09-04-reviewer-observability-attribution-remediation.md`)
is checked for here and does not recur.

Not self-approved. Distinct from, and does not modify, the historical
100/250 caps or the organizational 7,600-credit/billing-cycle guardrail
(a separate, external control — no evidence in this repository shows it
implicated by this proposal).

## Known non-blocking limitations

- The n=3-to-n=2 interpretive question above is flagged, not resolved.
- Sonnet's cost estimate is a cross-model ratio applied to a single-turn
  probe, not a direct multi-turn measurement — the ceiling compensates by
  assuming zero savings, but the central estimate itself carries real
  uncertainty.
- `build-feature` and `build-bugfix` are newly authored, minimal, mechanical
  fixtures (mirroring `build-restoration-gate`'s pattern) — they are
  simpler than a fully realistic production feature/bugfix task would be.
  This is disclosed, not hidden: they are sufficient to exercise the same
  deterministic oracle/regression/forbidden-scope machinery already
  proven by `build-restoration-gate`, but a real dispatch may reveal
  task-complexity effects this preflight cannot predict from fixture
  content alone.

None of these can change the Opus-vs-Sonnet decision itself (they affect
estimation precision and a documented interpretive gap, not correctness),
so none block this preflight per its own governing rule: *"Can this issue
materially change the decision? If no, record and continue; if yes,
report the exact blocker."*

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
37/37 PASS

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check
(clean)
```

Confirmed:

```text
production routing:        unchanged
user-global routing:       unchanged
v1-restored baseline:      unchanged (routing content; only this new
                            preflight document references it)
live model calls:          0
additional AI credits:     0
Phase 3 experiment:        not executed
Reviewer experiment:       not reopened
```
