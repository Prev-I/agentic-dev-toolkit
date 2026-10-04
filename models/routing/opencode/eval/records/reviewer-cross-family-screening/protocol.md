# Reviewer Cross-Family Quality Screening

## Freeze Status

- Experiment: `reviewer-cross-family-quality-screening-20261003`
- `status_at_freeze: AWAITING_APPROVAL`
- Runtime at freeze: OpenCode `1.18.32`
- Production routing: unchanged before, during, and after this protocol unless a
  later user decision explicitly changes it.
- Dispatch is forbidden until the user explicitly approves the frozen ceiling
  and a separate `approval.json` records the experiment id, status
  `APPROVED_FOR_DISPATCH`, and exact ceiling `805`. The frozen protocol and
  manifest are not edited after approval.
- The freeze is deliberately uncommitted because this task forbids commits.
  Approval binds the manifest digest, not a Git commit. Dispatch provenance will
  therefore report the surrounding HEAD, which does not contain these new
  untracked files; this is a known provenance limitation.

This protocol asks whether either GPT-family challenger is a credible candidate
for a future quality-oriented Reviewer profile:

| Arm | Model | Variant | Provider |
|---|---|---|---|
| Astra challenger | `github-copilot/gpt-6-astra` | `xhigh` | GitHub Copilot |
| Sol challenger | `github-copilot/gpt-6.1-sol` | `high` | GitHub Copilot |

Both use Copilot in accordance with the normal-work quota boundary in the bundle
README. Neither direct OpenAI nor the production Reviewer agent is used.

## Historical Reference

The Opus 5.5 high result in
`eval/records/opus55-reviewer-screening/adjudication.json` is the fixed reference
and is not rerun:

- gate: `BLOCK`;
- three seeded defects detected;
- one missed;
- one ambiguous;
- zero clean material findings.

The reference ran on OpenCode `1.18.31`; this freeze targets `1.18.32`. The
runtime difference is an explicit limitation, so comparisons to the reference
are historical rather than contemporaneous. The historical run also used
Superpowers `6.3.0`, dispatch runner `phase-r-dispatch-v1`, and an earlier
routing/instruction context. This freeze uses `phase-r-dispatch-v2` and an
isolated minimal config with no Superpowers plugin, model-routing instruction,
global references or external skills. That context difference is held equal
between challengers but differs from the historical reference.

## Frozen Workload

- Use the unchanged production Reviewer prompt copied to
  `config/reviewer-prompt.md`.
- Use the unchanged `reviewer-seeded-defects` fixture: five seeded cases and one
  clean control.
- Run `fixture_integrity_check` before any probe or workload dispatch.
- Keep the unchanged JSON request adapter, witness attribution and deterministic
  scorer in `eval/scoring/reviewer.sh`.
- Required threshold: all five seeded defects independently detected and zero
  material/blocking findings on clean.
- Use one attempt per challenger per case. No retry, replacement case, extra
  workload or post-hoc prompt change.
- Reject a call if the raw stream contains `Falling back to default agent`.
- Reject the experiment on fixture-integrity failure, provider/environment
  failure, empty or unparseable response, unknown cost, failed ledger admission,
  in-flight budget stop, or incomplete arm. A budget stop is
  `INVALID_OR_INCOMPLETE`, never a model-quality failure.
- Use isolated primary-mode experiment agents because the runtime cannot execute
  the Reviewer subagent directly. Their prompt, temperature and permissions are
  identical; only model and variant differ. The global configuration is not
  modified.
- Create every workload in a fresh neutral external directory with no Git
  history. Disable project config discovery and deny external-directory tools.
  Reject a run whose event stream shows the repository path; this is defense in
  depth, not a claim of an OS security sandbox.
- The earlier layout exposed case ids in paths and kept answer-key files in the
  same repository. This freeze removes case ids from workspace paths and denies
  external-directory access, but provider/model training exposure and prompt
  inference cannot be excluded.

