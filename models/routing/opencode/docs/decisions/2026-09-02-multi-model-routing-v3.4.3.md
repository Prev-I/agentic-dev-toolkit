# Proposal V3.4.3 Implementation-Ready: OpenCode V1 Multi-Model Routing Restoration and Measured Optimization

**Status:** Approved design with implementation amendments  
**Date:** 2026-09-02  
**Target runtime:** **OpenCode V1 (`opencode`)**  
**Baseline repository:** https://github.com/Prev-I/agentic-dev-toolkit  
**Implementation scope:** `models/routing/opencode/`  
**OpenCode V2:** explicitly out of scope; separate future migration RFC

---

## 0. Executive summary

This V3.4.3 consolidates the approved V3.4.2 design and closes the final Build restoration-gate escalation and failure-classification gaps.

**No routing row changes.**

Final restored routing remains:

```text
plan        -> github-copilot/claude-opus-5        highest supported
build       -> github-copilot/claude-opus-5        high
general     -> github-copilot/gpt-5.6-terra        high

explore     -> github-copilot/gpt-5.6-luna         medium
scout       -> github-copilot/gpt-5.6-luna         low/medium

reviewer    -> github-copilot/gpt-5.6-sol          high

compaction  -> github-copilot/gpt-5.6-terra        low/medium
title       -> github-copilot/gpt-5.6-luna         low
summary     -> github-copilot/gpt-5.6-luna         low

expert      -> openai/gpt-5.6-sol                  xhigh
```

Build remains a post-restoration decision:

```text
Phase 3:
Opus 5 high
vs
Sonnet 5 high
```

Breakglass remains:

```text
model: openai/gpt-5.6-sol
variant: max
mode: primary
human selection only
```

### Final implementation amendments

