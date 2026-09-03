# OpenCode V1 Routing Phase 0 Evidence Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining Phase-0 evidence gate that current provider availability permits, while preserving explicit blockers and stopping before Phase R.

**Architecture:** Extend the existing dependency-free Bash/JSON harness with a machine-readable budget decision, runtime-resolved Breakglass non-exposure evidence, a bounded three-run Luna-low self-variance executor, measured threshold derivation, and a final readiness matrix. Cost-bearing commands remain explicit and occur only after budget validation; prior failed evidence remains immutable and candidate A/B workloads are never invoked.

**Tech Stack:** Bash, Python standard library for JSON, OpenCode V1 CLI `1.18.26`, existing Phase-0 harness.

**Spec:** `docs/superpowers/specs/2026-09-03-opencode-routing-phase-0-closure-design.md`

## Global Constraints

- Do not modify `models/routing/opencode/opencode.jsonc`.
- Do not modify production `models/routing/opencode/.opencode/agents/*` definitions.
- Do not restore or activate production routing, change Expert production effort, or execute Phase R, Phase 3, or Phase 4.
- Do not expose or execute candidate A/B workloads.
- Approved `eval_budget_credits` is exactly `100`; approved `phase_r_recovery_budget_credits` is exactly `250` and may not fund evaluation.
- The organizational user guardrail is `7600` Copilot credits per billing cycle; enforcement is external to OpenCode.
- Preserve the existing failed Breakglass record; append a new attempt instead of overwriting it.
- Perform at most one new direct OpenAI Breakglass execution attempt in this closure.
- Preserve every self-variance run, including environment-invalid runs; never discard a valid inconvenient result.
- Continuous thresholds must be derived and committed only after persisted self-variance evidence and before any future candidate results.
- Every shell script uses `set -Eeuo pipefail` and `IFS=$'\n\t'` and is executable.
- Runtime-neutral fixtures and scoring do not invoke OpenCode.

---

### Task 1: Commit Numeric Budget Governance

**Files:**
- Create: `models/routing/opencode/eval/manifests/phase-0-budgets.json`
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/validate-budget.sh`
- Create: `models/routing/opencode/eval/tests/budget-test.sh`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-governance-blockers.md`

**Interfaces:**
- Consumes: Human approval in the task conversation on 2026-09-03.
- Produces: `validate_phase0_budget FILE`, returning zero only for the approved, separated allocations and external guardrail metadata.

- [ ] **Step 1: Write the failing budget validation test**

Create `budget-test.sh` that sources the wished-for validator, validates the committed manifest, then mutates each load-bearing field independently. Use temporary JSON records to assert rejection when the eval budget is not `100`, recovery budget is not `250`, `recovery_budget_reclaimable_for_eval` is not `false`, OpenCode-native enforcement is claimed, or approval reference is absent.

The committed manifest shape asserted by the test is:

```json
{
  "decision_date": "2026-09-03",
  "eval_budget_credits": 100,
  "phase_r_recovery_budget_credits": 250,
  "recovery_budget_reclaimable_for_eval": false,
  "approval_reference": "human operational owner approval in Phase-0 closure task conversation, 2026-09-03",
  "copilot_business_standard_allowance_credits": 1900,
  "organizational_user_guardrail_multiplier": 4,
  "organizational_user_guardrail_credits": 7600,
  "paid_usage": "allowed",
  "enforcement": "github_billing_organizational_control",
  "opencode_native_enforcement": "none",
  "at_guardrail": "stop_and_escalate_no_automatic_fallback",
  "historical_usage_observation": {"credits": 331, "date": "2026-09-01"},
  "current_remaining_headroom_credits": null
}
```

- [ ] **Step 2: Run the budget test and verify RED**

Run: `bash models/routing/opencode/eval/tests/budget-test.sh`

Expected: FAIL because `validate-budget.sh` and the budget manifest do not exist.

- [ ] **Step 3: Implement the manifest and strict validator**

Implement `validate_phase0_budget()` with Python standard-library JSON parsing. Require the exact numeric decisions, non-reclaimability, approval reference, `1900 * 4 == 7600`, external enforcement, no native enforcement, and null current headroom. Do not add runtime spending-cap behavior.

