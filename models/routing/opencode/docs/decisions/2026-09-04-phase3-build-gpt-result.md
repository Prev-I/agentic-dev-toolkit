# Phase-3 Build Opus-vs-Sol Result — 2026-09-04

Executes the experiment frozen and approved by
`docs/decisions/2026-09-04-phase3-build-gpt-preflight.md` (PR #16, 264-credit
approved cap). Machine-readable form:
`eval/records/phase3-build-gpt/adjudication.json`. Raw provenance:
`eval/records/phase3-build-gpt/{build-feature,build-bugfix}/pair*/`.

## Configuration (unchanged from the frozen preflight)

```text
incumbent:  github-copilot/claude-opus-5,   variant high
challenger: github-copilot/gpt-5.6-sol,     variant high
budget:     264 credits, APPROVED
workloads:  build-feature (pair 1), build-bugfix (pair 2)
order:      feature: opus -> sol
            bugfix:  sol -> opus
```

## Execution

All 4 planned dispatches completed with a healthy, valid `OK` classification
on the first attempt. No `INVALID_ENVIRONMENT`, no replacement pairs, no
`FIXTURE_DEFECT`.

```text
Pair 1 / build-feature
  Opus: OK, oracle PASS, regression PASS, wall-clock 51838 ms, 29.51590 credits
  Sol:  OK, oracle FAIL, regression PASS, wall-clock 40976 ms, 16.18650 credits
        -> VALID_CONTROLLER_FAILURE (see below), retained as evidence

Pair 2 / build-bugfix
  Sol:  OK, oracle PASS, regression PASS, wall-clock 63987 ms, 20.45420 credits
  Opus: OK, oracle PASS, regression PASS, wall-clock 44779 ms, 27.88140 credits
```

Budget consumed: **94.038 / 264 credits** (169.962 remaining, unused — no
replacement was needed).

### Sol's build-feature attempt: a genuine, valid failure, not a harness defect

Sol's dispatch was healthy (`exit_status: 0`, `classification: OK`) — this
was not an environment or harness failure. Its response:

> Using `brainstorming` to confirm the smallest correct design before
> implementation... Design: add only `reverse()` to `lib/strings.sh`...
> **Approve this design so I can implement it.**

Sol invoked a design-confirmation skill and stopped, waiting for human
approval that a non-interactive, single-shot `opencode run` dispatch cannot
provide. It never wrote `reverse()`. The regression suite still passed
(`upper()` was never touched, since no file was edited at all), but the
acceptance oracle correctly failed (`declare -F reverse` found nothing).

Classified `VALID_CONTROLLER_FAILURE` per the frozen taxonomy — a genuine
attempt, not an environment fault — and retained as permanent evidence, not
replaced, per the frozen invalid-attempt policy.

## Functional adjudication (criteria 1-5)

```text
1. correctness/task success: Sol REGRESSED on build-feature (oracle FAIL);
                              tied on build-bugfix (both oracle PASS)
```

**Result: functional regression by Sol.** Per the frozen final adoption
rule's `functional_regression` branch:

> If Sol is worse than Opus on any earlier-priority functional criterion
> (1-5) on either workload: KEEP_OPUS. Operational advantages cannot
> compensate. Adjudication stops here.

Criteria 2-7 (invariant preservation, scope adherence, human correction,
convergence, wall-clock, cost) are **not evaluated as decision inputs** — the
regression on criterion 1 is dispositive. They are recorded below for
completeness and observational value only, exactly as the frozen rule
permits ("operational criteria may be reported but are not needed to rescue
the decision" — here, there is nothing to rescue, since Opus already wins on
the earliest criterion).

## Wall-clock and cost (observational only — not used for the decision)

```text
build-feature: opus 51838 ms / 29.51590 credits, sol 40976 ms / 16.18650 credits
build-bugfix:  sol 63987 ms / 20.45420 credits, opus 44779 ms / 27.88140 credits

Sol total credits: 36.64070   Opus total credits: 57.39730
```

Sol was faster and cheaper on both workloads where it actually completed the
task, and did not complete build-feature at all. None of this is used for
the decision: a functional regression on the earliest criterion is
dispositive regardless of any operational figures.

## Final decision

```text
FINAL DECISION: KEEP_OPUS
```

Sol regressed on criterion 1 (correctness/task success) on `build-feature` —
a genuine, valid dispatch that did not complete the task. Per the frozen
adoption rule, this alone determines the outcome.

## Activation policy applied