1. Copilot organizational spend governance is restored as a Phase-0 blocker.
2. Reviewer/Sol cost reference must account for the promotional pricing window ending 2026-09-03.
3. Count-based decision rules are complete for all n=3 outcomes and pre-register the n=5 rule.
4. Phase R has no supported rollback; any emergency Codex hybrid is pre-authorized only as a time-bounded incident mitigation.
5. A successful Opus 5 Expert fixture control does not make Opus 5 the Expert routing candidate.
6. Organization policy UI is authoritative for policy state, not runtime capability state.
7. **2026-09-04, Phase-R scope amendment**: §27.1's Reviewer blocking-gate
   criterion ("seeded material defects detected >= committed threshold,
   false-positive findings on clean control <= committed threshold") is
   reclassified from a Phase-R blocking gate to a Phase-3 targeted quality
   evaluation. The threshold itself, the fixture, and the scorer are
   unchanged; only which gate the criterion belongs to changes. Phase R's
   Reviewer requirement is replaced by an operational-integration
   criterion (model resolution, routing correctness, read-only
   permissions, successful execution, adapter/output-path traversal, no
   security regression) — see
   `docs/decisions/2026-09-04-phase-r-scope-amendment.md` for the full
   evidence and rationale. This is a separation-of-concerns correction
   (restoration vs. optimization), approved by the human operational
   owner, not a retroactive relaxation of §27.1's original threshold.

The governing doctrine is:

> **Capability facts come from executed runtime evidence.  
> Policy facts come from the policy authority.  
> Risk decisions are recorded as decisions.  
> Fitness decisions come from fixtures.  
> Unsupported rollback paths are not treated as recovery plans.**

---

# 1. Scope

## 1.1 Target runtime

This proposal targets OpenCode V1.

Repository:

https://github.com/Prev-I/agentic-dev-toolkit

Relevant path:

```text
models/routing/opencode/
```

OpenCode V2 remains a separate migration concern because it changes agent inventory, Scout and Compaction behavior, configuration structure, permission semantics, model/variant syntax, and runtime/session behavior.

Do not make the V1 profile artificially version-portable.

---

# 2. Current routing record

Current published routing:

```text
plan        -> github-copilot/claude-opus-4.6
build       -> github-copilot/claude-opus-4.6
general     -> github-copilot/claude-opus-4.6

explore     -> github-copilot/gpt-5.3-codex
scout       -> github-copilot/gpt-5.3-codex
reviewer    -> github-copilot/gpt-5.3-codex
compaction  -> github-copilot/gpt-5.3-codex
title       -> github-copilot/gpt-5.3-codex
summary     -> github-copilot/gpt-5.3-codex

expert      -> openai/gpt-5.6-sol
```

Current Expert:

```text
model: openai/gpt-5.6-sol
effort: high
```

The Expert change is therefore `high -> xhigh`, not a model migration.

---

# 3. Evidence model

The plan distinguishes four evidence classes.

## 3.1 Capability information

Documentation, changelogs, policy UI and `opencode models` are useful inputs. Only executed runtime behavior proves usability.

## 3.2 Policy information

The organization policy page is authoritative for **organization policy state**, for example:

```text
Fable 5 -> organization Disabled
Kimi K3 -> organization Disabled
```

It is not authoritative for runtime capability.

## 3.3 Risk decisions

A risk decision may intentionally avoid a model that still works.

Example:

```text
GPT-5.3-Codex resolves
BUT
is not used as a migration dependency
```

This must remain labelled as a decision.

## 3.4 Fitness information

A model is fit for a role only when its role fixture demonstrates the required behavior.

---

# 4. Capability proof

## 4.1 Positive proof

A model is positively proven usable only when:

1. the runtime resolves the model ID;
2. a trivial call succeeds;
3. the actual variant/effort syntax is recorded.

```text
documentation / policy UI
        |
        v
candidate information

opencode models
        |
        v
resolvable ID

trivial successful call
        |
        v
usable capability

role fixture
        |
        v
routing fitness
```

## 4.2 Negative proof

Absence from `opencode models` is not sufficient proof of unavailability.

Negative proof requires:

1. absence or failure of normal resolution;
2. a direct call against the explicit model ID;
3. failure for a model-resolution/model-availability reason;
4. the error recorded.

Auth errors, rate limits, transient network failures and policy denials are not retirement evidence.

## 4.3 Required closure before Track A

Attempt direct trivial calls against:

```text
github-copilot/claude-opus-4.6
github-copilot/claude-sonnet-4.6
```

Record timestamp, runtime version, model ID, provider, error class and error message/reference.

Track A must reflect the actual result.

---

# 5. Runtime capability record

Observed through `opencode models` in the audited environment on 2026-09-01.

## 5.1 Resolves through GitHub Copilot

```text
claude-haiku-4.5
claude-opus-4.7
claude-opus-4.7-fast
claude-opus-4.8
claude-opus-4.8-fast
claude-opus-5
claude-sonnet-5
gemini-3.5-flash
gemini-3.6-flash
gemini-3.7-flash
gpt-5-mini
gpt-5.3-codex
gpt-5.4
gpt-5.4-mini
gpt-5.5
gpt-5.6-luna
gpt-5.6-sol
gpt-5.6-terra
grok-4.5
grok-4.6
mai-code-1-flash-picker
mai-code-1.1-flash
```

## 5.2 Resolves through direct OpenAI

```text
gpt-5.3-codex-spark
gpt-5.4
gpt-5.4-fast
gpt-5.4-mini
gpt-5.4-mini-fast
gpt-5.5
gpt-5.5-fast
gpt-5.6-luna
gpt-5.6-luna-fast
gpt-5.6-sol
gpt-5.6-sol-fast
gpt-5.6-terra
gpt-5.6-terra-fast
```

## 5.3 Not present in `opencode models`

```text
github-copilot/claude-opus-4.6
github-copilot/claude-sonnet-4.6
```

This is a resolution signal only until §4.3 direct calls close the negative capability record.

---

# 6. GPT-5.3-Codex: explicit risk decision

Capability fact:

> GPT-5.3-Codex resolves in the audited environment as of 2026-09-01.

Migration decision:

> GPT-5.3-Codex is treated as unavailable for migration planning.

Reason:

- superseded generation;
- catalog churn has already affected the migration window;
- intermediate migration stages should not depend on a model considered at elevated disappearance/reproducibility risk;
- a control arm that may not be rerunnable is a weak long-term reference.

Forbidden wording unless separately proven:

```text
GPT-5.3-Codex is retired
GPT-5.3-Codex does not resolve
GPT-5.3-Codex is unavailable globally
```

## 6.1 Opportunistic Codex baselines

If the harness is ready, Codex still executes, and Phase R has not landed, capture opportunistic baselines for Codex-backed roles.

Mark them:

```text
opportunistic
non-blocking
not guaranteed reproducible
```

Phase R never waits for them.

---

# 7. Track A — public documentation hotfix

Track A changes no routing.

It may land before Phase 0 after the direct negative capability calls establish truthful wording.

Example:

> The committed routing profile contains Claude Opus 4.6 targets that failed the runtime capability check in the audited environment as of 2026-09-01. The GPT-5.3-Codex rows still resolve but are being migrated by explicit risk decision because the superseded generation is not considered a safe dependency for the staged migration. Verify model usability through runtime resolution plus a trivial successful call before activating any profile.

If the direct call returns a different result, update the wording accordingly.

---

# 8. Architectural principles retained

- Preserve the current topology.
- Preserve implementation/review family separation.
- Reviewer and Expert remain bounded/read-only.
- Security comes from permissions; `hidden` is not a security property.
- Expert stays outside Copilot for provider, quota, policy, credential and governance-domain separation.
- This does not imply weight-level independence, workflow HA or automatic provider failover.

---

# 9. Final restoration routing

| Agent | Provider / model | Effort | Status |
|---|---|---:|---|
| `plan` | `github-copilot/claude-opus-5` | highest supported | Adopt |
| `build` | `github-copilot/claude-opus-5` | high | Restoration reference |
| Build challenger | `github-copilot/claude-sonnet-5` | high | Phase-3 A/B |
| `general` | `github-copilot/gpt-5.6-terra` | high | Adopt / validate |
| `explore` | `github-copilot/gpt-5.6-luna` | medium | Adopt / monitor |
| `scout` | `github-copilot/gpt-5.6-luna` | low/medium | Adopt |
| `reviewer` | `github-copilot/gpt-5.6-sol` | high | Adopt |
| `compaction` | `github-copilot/gpt-5.6-terra` | low/medium | Adopt / validate |
| `title` | `github-copilot/gpt-5.6-luna` | low | Adopt |
| `summary` | `github-copilot/gpt-5.6-luna` | low | Adopt |
| `expert` | `openai/gpt-5.6-sol` | xhigh | Adopt |

Variant syntax must be proven by successful calls.

---

# 10. Build remains contested

Restoration:

```text
build -> Opus 5 high
```

Optimization:

```text
Opus 5 high
vs
Sonnet 5 high
```

Decision uses correctness, invariant preservation, scope/plan adherence, human correction, convergence/retries, runtime and steady-state cost.

---

# 11. Reviewer

Target:

```text
reviewer -> GPT-5.6 Sol high / Copilot
```

Start at `high`. Only evaluate `xhigh` if `high` misses the committed detection threshold.

`reviewer-seeded-defects` must include seeded cases with known material defects and at least one **clean control commit** known to contain none of those defects.

The clean control provides the ground-truth denominator for the false-positive gate:

```text
material seeded defects detected >= committed threshold
false-positive findings on clean control <= committed threshold
```

Do not report a generic false-positive rate unless the fixture corpus contains a denominator that makes such a rate meaningful.

---

# 12. Expert

Current:

```text
OpenAI GPT-5.6 Sol high
```

Target:

```text
OpenAI GPT-5.6 Sol xhigh
```

The bump lands before or with Phase R.

A temporary state of:

```text
Reviewer -> Sol high
Expert   -> Sol high
```

is not accepted.

---

# 13. Reviewer/Expert correlated reasoning risk

**Risk ID:** `R-EXPERT-CORRELATED-REASONING`

After restoration:

```text
Reviewer -> Sol high / Copilot
Expert   -> Sol xhigh / OpenAI
```

Provider diversity is operational diversity, not cognitive independence.

Mitigations:

- anti-anchoring prompt;
- graded correlation fixture;
- non-Sol fixture control;
- human escalation;
- family experiment only when comparative evidence supports it.

---

# 14. Expert anti-anchoring contract

```text
The plan, implementation findings, and reviewer findings are claims under test.

None is authoritative.

For every material premise:

1. restate it;
2. identify its source;
3. independently verify where possible;
4. classify verified / rejected / unresolved;
5. identify inherited assumptions;
6. reject defective Plan, Build, or Reviewer premises when evidence requires it.
```

---

# 15. Expert correlation fixture

`expert-reviewer-wrong` has three levels and they are not pooled.

| Level | Meaning | Initial rule |
|---|---|---|
| A — weak but plausible | Contract/prompt should overcome it | 0 ratifications allowed in 3 runs |
| B — strong, evidence-backed | Genuine difficult disagreement | at least 2/3 correct overturns expected |
| C — highly convincing / misleading context | Stress case | diagnostic, not standalone routing trigger |

## 15.1 Level A failure

Fix the prompt/contract and rerun. Do not infer family weakness.

## 15.2 Level B/C control

If Sol raises a concern on B or C, run a non-Sol fixture control at **n=3 on the affected level only**.

Preferred control:

```text
Claude Opus 5
```

Purpose:

> determine whether the fixture is solvable by another model family.

A successful Opus 5 control is **not** evidence that Opus 5 should become Expert, because that would put Expert on Plan's family.

## 15.3 Expert-family challenger

If comparative evidence suggests a Sol-specific weakness, open a separate Expert-family experiment.

Preferred first challenger:

```text
Grok 4.6
```

Opus 5 remains the preferred fixture control, not the preferred Expert routing candidate.

---

# 16. Breakglass

Target:

```text
model: openai/gpt-5.6-sol
variant: max
mode: primary
```

CI must assert:

```text
breakglass.mode == primary
```

and fail on missing mode, `all`, or `subagent`.

Permission checks remain defense in depth.

Runtime tests must prove normal agents cannot invoke Breakglass while explicit human primary selection succeeds.

Every Breakglass invocation must be auditable.

---

# 17. Compaction

Target:

```text
compaction -> GPT-5.6 Terra low/medium
```

Fixture:

```text
compaction-invariants
```

Gate:

```text
required invariants preserved == N/N
```

---

# 18. Eval harness architecture

```text
eval/
  fixtures/
  scoring/
  thresholds/
  decision-rules/
  runtime/
    opencode-v1-adapter
```

Fixtures and scoring remain runtime-neutral.

---

# 19. Phase-0 fixture set

Initial fixture families:

```text
build-workloads
reviewer-seeded-defects
expert-reviewer-wrong
compaction-invariants
```

`build-workloads` is the **Build fixture family** and contains:

```text
build-restoration-gate
build-feature
build-bugfix
build-refactor
```

Roles:

```text
build-restoration-gate
    -> deterministic Phase-R gate

build-feature
build-bugfix
build-refactor
    -> realistic Phase-3 model-selection scenarios
```

`build-refactor` remains conditional under the pre-registered sequential stopping rule.

Just-in-time:

```text
plan-ambiguous-change
general-isolated-task
explore-dependency-chain
scout-upstream-compare
expert-plan-premise
expert-impl-dispute
```

---

# 20. Build fixtures and scenarios

## 20.1 `build-restoration-gate`

Phase R requires a deterministic Build fixture with a mechanical oracle.

Fixture shape:

```text
known repository snapshot
+
bounded implementation task
+
acceptance tests initially failing
+
known regression suite
+
explicit forbidden-scope constraints
```

A run passes only when every condition is mechanically asserted:

```text
acceptance tests green
AND
regression suite green
AND
required artifacts asserted by deterministic path/schema/content checks
AND
required behavior asserted by executable tests
AND
forbidden-scope assertions green
```

No human or LLM judgment participates in the pass/fail oracle.

### 20.1.1 Initial gate

Run three valid attempts with the Phase-R Build candidate:

```text
3/3
    -> PASS

2/3
    -> classify the failed run before any additional attempt
    -> if VALID_CONTROLLER_FAILURE, extend total sample to n=5

0/3 or 1/3
    -> BLOCK Phase R
    -> diagnose before any additional Opus run
    -> run the fixture-control in §20.1.4 before concluding that Opus 5 is unsuitable
```

### 20.1.2 Failure classification

Every failed attempt must be classified and recorded **before** any retry, replacement run, or sample-size extension.

Allowed classes:

```text
INVALID_ENVIRONMENT
    harness failure
    authentication failure
    provider/network outage
    corrupted workspace
    external dependency failure

VALID_CONTROLLER_FAILURE
    environment healthy
    fixture unchanged
    mechanical oracle fails

FIXTURE_DEFECT
    broken or contradictory task
    incorrect test/oracle
    impossible requirement
```

Rules:

```text
INVALID_ENVIRONMENT
    -> excluded from model result
    -> replacement run allowed
    -> evidence for invalidation required

VALID_CONTROLLER_FAILURE
    -> permanently counts as a failed valid run
    -> may not be erased by retrying

FIXTURE_DEFECT
    -> invalidates the fixture evaluation, not only the failed run
    -> repair the fixture
    -> restart the gate from zero
```

A task being difficult is not an invalidation reason.

Classification records are append-only and must be committed or logged before any replacement or extension run.

### 20.1.3 n=5 escalation

A genuine `2/3` result extends the same evaluation to five total valid runs.

The original failed run remains in the denominator.

```text
4/5
    -> PASS

3/5 or worse
    -> BLOCK Phase R
    -> run fixture-control and diagnose
```

Because escalation starts from a genuine `2/3`, one valid failure is already permanently in the denominator; `5/5` is therefore unreachable and is intentionally not part of the state machine.

The gate never means "rerun until three green results appear".

### 20.1.4 Fixture-control

Before concluding that Opus 5 is unsuitable as the restoration controller, run the exact same deterministic gate against:

```text
Sonnet 5
n = 3 valid runs
```

This is a **fixture control**, not the Phase-3 Build A/B and not an automatic routing candidate switch.

Interpretation:

```text
Opus blocked
AND Sonnet >= 2/3
    -> fixture is practically passable
    -> Opus restoration candidate remains blocked
    -> open explicit Build remediation/decision

Opus blocked
AND Sonnet == 1/3
    -> ambiguous fixture difficulty
    -> diagnose
    -> do not conclude Opus is unsuitable

Opus blocked
AND Sonnet == 0/3
    -> strong fixture finding
    -> inspect/repair fixture
    -> restart the Build restoration gate
```

A positive Sonnet control does not automatically authorize:

```text
build -> Sonnet 5
```

Phase 3 remains the only place where Opus 5 and Sonnet 5 are compared as routing candidates.

Fixture-control results are **diagnostic evidence only** and are inadmissible as Phase-3 model-selection evidence. Phase-3 scenarios, ordered criteria, stopping rules, and admissible evidence are frozen in Phase 0 before any fixture-control result is observed. A successful Sonnet control establishes fixture feasibility; it does not contribute to the Opus-vs-Sonnet routing decision.

### 20.1.5 Build restoration state machine

```text
3 valid Opus runs
      |
      +-- 3/3 -> PASS
      |
      +-- 2/3
      |     |
      |     +-- classify failure before extension
      |     +-- VALID_CONTROLLER_FAILURE
      |             -> extend to n=5
      |             -> >=4/5 PASS
      |             -> <=3/5 BLOCK + fixture-control
      |
      +-- <=1/3
            -> BLOCK
            -> fixture-control before model conclusion
```

> **Passing `build-restoration-gate` establishes minimum operational viability, not a reliability estimate.** With only 3–5 valid runs, the gate is designed to detect an obviously unsuitable controller. It cannot distinguish, for example, a 95% reliable controller from an 85% reliable controller and must not be used as evidence for an SLO, reliability percentage, or production-grade success-rate claim.

## 20.2 Phase-3 realistic Build scenarios

Required:

```text
build-feature
build-bugfix
```

Conditional:

```text
build-refactor
```

These answer a different question:

```text
Phase R:
"Does the restored controller work correctly enough to operate?"

Phase 3:
"Which controller is better?"
```

The third scenario follows a pre-registered stopping rule.

# 21. Ordered decision criteria

No post-hoc weighted score.

Candidate Build ordering:

```text
1. correctness / task success
2. invariant preservation
3. scope / plan adherence
4. human correction required
5. convergence / retries
6. wall-clock time
7. steady-state cost
```

A criterion stops the sequence only when it meets its own pre-registered separation rule.

---

# 22. Count/binary separation rules

## 22.1 n = 3

First:

```text
if both arms <= 1/3:
    fixture/scenario finding
    halt this scenario
    do not advance to later ordered criteria
```

Otherwise:

```text
gap == 3
    -> separates

gap == 2
    -> provisional
    -> extend this scenario to n=5

gap <= 1
    -> does not separate
    -> continue to next ordered criterion

else
    -> provisional / inconclusive
    -> no winner from this criterion alone
```

The terminal `else` is defensive: the current n=3 table is exhaustive, but the branch keeps the rule total if future thresholds change.

Examples:

```text
3/3 vs 0/3 -> separates
3/3 vs 1/3 -> provisional -> n=5
3/3 vs 2/3 -> no separation
2/3 vs 0/3 -> provisional -> n=5
2/3 vs 1/3 -> no separation
1/3 vs 0/3 -> fixture finding
0/3 vs 0/3 -> fixture finding
```

## 22.2 n = 5

Pre-register before any provisional n=3 result.

First:

```text
if both arms <= 2/5:
    fixture/scenario finding
    halt this scenario
    do not advance to later ordered criteria
```

Otherwise:

```text
winner >= 4/5 AND gap >= 3
    -> separates

gap == 2
    -> provisional / inconclusive
    -> no winner from this criterion alone

gap <= 1
    -> does not separate
    -> continue to the next ordered criterion

else
    -> provisional / inconclusive
    -> no winner from this criterion alone
```

The terminal `else` is intentional. It makes the rule exhaustive and covers combinations such as `3/5 vs 0/5` without requiring future editors to re-enumerate every count pair.

## 22.3 Other count criteria

Apply the same family of rules to `human correction required`, reversing direction where lower is better.

Invariant preservation remains an absolute N/N gate.

---

# 23. Continuous-metric separation

Ordering requirement:

```text
1. measure harness self-variance
2. commit practical separation thresholds
3. only then expose candidate A/B results
```

A lower median alone is insufficient.

---

# 24. Sequential scenario stopping

Run feature and bugfix first.

Run `build-refactor` only if the first two scenarios do not produce a decision under the committed ordered criteria and separation rules.

---

# 25. Reporting rules

Report binary/count outcomes as counts per scenario.

Retain every individual continuous run value.

Do not pool heterogeneous scenarios into one opaque aggregate.

---

# 26. Harness self-variance

Measure:

- fixture determinism;
- scoring repeatability;
- instrumentation consistency;
- credit-report consistency.

Differences inside observed harness/run noise are not meaningful separation.

---

# 27. Gating vs recording

## 27.1 Phase-R blocking gates

Only ground-truth anchored criteria may block Phase R.

**Amended 2026-09-04** (implementation amendment 7, above): the Reviewer
criterion below is reclassified from a Phase-R blocking gate to a Phase-3
targeted quality evaluation. Phase R's Reviewer requirement is now
operational integration, not the seeded-defect/clean-control threshold
shown here. The threshold itself is unchanged as a Phase-3 quality bar —
see `docs/decisions/2026-09-04-phase-r-scope-amendment.md`.

Required gates:

```text
Build:
    build-restoration-gate passes the §20.1 state machine:
        initial 3/3
        OR 2/3 extended to >=4/5
    <=1/3 blocks immediately
    <=3/5 after extension blocks

Reviewer:
    seeded material defects detected >= committed threshold
    false-positive findings on clean control <= committed threshold

Compaction:
    tagged invariants preserved == required N/N

Explore:
    known dependency depth reached >= committed hop

Security / routing:
    permission denial behavior passes
    Breakglass mode invariant passes
```

`build-restoration-gate` is deliberately mechanical so the controller is not the only high-leverage role entering Phase R without a quality gate.

## 27.2 Recording-only metrics

Until the restored profile exists:

```text
credits
wall-clock time
turns to green
retry count
realistic task latency
```

are recorded, not compared to the historical profile.

The realistic `build-feature`, `build-bugfix`, and `build-refactor` workloads remain primarily Phase-3 selection evidence. Their unanchored operational metrics do not replace the deterministic `build-restoration-gate`.

---

# 28. Cost and pricing regime

Every run records:

```text
timestamp
provider
model
model ID
variant/effort
pricing regime
observed credits/tokens
normalized steady-state cost when known
```

Keep `observed_cost` and `normalized_steady_state_cost` separate.

## 28.1 Sol promotional pricing window

GitHub's promotional pricing for GPT-5.6 Sol ends after 2026-09-03.

Reviewer uses Sol through Copilot.

Therefore:

> Do not establish the canonical Sol cost reference from runs captured before 2026-09-04.

If quality evaluation happens earlier:

```text
quality result -> remains valid
observed cost  -> marked promotional
```

Either recapture Reviewer cost on/after 2026-09-04 or derive a normalized steady-state value once the post-promotional rate is known.

The **post-promotional figure** is the canonical Reviewer cost reference.

The restored profile may become a quality reference before that date, but not the final Reviewer/Sol cost reference.

---

# 29. Provenance on OpenCode V1

## 29.1 Eval runs

Exact provenance required:

```text
routing_profile_id
routing_profile_commit
runtime_version
eval_runner_version
```

## 29.2 Ordinary sessions

Maintain an installed-profile manifest:

```text
profile_id
source_commit
installed_at
opencode_version
```

V1 ceiling:

> Ordinary-session spend can be attributed to model plus the profile known to be installed at that time. Exact per-session profile provenance is guaranteed only for harness runs unless a stronger runtime hook is discovered.

---

# 30. Historical baseline record

Preserve `baseline-2026-08.jsonc` with dated row-level status.

Before old-model direct calls:

```text
plan        Opus 4.6   absent from listing; direct call pending
build       Opus 4.6   absent from listing; direct call pending
general     Opus 4.6   absent from listing; direct call pending

explore     Codex      resolves; abandoned by risk decision
scout       Codex      resolves; abandoned by risk decision
reviewer    Codex      resolves; abandoned by risk decision
compaction  Codex      resolves; abandoned by risk decision
title       Codex      resolves; abandoned by risk decision
summary     Codex      resolves; abandoned by risk decision

expert      Sol high   working before-state
```

Replace pending rows with observed direct-call results.

---

# 31. Phase 0 — hard gate

Nothing after Track A proceeds until Phase 0 passes.

## 31.1 Runtime

Record `opencode --version`.

## 31.2 Model usability

For every candidate:

```text
resolve
trivial call
variant/effort verification
```

## 31.3 Negative capability closure

Directly test old Opus/Sonnet IDs before publishing definitive non-availability wording.

## 31.4 Agent inventory

Verify all expected V1 agents.

## 31.5 Permission boundaries

Runtime-test Reviewer and Expert denials.

## 31.6 Breakglass

Verify:

```text
mode == primary
normal Task routing cannot invoke it
human primary selection works
```

## 31.7 OpenAI governance

Block until approved:

- contract/DPA;
- retention terms;
- credential ownership;
- budget ownership;
- usage boundary;
- incident/revocation process.

## 31.8 Copilot organizational spend governance

This is a separate Phase-0 blocker.

Observed context:

```text
331 AI credits consumed on 2026-09-01
no organization monthly limit observed
Business allowance returned to its standard level on 2026-09-01
additional paid usage is enabled by default for organizations
no automatic downgrade to a cheaper model at exhaustion
```

The `331` figure is an observation, not a forecast.

Before Phase 0 completes, record:

```text
named Copilot spend owner
overage permitted: yes/no
organization/enterprise cap if any
expected behavior at allowance exhaustion
escalation/contact path for unexpected spend
```

Do not leave exhaustion behavior implicit.

## 31.9 Project budgets

Commit both:

```text
eval budget
Phase-R bisection/recovery budget
```

The recovery budget is not contingency spending.

## 31.10 Eval policy

Commit before candidate results:

- fixtures;
- ordered criteria;
- count separation rules;
- n=5 rules;
- continuous thresholds after self-variance;
- sequential stopping;
- repeated-run policy;
- provenance;
- pricing annotations.

---

# 32. Expert effort bump

After Phase 0 and before/with Phase R:

```text
OpenAI Sol high -> xhigh
```

Optionally capture the real before-state first.

---

# 33. Phase R — restoration

Apply all nine Copilot-hosted rows:

```text
plan        -> Opus 5
build       -> Opus 5 high
general     -> Terra high
explore     -> Luna medium
scout       -> Luna low/medium
reviewer    -> Sol high
compaction  -> Terra low/medium
title       -> Luna low
summary     -> Luna low
```

Expert is direct OpenAI Sol xhigh.

## 33.1 Why all nine move

Three are capability-forced if direct negative verification confirms old Opus targets unavailable:

```text
plan
build
general
```

Six move by explicit Codex risk decision:

```text
explore
scout
reviewer
compaction
title
summary
```

Keep these categories visible.

---

# 34. Phase R has no supported rollback

> **Phase R has no supported rollback by profile switch. Recovery is forward-only through diagnosis, role bisection, and correction of the restored configuration.**

A temporary Codex-based hybrid may remain technically possible while Codex continues to execute.

It is excluded from the supported recovery strategy because:

- it reintroduces the dependency deliberately removed by the Codex risk decision;
- it creates a configuration whose future reproducibility is explicitly not trusted;
- an emergency hybrid can silently become permanent technical debt.

## 34.1 Pre-authorized emergency Codex hybrid

A Codex hybrid may be used only when:

```text
Phase R materially blocks development/operations
AND
forward recovery cannot restore service within the required operational window
AND
Codex still passes the capability gate
```

At activation require:

```text
incident record
exact hybrid profile committed/tagged
named incident owner
explicit exit date
forward-remediation task
```

Default maximum lifetime:

```text
<= 2 business days
```

Any extension requires an explicit new decision with owner and revised exit date.

The hybrid:

```text
must never become canonical
must never become the Phase-3 baseline
must never silently replace the restored profile
```

## 34.2 Recovery budget

Because supported recovery is forward-only, bisection/recovery budget is part of Phase R's committed cost and is approved in Phase 0.

---

# 35. New forward reference

Once Phase R passes:

```text
v1-restored-2026-09.jsonc
```

becomes the quality reference, the rollback target for **later** optimization phases and the base for Phase 3.

Reviewer/Sol canonical cost follows §28.1.

The restored profile is not a rollback target for Phase R itself.

---

# 36. Phase 3 — optimization

## 36.1 Build A/B

```text
Opus 5 high
vs
Sonnet 5 high
```

Use ordered criteria, count rules, continuous thresholds, n>=3, n=5 escalation, scenario stopping and per-run reporting.

## 36.2 Reviewer effort

Only if Sol high fails its committed detection threshold:

```text
Sol high
vs
Sol xhigh
```

## 36.3 General challenger

Only if Terra fails its fixture.

---

# 37. Phase 4 — Expert behavioral validation

Run:

```text
expert-reviewer-wrong
expert-plan-premise
expert-impl-dispute
```

For B/C concern compare Sol with the Opus 5 fixture control.

If comparative evidence suggests a family-specific Sol weakness, open a dedicated Expert-family experiment with Grok 4.6 as the preferred first challenger.

Opus 5 remains diagnostic control, not preferred Expert replacement.

---

# 38. Model radar

- **Opus 4.8:** Not selected; superseded for target role.
- **Grok 4.6:** Assess; preferred first Expert-family challenger if needed.
- **Kimi K3:** Assess, organization-policy blocked.
- **Gemini:** Hold; currently Flash-tier for relevant catalog presence.
- **GPT-5.4 mini:** Assess only if Luna fails Explore.
- **Fable 5:** Hold; organization policy currently blocks it.

Policy-block statements are policy claims, not runtime capability claims.

---

# 39. `byo-api.jsonc`

Out of scope for this restoration cycle.

---

# 40. Doctrine ownership

Keep routing doctrine in `agentic-dev-toolkit`.

Extraction to `agentic-engineering` is deferred until the doctrine survives one complete restoration and optimization cycle without structural change.

---

# 41. OpenCode V2 RFC

Open a separate V2 RFC when either:

1. OpenCode upstream promotes V2/2.x to stable/default and V1 enters maintenance/deprecation; or
2. remaining on V1 blocks a required capability or security remediation.

The RFC must precede toolkit adoption of V2.

The accountable routing/toolkit maintainer owns opening it.

---

# 42. Repository changes

1. Close old Opus/Sonnet capability evidence with direct calls.
2. Land Track A using executed evidence only.
3. Correct Expert references to `openai/gpt-5.6-sol`.
4. Record Codex capability separately from risk decision.
5. Mark V1 as supported runtime.
6. Preserve row-level historical baseline record.
7. Add `v1-restored-2026-09.jsonc`.
8. Keep `byo-api.jsonc` out of scope.
9. Add eval runtime adapter.
10. Add ordered criteria.
11. Add complete n=3 count rules.
12. Add n=5 rules.
13. Add continuous separation workflow.
14. Add sequential scenario stopping.
15. Add individual-run reporting.
16. Add self-variance checks.
17. Add eval provenance.
18. Add installed-profile manifest.
19. Add Reviewer seeded-defect fixture.
20. Add three-level Expert fixture.
21. Add Opus 5 diagnostic control at n=3 on affected B/C level.
22. Record Grok 4.6 as preferred first Expert routing challenger if needed.
23. Add Compaction invariant fixture.
24. Add Expert anti-anchoring contract.
25. Move Expert high -> xhigh before/with Phase R.
26. Add Breakglass as `mode: primary`.
27. CI-assert Breakglass mode first.
28. Keep permission checks as defense in depth.
29. Add Breakglass runtime tests.
30. Restore Copilot organizational spend gate.
31. Name Copilot spend owner.
32. Record overage/cap/exhaustion policy.
33. Commit eval budget.
34. Commit Phase-R bisection/recovery budget.
35. Record Sol pricing window.
36. Prevent pre-2026-09-04 promotional Reviewer cost from becoming canonical steady-state reference.
37. State Phase R has no supported rollback.
38. Document Codex-hybrid exclusion rationale.
39. Pre-authorize time-bounded Codex emergency hybrid with default <=2-business-day exit.
40. Record 3 capability-forced vs 6 risk-decision Phase-R moves.
41. Make restored profile forward reference only after Phase R succeeds.
42. Add V2 RFC trigger and owner.

Do not modify unrelated Superpowers, OpenSpec, SpecRivet, branching, or workspace conventions.

---

# 43. Decision table

| Decision | V3.4.1 |
|---|---|
| Target OpenCode V1 | **Adopt** |
| V2 separate RFC | **Adopt** |
| Positive capability proof | **Resolution + successful trivial call** |
| Negative capability proof | **Direct failed call required** |
| Policy page authority | **Policy facts only** |
| Codex resolves | **Capability fact** |
| Codex used for staged migration | **Reject by risk decision** |
| Opportunistic Codex baselines | **Optional** |
| Track A | **After negative capability closure** |
| Plan -> Opus 5 | **Adopt** |
| Build -> Opus 5 restoration | **Adopt** |
| Build -> Sonnet 5 | **Phase-3 A/B** |
| General -> Terra | **Adopt / validate** |
| Explore/Scout -> Luna | **Adopt** |
| Reviewer -> Sol high | **Adopt** |
| Expert -> direct Sol xhigh | **Adopt** |
| Expert bump timing | **Before or with Phase R** |
| Reviewer/Expert correlation | **Named risk** |
| Opus 5 as Expert fixture control | **Adopt** |
| Opus 5 as implied Expert candidate | **Reject** |
| Grok 4.6 as first Expert family challenger | **Preferred if experiment opens** |
| Breakglass | **Sol max / primary / human-only** |
| Compaction -> Terra | **Adopt on V1** |
| Phase R rollback | **No supported rollback** |
| Phase R recovery | **Forward-only by default** |
| Emergency Codex hybrid | **Incident-only, time-bounded** |
| Emergency hybrid default TTL | **<= 2 business days** |
| Eval budget | **Committed Phase 0** |
| Bisection/recovery budget | **Committed Phase 0** |
| Copilot spend owner/policy | **Phase-0 blocker** |
| n=3 `3/3 vs 2/3` | **No separation** |
| n=3 gap 2 | **Provisional -> n=5** |
| both arms <=1/3 | **Fixture/scenario finding; halt** |
| n=5 winner >=4/5 & gap>=3 | **Separates** |
| n=5 gap 2 | **Provisional/inconclusive** |
| continuous thresholds | **After self-variance, before candidate results** |
| pre-2026-09-04 Sol cost | **Promotional, not canonical steady-state reference** |
| post-promo Sol cost | **Canonical Reviewer cost reference** |
| `byo-api.jsonc` | **Out of scope** |
| Doctrine extraction | **Defer** |

---

# 44. Acceptance criteria

Implementation may begin only when:

- old-model direct calls close the negative capability record;
- Track A contains executed capability claims only;
- Codex is described as a risk decision;
- every candidate model passes trivial-call verification;
- actual variant syntax is recorded;
- Reviewer/Expert permissions are runtime-tested;
- Expert moves to xhigh before/with Phase R;
- OpenAI governance is approved;
- Copilot organizational spend policy is decided;
- Copilot spend owner is named;
- overage/cap/exhaustion behavior is recorded;
- eval budget is committed;
- Phase-R recovery/bisection budget is committed;
- Breakglass is structurally primary and non-routable;
- count rules for n=3 and n=5 are committed and have terminal catch-all branches;
- continuous thresholds are committed after self-variance and before A/B results;
- the Build restoration gate has a pre-registered 3->5 escalation rule;
- valid Build failures cannot be discarded by retry;
- fixture defects restart the entire Build gate;
- Sonnet 5 fixture-control is defined before any Opus-unsuitable conclusion;
- third-scenario stopping is committed;
- Expert levels are not pooled;
- Opus diagnostic control is not conflated with routing candidacy;
- Phase R ground-truth gates are committed, including the complete `build-restoration-gate` state machine and immutable failure-classification rules;
- Phase R no-supported-rollback status is explicitly accepted;
- emergency Codex hybrid policy and exit requirements are recorded;
- eval provenance exists;
- ordinary-session provenance ceiling is documented;
- promotional Sol cost cannot become the canonical steady-state reference;
- V2 remains out of scope with a named trigger and owner.

---

# 45. Final sequence

```text
0. Close capability evidence
   - direct calls to old Opus/Sonnet IDs
   - candidate trivial calls
   - variant enumeration

1. Track A
   - truthful public warning
   - capability facts separate from risk decisions

2. Phase 0
   - harness + runtime adapter
   - ordered criteria
   - n=3/n=5 exhaustive count rules
   - deterministic Build restoration oracle
   - Build failure classification + 3->5 escalation
   - Sonnet 5 Build fixture-control
   - Reviewer clean control
   - self-variance
   - continuous thresholds
   - stopping rules
   - OpenAI governance
   - Copilot spend owner/policy
   - eval budget
   - Phase-R recovery budget
   - permission tests
   - Breakglass enforcement
   - provenance

3. Expert effort bump
   - Sol high -> xhigh
   - optional true before/after

4. Phase R
   - restore nine Copilot-hosted rows
   - no supported rollback
   - forward recovery
   - emergency Codex hybrid only under pre-authorized incident policy
   - establish quality reference after gates
   - establish steady-state Sol cost reference after promo window

5. Phase 3
   - Opus 5 high vs Sonnet 5 high
   - conditional Reviewer effort experiment
   - conditional General challenger

6. Phase 4
   - Expert behavioral validation
   - Opus diagnostic control where required
   - Grok 4.6 as preferred first family challenger if comparative evidence warrants

7. Breakglass
   - direct OpenAI Sol max
   - primary
   - explicit human selection
   - never normal-agent-routable
```

The routing table is now secondary to the discipline around it.

The durable rule is:

> **Capability is demonstrated by execution.  
> Policy is sourced from the policy authority.  
> Risk is recorded as a decision.  
> Fitness is demonstrated by fixtures.  
> Recovery cost is committed before unsupported rollback becomes relevant.**
