# Phase-R Scope Amendment & Closure — 2026-09-04

## What this is, and what it is not

**This is a separation-of-concerns correction.** The original Phase-R
process conflated two different questions into one gate:

- **Restoration**: is the restored V1 routing operationally viable and
  safe enough to replace the unusable/superseded baseline?
- **Optimization**: is each selected model the *best* controller for its
  role, compared against alternatives?

These are answered by different evidence, at different times, for
different reasons. Phase R answers the first. This amendment moves the
second — the Reviewer 5/5 seeded-defect + clean-zero benchmark — to where
it belongs: a targeted, hypothesis-driven Phase-3 evaluation.

**This is not a threshold relaxation.** The Reviewer benchmark's 5/5
threshold, its clean-zero threshold, its fixture, and its scorer are
**unchanged** by this amendment. The benchmark still requires exactly what
it always required. What changes is *which gate it belongs to* — not what
it measures or what counts as passing it. Nothing here recovers,
reinterprets, or reruns the historical Reviewer benchmark results, and
none of the fixture/scorer hardening from the two prior remediations
(`2026-09-04-reviewer-fixture-integrity-remediation.md`,
`2026-09-04-reviewer-observability-attribution-remediation.md`) is
reverted or diminished.

This decision was made by the human operational owner, choosing to
simplify the migration roadmap by separating restoration from
optimization going forward. It responds to that decision, not to the
Reviewer benchmark's block.

## The amended Phase-R restoration gate

Phase R now asks: **is each role's routing operationally integrated,
resolvable, and safe** — not: is each role's *quality* optimal. The
amended hard-gate set:

```text
routing resolution
security / permissions
Breakglass boundary
Build operational restoration
Explore operational gate
Compaction invariant preservation
Reviewer operational integration   <- new gate, replacing the quality benchmark
```

### Reviewer operational integration — the new Phase-R gate

PASS requires repository/runtime evidence establishing all of:

| Property | Evidence | Result |
|---|---|---|
| Model resolves | `github-copilot/gpt-5.6-sol` — `eval/manifests/installed-profile.json`, `eval/records/phase-r/security/reviewer.json`, `eval/records/phase-r/effective-routing.json` (all three agree) | PASS |
| Variant | `high` — same three sources | PASS |
| Routing correct | `eval/records/phase-r/effective-routing.json`: `status: "PASS"`, `mismatches: []`, neutral and project-working-directory resolution agree exactly, `breakglass_task_action: "deny"` present on both | PASS |
| Permissions read-only (repository/filesystem) | `eval/records/phase-r/security/reviewer.json`: `edit: "deny"`, `task: "deny"`, `bash.wildcard: "deny"` with only a read-only git allowlist (`git status*`, `git diff*`, `git log*`, `git show*`). `websearch: "allow"` is unchanged network egress per the bundle's own committed, documented contract (`README.md`'s "Enable web search" section) — not a repository-write capability, and not altered by this amendment | PASS |
| Successful execution through the actual OpenCode path | `eval/records/phase-r/reviewer/*/dispatch/dispatch.json` (e.g. `R-AUTH`): `dispatch_target: "agent:reviewer"` (resolved via the real `--agent reviewer` invocation, not a raw model override), `exit_status: 0`, `classification: "OK"` | PASS |
| Output traversed the evaluation/adapter path | `eval/records/phase-r/reviewer/findings.json`: `scorer: "eval/scoring/reviewer.sh::reviewer_structured_gate"`, all 5 seeded cases normalized from raw dispatch output through the adapter | PASS |
| No permission/Breakglass boundary regression | `eval/records/phase-r/security/{reviewer,expert,breakglass-non-exposure,breakglass-primary}.json` all present, unchanged, and still valid — no code path touched by either Reviewer remediation altered any permission block | PASS |