- [ ] **Step 4: Update governance evidence**

Add a project-budget section that records the two approvals and explicitly preserves the already-resolved operational owner, V2 RFC owner, Copilot/OpenAI spend owners, IT credential authority, R&D authorization, external enterprise controls, and Copilot guardrail behavior. State that enterprise DPA, retention, contracts, and enterprise-wide AI governance are not project deliverables or reopened blockers.

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```bash
bash models/routing/opencode/eval/tests/budget-test.sh
bash models/routing/opencode/eval/run-tests.sh
```

Expected: all tests PASS.

- [ ] **Step 6: Commit the budget decision**

```bash
git add models/routing/opencode/eval/manifests/phase-0-budgets.json \
  models/routing/opencode/eval/runtime/opencode-v1-adapter/validate-budget.sh \
  models/routing/opencode/eval/tests/budget-test.sh \
  models/routing/opencode/docs/evidence/2026-09-02-governance-blockers.md
git commit -m "chore(opencode): record Phase 0 budgets"
```

---

### Task 2: Correct Breakglass Non-Exposure Evidence

**Files:**
- Modify: `models/routing/opencode/eval/runtime/opencode-v1-adapter/probe-breakglass.sh`
- Modify: `models/routing/opencode/eval/tests/breakglass-runtime-test.sh`
- Create: `models/routing/opencode/eval/records/breakglass-normal-agent-non-exposure.json`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-phase-0-security-boundary.md`

**Interfaces:**
- Consumes: `phase-0-security-profile.json` and `opencode debug agent NAME` JSON.
- Produces: `capture_breakglass_non_exposure PROFILE OUTPUT`, a non-cost-bearing runtime-resolved evidence record; keeps `probe_breakglass_primary PROFILE OUTPUT` separate for positive execution.

- [ ] **Step 1: Write failing non-exposure tests**

Refactor the test fake so `opencode debug agent phase0-normal` returns an ordered permission array. Assert PASS only when the last matching Task rule for `breakglass` is deny and resolved Breakglass is exactly primary/OpenAI Sol/max. Assert failure for reversed rule order, absent deny, `ask`, Breakglass subagent/all mode, wrong model, and prompt-only refusal text.

Expected record fields:

```json
{
  "evidence_mechanism": "resolved_permission_and_inventory",
  "task_schema_directly_exposed": false,
  "normal_agent_breakglass_task_action": "deny",
  "breakglass_mode": "primary",
  "normal_agent_non_exposure": true,
  "prompt_behavior_used_as_oracle": false
}
```

- [ ] **Step 2: Run the Breakglass runtime test and verify RED**

Run: `bash models/routing/opencode/eval/tests/breakglass-runtime-test.sh`

Expected: FAIL because the existing function still requires a model-emitted Task attempt.

- [ ] **Step 3: Split non-exposure from positive execution**

Implement `capture_breakglass_non_exposure()` using only structured resolved-agent JSON. Evaluate permissions with OpenCode V1 last-match-wins semantics. Do not invoke a model. Refactor positive execution into `probe_breakglass_primary()` so its return status depends only on resolved human-primary selection, provider success, and exact `BREAKGLASS_PRIMARY_OK` text.

Remove the normal-model prompt invocation entirely. Keep structured explicit Task rejection support only if it can be invoked without an LLM; otherwise record `task_schema_directly_exposed: false` and use resolved permission plus inventory evidence.

- [ ] **Step 4: Capture the real non-exposure record**

Run the non-cost-bearing function against OpenCode V1 and write `breakglass-normal-agent-non-exposure.json`. Confirm it reports `normal_agent_non_exposure: true`, primary mode, exact model/variant, and no session/provider metadata.

- [ ] **Step 5: Update security evidence and verify GREEN**

Document that OpenCode V1 offers resolved permission/inventory evidence but no standalone Task-target schema dump, and that prompt behavior is not the security oracle.

Run:

```bash
bash models/routing/opencode/eval/tests/breakglass-runtime-test.sh
bash models/routing/opencode/eval/tests/breakglass-test.sh
```

Expected: PASS.

- [ ] **Step 6: Commit corrected boundary evidence**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/probe-breakglass.sh \
  models/routing/opencode/eval/tests/breakglass-runtime-test.sh \
  models/routing/opencode/eval/records/breakglass-normal-agent-non-exposure.json \
  models/routing/opencode/docs/evidence/2026-09-02-phase-0-security-boundary.md
git commit -m "fix(opencode): record Breakglass non-exposure"
```