`gpt_loses_ties_or_inconclusive` branch: **KEEP_OPUS**. Production routing
remains unchanged (`Build: github-copilot/claude-opus-5 high`,
`Reviewer: github-copilot/gpt-5.6-sol high`). This Build/Sol optimization
line may stop unless a new material hypothesis exists — there is no pending
`Reviewer` inversion question to carry forward, since Sol did not win.

## Routing impact

None. Production routing was never modified during measurement: all 4
dispatches used direct `--model`/`--variant` overrides against fresh,
isolated, per-arm sandboxes, never the routed `build` agent identity or the
user-global active profile. `v1-restored-2026-09.jsonc` is unchanged.

## A harness bug found and fixed during execution (disclosed, not hidden)

`eval/runtime/opencode-v1-adapter/run-phase3-build-fixture.sh` hardcoded its
ledger account name to `phase3_build_ab` (a copy-paste artifact from the
Opus-vs-Sonnet runner) instead of accepting it as a parameter. This meant
the first dispatch's cost landed under the wrong account key in a ledger
whose `caps` only defined `phase3_build_gpt`, so any query of the *correct*
account (`ledger_spent`/`ledger_admit` against `phase3_build_gpt`) would
have under-reported spend by 29.5159 credits until the entry was relabelled.
**Correction, per independent review**: `dispatch_fixture` (the actual
dispatch code path) never calls `ledger_admit` at all — it only calls
`ledger_append` after the fact. No live admission check was running to be
defeated; the 264-credit cap is reconciled after each dispatch, not
enforced before it, and this was already true before this bug and remains
true after the fix. The bug's real effect was narrower than an earlier
draft of this section claimed (it neither ran nor "defeated" a check): it
mislabelled one ledger entry's account field, nothing more. Found
immediately after the first dispatch: the script was fixed to accept
`--account` as an explicit parameter, and the one affected ledger entry's
`account` field was corrected (the credits value itself was always correct
— `derived_credits` comes straight from `dispatch-fixture.sh`, untouched by
this bug). No path existed for this bug to enable unmeasured spend: only 4
dispatches were ever made, each is independently reconstructible from its
own `raw.jsonl`, and the total (94.038) is far under the 264-credit cap
regardless. Wiring `ledger_admit` into `dispatch_fixture` as a genuine
pre-spend check remains a real, disclosed gap for a future experiment to
close — not fixed here, since it doesn't change this outcome.

## Known non-blocking limitations (per independent review)

- **Sandboxes were created inside the git worktree**, so both models' `git
  log`/`git status` calls (run only as harmless exploration, never as part
  of completing the task) walked upward and saw this repository's real
  history and working-tree state, including this experiment's own name and
  in-flight commits. Confirmed via `raw.jsonl`: this did not affect the
  outcome (Sol's build-feature failure was already determined at its first
  tool call, loading a design-confirmation skill, before any git command
  ran; it passed build-bugfix regardless). This is a real evidence-blinding
  risk for a *future* experiment where a model's behavior could plausibly
  depend on seeing the experiment's own framing, and is disclosed rather
  than fixed here: closing it requires changing the shared sandbox-creation
  mechanism (`mktemp -d` outside any repository, or a `GIT_CEILING_DIRECTORIES`
  guard), which is harness-hardening work beyond what this specific
  decision required.
- **The installed skill set/version is not recorded in `dispatch.json`.**
  The `brainstorming` skill Sol invoked comes from a machine-global plugin
  cache (`superpowers`), available identically to both arms (not a sandbox
  artifact), but a rerun on a machine with a different superpowers version
  could in principle behave differently with identical recorded provenance.
- **The 4 dispatch invocations are not captured as a single reproducible
  driver script**, and the `--timeout 480` actually used is committed
  nowhere in the frozen preflight (the runner's own default is 1800s). It
  applied symmetrically and no dispatch came within 400s of it, so it is
  harmless here, but the run cannot be replayed from the repository alone.

None of these affect the KEEP_OPUS decision or the `VALID_CONTROLLER_FAILURE`
classification, both independently re-derived and confirmed correct under
every alternative reading tried.

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
41/41 PASS

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check
(clean)
```

Confirmed:

```text
other routing rows:        unchanged (Build only, no other role touched)
Reviewer experiment:       not executed
GPT/other-model experiment: not executed
Phase 4:                   not started
live model calls:          4 (2 opus, 2 sol) -- exactly the frozen initial sample
additional AI credits:     94.038 (within the 264-credit approved cap)
```