The frozen alternating order is:

```text
clean          Astra / Sol
R-API          Sol / Astra
R-AUTH         Astra / Sol
R-BOUNDARY     Sol / Astra
R-CONCURRENCY  Astra / Sol
R-ERROR        Sol / Astra
```

## Budget Contract

Credits are runtime-reported USD multiplied by 100 and are not reconciled with
provider billing. The current catalog prices per million tokens are:

| Model | Input USD | Output USD | Cache read USD | Cache write USD |
|---|---:|---:|---:|---:|
| Opus 5.5 reference | 4 | 20 | 0.2 | 0 |
| GPT-6 Astra | 10 | 50 | 1 | 0 |
| GPT-6.1 Sol | 2 | 10 | 0.1 | 0 |

The historical Opus 5.5 Reviewer corpus spent `118.53332` workload credits.
Simple output-price ratios give descriptive lower-detail projections of
`296.33330` for Astra (`118.53332 * 50/20`) and `59.26666` for Sol
(`118.53332 * 10/20`). They are not token-normalized estimates: the historical
corpus was cache-heavy, Astra cache reads are priced at five times Opus 5.5, and
Sol cache reads at half. These projections do not authorize a call.

The historical Opus record listed a nonzero cache-write price, while the current
catalog reports zero for all three models. This freeze uses the current catalog
and records the catalog/runtime difference rather than retroactively repricing
the historical ledger.

Admission is deliberately more conservative:

- Astra probe: 50 credits; six workloads at 100 each; arm stop threshold 650.
- Sol probe: 10 credits; six workloads at 20 each; arm stop threshold 130.
- Admission total: `50 + 6*100 + 10 + 6*20 = 780`.
- Reporting-lag reserve from the paired PATH precedent: `23.341875`.
- Protected total: `803.341875`; proposed ceiling: **805 credits**.

Before every probe and workload, call `ledger_admit` with the frozen projection.
Before dispatch, use `ledger_spent` to set the in-flight wrapper threshold to the
arm's remaining allowance. After every call, record known cost even when the call
fails, and stop on unknown cost. Reserve `15` credits of reporting lag for Astra
and `8.341875` for Sol. Completed-step monitoring is not a provider-side hard
cap, and in-flight reporting lag remains. A stopped call may incur one final
unreported step plus polling delay. Treat spend after a budget stop as a lower
bound and dispatch no further call.

## Preregistered Outcomes

1. `NO_CHALLENGER_PASSES_THRESHOLD`: neither challenger clears 5/5 plus
   clean-zero. No quality-profile routing decision is unlocked.
2. `ASTRA_PASSES_THRESHOLD`: Astra becomes a credible candidate for a later
   user decision to route Reviewer to Copilot Astra `xhigh`; no automatic
   promotion.
3. `SOL61_PASSES_THRESHOLD`: Sol becomes a credible candidate for a later user
   decision to route Reviewer to Copilot GPT-6.1 Sol `high`; no automatic
   promotion.
4. `BOTH_PASS_THRESHOLD`: both are credible candidates; quality and clean-zero
   decide first, then efficiency may inform a later user choice.
5. `CREDIBLE_CANDIDATE_BELOW_THRESHOLD`: a challenger detects more than the
   historical three cases, has no more than one ambiguous case, preserves
   clean-zero, and remains below 5/5. It is credible for broader testing, not
   promotion. This label is evaluated independently per arm and can coexist with
   another arm's threshold result.
6. `INVALID_OR_INCOMPLETE`: no routing conclusion.

Efficiency never overrides a quality block. The preregistered outcome where
neither challenger passes is expected and valid, not a protocol failure.

## Retained Evidence After A Future Approved Run

Retain raw streams, responses, parsed findings, normalized findings, scorer
attribution, resolved agent configs, tokens, timing, credits, ledger entries and
an adjudication. Do not rewrite this pre-dispatch freeze manifest.