---

### Task 3: Attempt Breakglass Human-Primary Execution Once

**Files:**
- Preserve unchanged: `models/routing/opencode/eval/records/breakglass-boundary.json`
- Create: `models/routing/opencode/eval/records/breakglass-primary-attempt-2026-09-03.json`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-phase-0-security-boundary.md`

**Interfaces:**
- Consumes: `probe_breakglass_primary PROFILE OUTPUT` from Task 2.
- Produces: One immutable new attempt classified `PASS` or `BLOCKED_EXTERNAL`; never retries in this closure.

- [ ] **Step 1: Add classification tests before the live call**

Add fake provider cases asserting exact response => `PASS`; HTTP 429/usage limit, authentication, network, or provider outage => `BLOCKED_EXTERNAL`; wrong exact response with a healthy provider => `FAIL`. Assert the output includes attempt number `1`, retry count `0`, runtime version, resolved model/variant, sanitized provider error, and no raw headers/session IDs.

- [ ] **Step 2: Run the test and verify RED, then implement classification**

Run the focused test before and after implementation. The implementation must return nonzero for both `BLOCKED_EXTERNAL` and `FAIL`, while still writing the record.

- [ ] **Step 3: Execute exactly one live positive attempt**

Run `probe_breakglass_primary` once. Do not rerun if it returns a quota/provider failure. Preserve the prior `breakglass-boundary.json` unchanged and write the new dated record.

- [ ] **Step 4: Update evidence with the observed result**

If the result is `PASS`, record exact successful human-primary execution. If quota remains unavailable, record `BLOCKED_EXTERNAL` and the sanitized reason. Do not weaken the gate.

- [ ] **Step 5: Commit the immutable attempt**

```bash
git add models/routing/opencode/eval/runtime/opencode-v1-adapter/probe-breakglass.sh \
  models/routing/opencode/eval/tests/breakglass-runtime-test.sh \
  models/routing/opencode/eval/records/breakglass-primary-attempt-2026-09-03.json \
  models/routing/opencode/docs/evidence/2026-09-02-phase-0-security-boundary.md
git commit -m "chore(opencode): record Breakglass primary attempt"
```

---

### Task 4: Add Bounded Self-Variance Execution

**Files:**
- Create: `models/routing/opencode/eval/fixtures/self-variance/fixture.json`
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/run-self-variance.sh`
- Create: `models/routing/opencode/eval/tests/self-variance-runner-test.sh`
- Modify: `models/routing/opencode/eval/runtime/opencode-v1-adapter/provenance.sh`

**Interfaces:**
- Consumes: Validated `phase-0-budgets.json`, fixed fixture JSON, OpenCode V1 JSON events.
- Produces: `run_self_variance_once FIXTURE BUDGET OUTPUT`, one fully-provenanced run; `run_self_variance_set FIXTURE BUDGET OUTPUT_DIR`, exactly three valid runs or explicit retained invalid records.

- [ ] **Step 1: Write failing runner tests**

Use a fake OpenCode binary with complete text and `step_finish` events. Assert exact invocation of Luna-low, exact response scoring, fixture SHA-256, and these fields:

```text
routing_profile_id
routing_profile_commit
runtime_version
eval_runner_version
timestamp
environment
provider
model
variant
pricing_regime
classification
fixture_digest
score
instrumentation_schema
credit_report.observed_cost
credit_report.cost_unit
credit_report.cost_source
credit_report.derived_credits
tokens
wall_clock_ms
retry_count
candidate_results_used
```

Assert the runner rejects an unvalidated/missing budget, refuses a fourth valid run, retains an `INVALID_ENVIRONMENT` record, never converts direct OpenAI telemetry, and marks `candidate_results_used: false`.

- [ ] **Step 2: Run the runner test and verify RED**

Run: `bash models/routing/opencode/eval/tests/self-variance-runner-test.sh`

Expected: FAIL because the runner and fixture do not exist.