**All seven properties are established from evidence already in the
repository.** No new model call was made to produce this table — every
citation above resolves to a file that predates this amendment. Phase R's
restoration gate does not require quantitative defect-recall evidence, by
design (that is precisely the property being moved to Phase 3). None of
the conditions that would block this closure apply: Reviewer operational
integration has demonstrably succeeded; the read-only boundary evidence is
valid and unchanged; routing/security evidence is valid and unchanged;
closing Phase R requires no new model call and no production routing
change.

### Gates retained without rerun

Per repository evidence, none of the following show any regression since
their original PASS, and none were touched by anything in this amendment:

```text
routing resolution:  eval/records/phase-r/effective-routing.json,        status PASS
security/permissions: eval/records/phase-r/security/{reviewer,expert}.json, unchanged
Breakglass boundary:  eval/records/phase-r/security/breakglass-{non-exposure,primary}.json, unchanged
Build:                eval/records/phase-r/build/outcome.json,           verdict "pass"
Explore:               eval/records/phase-r/explore/outcome.json,        verdict "pass"
Compaction:            eval/records/phase-r/compaction/outcome.json,     verdict "pass"
```

These are **retained**, not rerun. Rerunning them would spend live credits
to re-prove something no evidence disputes — exactly the kind of
unnecessary spend this amendment is meant to avoid.

## Phase-R outcome

```text
Phase R: PASS
```