- [ ] **Step 3: Implement the fixed fixture and one-run adapter**

Use a fixed prompt and oracle such as exact `SELF_VARIANCE_OK`. Set profile ID to `phase-0-self-variance-non-production`, profile commit to current repository HEAD at execution, runner version to a literal schema version such as `phase0-self-variance-v1`, provider/model to Copilot Luna-low, and pricing to standard.

For Copilot provider-reported USD cost, derive credits as `observed_cost * 100` and record both the source and conversion. Leave derived credits null for unknown/incompatible units. Classify nonzero runtime/provider failures as `INVALID_ENVIRONMENT` with sanitized evidence.

- [ ] **Step 4: Implement the three-valid-run set and budget guard**

Before each run, sum only comparable derived eval credits already persisted in the set and refuse a call whose conservative envelope would exceed 100. Retain invalid records with monotonically increasing attempt numbers; stop for operator classification rather than automatically retrying indefinitely. Stop after exactly three valid records.

- [ ] **Step 5: Run focused and full tests to GREEN**

```bash
bash models/routing/opencode/eval/tests/self-variance-runner-test.sh
bash models/routing/opencode/eval/run-tests.sh
```

Expected: PASS without real model calls because tests use the fake binary.

- [ ] **Step 6: Commit the runner before cost-bearing execution**

```bash
git add models/routing/opencode/eval/fixtures/self-variance/fixture.json \
  models/routing/opencode/eval/runtime/opencode-v1-adapter/run-self-variance.sh \
  models/routing/opencode/eval/runtime/opencode-v1-adapter/provenance.sh \
  models/routing/opencode/eval/tests/self-variance-runner-test.sh
git commit -m "feat(opencode): add bounded self-variance runner"
```

---

### Task 5: Execute and Measure Self-Variance

**Files:**
- Create: `models/routing/opencode/eval/records/self-variance/run-*.json`
- Create: `models/routing/opencode/eval/records/self-variance/summary.json`
- Modify: `models/routing/opencode/eval/scoring/self-variance.sh`
- Modify: `models/routing/opencode/eval/tests/self-variance-test.sh`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-phase-0-self-variance.md`

**Interfaces:**
- Consumes: Individual records from Task 4.
- Produces: `measure_self_variance SUMMARY RUN...` including boolean consistency checks and min/median/max/range/relative-range for comparable continuous metrics.

- [ ] **Step 1: Extend tests for measured ranges**

Use literal records with wall-clock values `1000, 1100, 1200` and derived credits `1.0, 1.1, 1.2`. Assert median `1100`/`1.1`, range `200`/`0.2`, and relative range `0.181818...` for both. Assert unavailable output if units differ, any run is invalid, or derived credits are null. Keep existing four consistency checks.

- [ ] **Step 2: Run the scorer test and verify RED**

Run: `bash models/routing/opencode/eval/tests/self-variance-test.sh`

Expected: FAIL because measured continuous ranges are absent.

- [ ] **Step 3: Implement range measurement and verify GREEN**

Implement median and relative range with Python's standard library. Retain individual values in the summary; do not pool other fixtures or claim significance.

- [ ] **Step 4: Execute the approved live run set**

Run `run_self_variance_set` once to obtain three valid Luna-low records. If an environment-invalid run occurs, preserve it and stop for classification before replacement. Do not invoke candidate models or any Phase-R fixture.

- [ ] **Step 5: Generate and inspect the summary**

Run `measure_self_variance` over exactly the three valid records. Verify all four required checks and `self_variance_complete` are true, candidate results are false, provenance fields exist in every run, and total derived credits remain within 100.

- [ ] **Step 6: Update methodology evidence and commit measurements**

Document run IDs, model/variant, total observed credits/tokens, ranges, invalid attempts if any, and explicit non-candidate status.

```bash
git add models/routing/opencode/eval/records/self-variance \
  models/routing/opencode/eval/scoring/self-variance.sh \
  models/routing/opencode/eval/tests/self-variance-test.sh \
  models/routing/opencode/docs/evidence/2026-09-02-phase-0-self-variance.md
git commit -m "chore(opencode): record harness self-variance"
```

---

### Task 6: Freeze Practical Continuous Thresholds

**Files:**
- Create: `models/routing/opencode/eval/scoring/continuous-thresholds.sh`
- Create: `models/routing/opencode/eval/tests/continuous-thresholds-test.sh`
- Modify: `models/routing/opencode/eval/thresholds/continuous.json`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-phase-0-self-variance.md`

**Interfaces:**
- Consumes: committed `summary.json` with `candidate_results_used: false`.
- Produces: `derive_continuous_thresholds SUMMARY OUTPUT COMMIT_REFERENCE`; frozen operational thresholds.

- [ ] **Step 1: Write failing threshold tests**

Assert `max(2 * relative_range, floor)` for wall-clock floor `0.20` and comparable credits floor `0.10`. Cover both floor-dominant and variance-dominant examples. Assert refusal if self-variance is incomplete, candidate results were used, commit reference is empty, or units are incompatible. Assert a lower median alone is explicitly insufficient.

- [ ] **Step 2: Run the threshold test and verify RED**

Run: `bash models/routing/opencode/eval/tests/continuous-thresholds-test.sh`

Expected: FAIL because the derivation script does not exist.

- [ ] **Step 3: Implement derivation and freeze the threshold file**

Write structured entries for each metric:

```json
{
  "metric": "wall_clock_ms",
  "observed_self_variance": {"relative_range": 0.0},
  "practical_separation_threshold": 0.20,
  "rule": "max(2 * relative_range, 0.20)",
  "reasoning": "operational threshold; lower median alone is insufficient",
  "commit_reference": "<self-variance evidence commit>"
}
```

Use actual measured values. For unavailable cost units, record threshold status unavailable and forbid separation instead of inventing a number.

- [ ] **Step 4: Verify ordering and commit**

Confirm the threshold file references the already-committed self-variance evidence SHA and no candidate records exist in the input.

```bash
bash models/routing/opencode/eval/tests/continuous-thresholds-test.sh
bash models/routing/opencode/eval/run-tests.sh
git add models/routing/opencode/eval/scoring/continuous-thresholds.sh \
  models/routing/opencode/eval/tests/continuous-thresholds-test.sh \
  models/routing/opencode/eval/thresholds/continuous.json \
  models/routing/opencode/docs/evidence/2026-09-02-phase-0-self-variance.md
git commit -m "chore(opencode): freeze continuous thresholds"
```

---

### Task 7: Publish Final Phase-0 Readiness Matrix

**Files:**
- Create: `models/routing/opencode/eval/manifests/phase-0-readiness.json`
- Create: `models/routing/opencode/eval/runtime/opencode-v1-adapter/validate-readiness.sh`
- Create: `models/routing/opencode/eval/tests/readiness-test.sh`
- Create: `models/routing/opencode/docs/evidence/2026-09-03-phase-0-readiness.md`
- Modify: `models/routing/opencode/docs/evidence/2026-09-02-phase-0-gates.md`

**Interfaces:**
- Consumes: all committed Phase-0 records/manifests/thresholds.
- Produces: `validate_phase0_readiness FILE`, requiring the approved status vocabulary and deriving overall completeness only when every required row is PASS.

- [ ] **Step 1: Write failing matrix tests**

Require rows for candidate capability, variant capability, agent inventory, Reviewer permissions, Expert permissions, Breakglass non-exposure, Breakglass human-primary execution, eval budget, recovery budget, self-variance, thresholds, provenance, installed manifest, Build fixture, Reviewer clean control, Compaction invariants, governance, and Sol pricing handling.

Assert only `PASS`, `BLOCKED_EXTERNAL`, `BLOCKED_DECISION`, and `FAIL` are accepted. Assert `phase_0_complete: true` only when every required row is PASS. A quota-blocked Breakglass row must force false without turning other passing rows into failures.

- [ ] **Step 2: Run readiness test and verify RED**

Run: `bash models/routing/opencode/eval/tests/readiness-test.sh`

Expected: FAIL because readiness artifacts do not exist.

- [ ] **Step 3: Implement validator and populate evidence-backed statuses**