`v1-restored-2026-09.jsonc` is now the **canonical restored V1 baseline**
and the **forward reference for hypothesis-driven optimization** — see
[Restored profile status](#restored-profile-status) below. Production
routing is unchanged by this amendment: it was already the restored
routing, active on the real, user-global OpenCode configuration since Task
16 of the original Phase-R execution.

## Reviewer quality benchmark: reclassified, not weakened

```text
reviewer-seeded-defects:
    classification:  Phase-3 targeted Reviewer-quality evaluation
    (was:             Phase-R restoration hard gate)
    threshold:        5/5 seeded defects detected, 0 material/blocking
                       findings on the clean control -- UNCHANGED
    fixture:           unchanged (all fixture-integrity and observability
                       hardening from the two prior remediations retained)
    scorer:            unchanged (all attribution hardening retained)
    historical runs:   remain INADMISSIBLE for quality adjudication --
                       not recovered, not reinterpreted, not reused as
                       Phase-R evidence retroactively
    new live run required to close Phase R: NO
```

**Purpose going forward**: future targeted Reviewer evaluation, model/effort
comparison, or investigation triggered by an observed real-world quality
concern — not a standing requirement to re-clear before any restoration
work can close.

**Known limitations remain documented, not hidden**, and are not claimed
solved:

- R-API's witness attribution can be defeated by a coincidental sub-line
  match (a plausible unrelated finding's natural targeted quote happens to
  overlap the witness) — disclosed and tested in
  `eval/tests/reviewer-witness-attribution-test.sh`.
- R-AUTH and R-CONCURRENCY lack an equally strong deterministic witness
  for their pure-removal mutations; they retain file+severity attribution
  with an explicit, acknowledged residual hallucination risk.

This benchmark does not claim formal proof, perfect attribution, or a
complete defect-detection oracle — it is a bounded, honestly-documented
evaluation tool. That is an acceptable and normal property of an
evaluation harness; it is not, on its own, a reason to keep it as a
restoration gate, and it is not being further hardened in this task.

## Pending Reviewer rerun tranche

```text
reviewer_remediation_rerun_budget:
    previously proposed: 340 credits (6 required dispatches + 1
                          INVALID_ENVIRONMENT allowance, both priced at
                          the historical ceiling)
    previous status:      PENDING_HUMAN_APPROVAL
    new status:            NOT_REQUIRED_FOR_PHASE_R / NOT_AUTHORIZED
```

Not described as technically invalid — the derivation and arithmetic in
`2026-09-04-reviewer-observability-attribution-remediation.md` remain
accurate. It is simply no longer needed to close Phase R, because the
Reviewer quality benchmark it would have re-run is no longer a Phase-R
gate. No live spend is authorized by this amendment. If a future Phase-3
Reviewer evaluation is opened (see
[Phase-3 roadmap](#phase-3-roadmap-hypothesis-driven-only)), its own
budget must be proposed and approved at that time — this withdrawn
proposal is not silently reused.

## Historical budget breach — preserved, not rebased

```text
evaluation:
    approved: 100
    observed: >=289.01
    status:   BREACHED

recovery:
    approved: 250
    observed: 349.94
    status:   BREACHED
```

Unmodified from `eval/records/phase-r/budget-ledger.json`'s
`i1_correction` block. The accounting defect that caused the original
undercounting (`dispatch-fixture.sh` not summing `step_finish` events) was
corrected technically in commit `505d35a`; **historical compliance with
the approved caps remains breached** — that fact is not erased by fixing
the bug that hid it. This is recorded here as a process/evaluation-control
incident, already remediated at the tooling level, not as an open
enterprise-governance question.

**Distinct from, and not conflated with**, the organizational Copilot
guardrail (7,600 credits/billing cycle, externally enforced via GitHub
billing) — no evidence in this repository shows that guardrail itself was
breached, and this amendment does not open a new enterprise-governance
workstream to investigate it.

## Restored profile status

`eval/manifests/installed-profile.json` and
`profiles/v1-restored-2026-09.jsonc` are updated by this amendment to
reflect Phase-R PASS:

```text
phase_r_status:              PASS (was: BLOCKED_REVIEWER_RERUN)
canonical:                   true (was: false)
canonical_quality_reference: true (was: false) -- restoration-quality
                              reference, not a claim of optimal
                              per-role model selection; that is a
                              separate, ongoing Phase-3 concern
operational_state:           active (was: active-provisional)
```

No routing content in either file changes — only status/metadata fields.
Production routing is not touched by this amendment; it was already the
restored routing.

## Phase-3 roadmap (hypothesis-driven only)

**Not executed by this amendment.** Recorded as doctrine only.

**Principle**: optimization experiments are hypothesis-driven, not
exhaustive. A model/role experiment opens only when there is material
expected operational value, an observed real-world weakness, or a
credible cost/latency improvement opportunity. Routing rows are not
proactively benchmarked by default.

**First approved candidate**: Build —
`github-copilot/claude-opus-5 high` vs `github-copilot/claude-sonnet-5
high`. High impact (Build is the primary implementation controller),
deterministic fixture already exists (`build-restoration-gate` and
siblings), and controller quality has direct engineering value. Not
executed by this task.

**Reviewer**: stays at `github-copilot/gpt-5.6-sol` `high`. No immediate
5+1 rerun. Future triggers that would justify opening a new Reviewer
quality evaluation: real-world material misses, real-world material false
positives, frequent human correction of Reviewer findings, unexpected
cost/latency, or a credible superior challenger model. Any of these would
be decided on its own merits, with its own budget proposal, at the time it
arises — not pre-authorized here.

**Other roles** (General, Explore, Scout, Compaction, Title, Summary): not
proactively benchmarked without an explicit optimization hypothesis for
that specific role.

## Durable evaluation doctrine

Three levels, kept distinct going forward:

```text
RESTORATION:
    capability, routing correctness, security, operational smoke/invariants

OPTIMIZATION:
    targeted comparative evaluation, only for material hypotheses

EVALUATION ENGINEERING:
    harness hardening only when required to support an actual pending
    decision
```

**A harness finding does not automatically create a new remediation
workstream.** Before fixing an evaluation limitation, ask whether
resolving it can materially change the decision currently being made. The
two prior Reviewer remediations were justified because they changed
whether the Phase-R restoration gate could be trusted; further hardening
of the same benchmark, now that it is a Phase-3 tool rather than a
restoration gate, is only justified when a real Phase-3 decision depends
on it.