Each row contains status, evidence path, and concise rationale. Use the actual Task 3 Breakglass result. Do not claim Phase 0 complete if that result is blocked externally. Installed-profile manifest may PASS as a schema/provenance-ceiling gate while retaining `installed_at: null` for a profile not activated; explain that no installation occurred because production routing remained unchanged.

- [ ] **Step 4: Update human-readable status docs**

Publish the same matrix in Markdown, include approved budgets, self-variance summary, frozen thresholds, and remaining blockers. Update the prior gate doc to point to the final record rather than retaining stale unresolved-budget wording.

- [ ] **Step 5: Run focused and full tests**

```bash
bash models/routing/opencode/eval/tests/readiness-test.sh
bash models/routing/opencode/eval/run-tests.sh
```

Expected: PASS. The validator passing means the matrix is internally valid, not necessarily that `phase_0_complete` is true.

- [ ] **Step 6: Commit final readiness evidence**

```bash
git add models/routing/opencode/eval/manifests/phase-0-readiness.json \
  models/routing/opencode/eval/runtime/opencode-v1-adapter/validate-readiness.sh \
  models/routing/opencode/eval/tests/readiness-test.sh \
  models/routing/opencode/docs/evidence/2026-09-03-phase-0-readiness.md \
  models/routing/opencode/docs/evidence/2026-09-02-phase-0-gates.md
git commit -m "docs(opencode): publish Phase 0 readiness"
```

---

### Task 8: Verify Unchanged Rules, Scope, and Open Pull Request

**Files:** No intended source changes; fix only verified defects within Tasks 1-7.

**Interfaces:**
- Consumes: completed closure branch.
- Produces: independently reviewed PR against `main` with truthful completion/blocker status.

- [ ] **Step 1: Run complete verification**

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
```

Expected: all tests PASS and no whitespace errors.

- [ ] **Step 2: Verify frozen count/state behavior explicitly**

Run:

```bash
bash models/routing/opencode/eval/tests/count-rules-test.sh
bash models/routing/opencode/eval/tests/build-gate-test.sh
bash models/routing/opencode/eval/tests/fixtures-test.sh
```

Confirm coverage remains n=3/n=5 including terminal branches; Build 3/3, 2/3 extension, 4/5, <=3/5; valid-failure persistence; invalid-environment replacement; fixture-defect reset; and fixture-control exclusion. Do not redesign these functions.

- [ ] **Step 3: Prove production scope is unchanged**

```bash
test -z "$(git diff main --name-only -- \
  models/routing/opencode/opencode.jsonc \
  models/routing/opencode/.opencode/agents)"
```

Also inspect the full changed-file list for Phase-R/restored-profile artifacts. Expected: none.

- [ ] **Step 4: Request independent code/evidence review**

Review `main..HEAD` against the design and governing decision. Resolve blocking/important implementation findings with TDD and rerun complete verification. Treat provider quota or current billing visibility as external evidence blockers, not code defects.

- [ ] **Step 5: Push and create the pull request**

Push `chore/opencode-routing-phase-0-closure` and create a PR titled:

```text
chore(opencode): close routing Phase 0 evidence
```

The PR body must separately list implemented infrastructure, measured evidence, external blockers, and the approved 100/250 budgets. State `Phase 0 complete` only if the readiness manifest has `phase_0_complete: true`; otherwise name the exact blocking rows. Explicitly state production routing is unchanged and Phase R was not started.

## Self-Review

- Spec coverage: Tasks 1-7 cover budgets, governance, Breakglass semantics and one positive attempt, repeated measurements, provenance, threshold ordering, and the final matrix; Task 8 covers unchanged rules, production scope, review, and PR.
- Cost ordering: budget is committed in Task 1; the Breakglass call occurs once in Task 3; the three-run self-variance executor is committed before execution in Task 5.
- Candidate isolation: no task invokes Build, Reviewer, or Expert comparative fixtures; Luna-low is explicitly non-candidate instrumentation.
- Evidence integrity: prior Breakglass failure is preserved, invalid self-variance attempts are retained, and unavailable units remain unavailable.
- Type consistency: budget validator, Breakglass capture/probe, self-variance runner/scorer, threshold derivation, and readiness validator interfaces are defined once and consumed by later tasks under the same names.
- Placeholders: runtime-generated commit references use explicit command output at execution time; no design requirement is deferred.
