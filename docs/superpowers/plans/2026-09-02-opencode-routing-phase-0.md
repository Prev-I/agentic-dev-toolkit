# OpenCode V1 Routing Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish measured, testable OpenCode V1 routing gates without changing the published routing profile or entering Phase R.

**Architecture:** A dependency-free Bash harness records runtime calls through a small OpenCode V1 adapter and writes JSON evidence. Runtime-neutral fixture metadata, scoring, and decision rules remain separate from that adapter. Tests use Bash assertions and fixtures only; model calls are explicit Phase-0 probes, never test fixtures.

**Tech Stack:** Bash, JSON, OpenCode V1 CLI, existing `tests/install.sh` conventions.

**Spec:** `models/routing/opencode/docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md`

## Global Constraints

- Do not modify `models/routing/opencode/opencode.jsonc` or production agent definitions.
- Do not activate restored routing, increase Expert effort, or execute Phase R, Phase 3, or Phase 4.
- Every model/variant claim requires a successful explicit `opencode run --model ... --variant ...` probe recorded with raw result metadata.
- Runtime-neutral fixtures/scoring must not invoke OpenCode.
- Persist build-failure classification before a replacement or extension run.
- Preserve separate `observed_cost` and `normalized_steady_state_cost` fields.
- Treat pre-2026-09-04 Sol cost as promotional; never canonical steady-state cost.
- Project eval and Phase-R recovery budgets remain blocking Phase-R inputs until numerically approved.

---

### Task 1: Harness scaffold and test runner

**Files:** Create `models/routing/opencode/eval/{fixtures,scoring,thresholds,decision-rules,runtime/opencode-v1-adapter,records,manifests}/`; create `models/routing/opencode/eval/run-tests.sh`; create `models/routing/opencode/eval/tests/test-lib.sh`.

- [ ] Create directories and executable test runner with `set -Eeuo pipefail` and `IFS=$'\n\t'`.
- [ ] Add a failing test that asserts the required layout exists.
- [ ] Implement layout assertion and run `bash models/routing/opencode/eval/run-tests.sh` to green.
- [ ] Commit `feat(opencode): scaffold Phase 0 eval harness`.

### Task 2: Provenance and installed-profile manifest

**Files:** Create `eval/runtime/opencode-v1-adapter/provenance.sh`, `eval/manifests/installed-profile.json`, `eval/tests/provenance-test.sh`.

- [ ] Write failing tests for required run fields: `routing_profile_id`, `routing_profile_commit`, `runtime_version`, `eval_runner_version`, `timestamp`, `provider`, `model`, `variant`, `pricing_regime`, `observed_cost`, and `normalized_steady_state_cost`.
- [ ] Implement JSON record emission and manifest validation for `profile_id`, `source_commit`, `installed_at`, and `opencode_version`.
- [ ] Assert unknown cost remains null and ordinary-session provenance is documented as installed-profile attribution only.
- [ ] Commit `feat(opencode): record routing provenance`.

### Task 3: Runtime capability matrix and agent inventory

**Files:** Create `eval/runtime/opencode-v1-adapter/probe.sh`, `docs/evidence/2026-09-02-phase-0-capability-matrix.md`, `eval/tests/probe-test.sh`.

- [ ] Test command construction for a fresh `opencode run --model MODEL --variant VARIANT` trivial request and JSON result parsing.
- [ ] Implement recording of version, model listing, timestamp, repository commit, environment, stdout/stderr, exit status, timing, and retries.
- [ ] Probe required candidates and every required variant: Opus highest-supported/high, Sonnet high, Terra high and low/medium, Luna medium/low, Copilot Sol high, and OpenAI Sol xhigh/max.
- [ ] Record actual accepted syntax and agent inventory; if a semantic effort has no exact accepted syntax, record nearest value and stop that affected item for an amendment.
- [ ] Commit `chore(opencode): record Phase 0 capability matrix`.

### Task 4: Pure count rules and Build gate state machine

**Files:** Create `eval/decision-rules/count-rules.sh`, `eval/decision-rules/build-gate.sh`, `eval/tests/count-rules-test.sh`, `eval/tests/build-gate-test.sh`.

- [ ] Write failing table-driven tests for every n=3/n=5 rule, both-low fixture findings, terminal catch-alls, 3/3 pass, 2/3 extension, <=1/3 block, 4/5 pass, and <=3/5 block.
- [ ] Implement pure shell functions returning explicit states, never a weighted score.
- [ ] Add append-only classification ledger validation: invalid environment replacement, permanent valid failure, fixture-defect reset, and no erasure of prior valid failure.
- [ ] Commit `feat(opencode): add deterministic Build gate rules`.

### Task 5: Build fixture family and diagnostic control metadata

**Files:** Create `eval/fixtures/build-workloads/{build-restoration-gate,build-feature,build-bugfix,build-refactor}/fixture.json`, `eval/scoring/build-control.sh`, and tests.

- [ ] Write failing tests that restoration gate is mechanical and Phase-3 workloads cannot score as Phase-R evidence.
- [ ] Implement fixture schema requiring snapshot, bounded task, initially failing acceptance tests, regression command, required artifacts, behavior tests, and forbidden-scope assertions.
- [ ] Add Sonnet n=3 control metadata marked `diagnostic_only` and `excluded_from_phase_3_selection` with the approved interpretation table.
- [ ] Commit `feat(opencode): add Build fixtures and control`.

### Task 6: Reviewer, Expert, and Compaction fixtures

**Files:** Create reviewer, expert, and compaction fixture JSON plus scoring scripts and tests.

- [ ] Add reviewer seeded categories for concurrency, authorization/security, API compatibility, boundary handling, and error swallowing plus a clean control.
- [ ] Test grounded reviewer counts and reject an ungrounded rate denominator.
- [ ] Add Expert A/B/C unpooled metadata, Opus 5 diagnostic-control-only metadata, and Grok 4.6 future-challenger metadata.
- [ ] Add tagged compaction invariants and an exact N/N preservation scorer with tests.
- [ ] Commit `feat(opencode): add Phase 0 quality fixtures`.

### Task 7: Self-variance and thresholds

**Files:** Create `eval/scoring/self-variance.sh`, `eval/thresholds/continuous.json`, tests, and methodology documentation.

- [ ] Write failing tests for determinism, scoring repeatability, instrumentation consistency, and credit-report consistency records.
- [ ] Implement self-variance collection and refuse threshold finalization until self-variance is complete.
- [ ] Record that candidate A/B results cannot create continuous thresholds.
- [ ] Commit `feat(opencode): add self-variance gate`.

### Task 8: Permission and Breakglass Phase-0 boundary

**Files:** Create a non-production Phase-0 test profile, permission test scripts, Breakglass schema/validator, and tests.

- [ ] Write failing tests for `breakglass.mode == primary` and rejection of missing, `all`, and `subagent` mode.
- [ ] Implement read-only Reviewer/Expert semantic checks from actual V1 permissions and Breakglass normal-agent denial/human-primary invocation tests.
- [ ] Ensure `hidden` is never evaluated as a security control and autonomous escalation is absent.
- [ ] Commit `feat(opencode): add Phase 0 routing security gates`.

### Task 9: Governance, budgets, and Phase-0 documentation

**Files:** Create Phase-0 evidence/readme under `docs/evidence/`; update routing README only for harness invocation.

- [ ] Record resolved local ownership and external billing enforcement without creating a spending-cap feature.
- [ ] Record eval and Phase-R recovery budgets as distinct unresolved Phase-R inputs unless human-approved numbers exist.
- [ ] Document Sol promotional pricing and ordinary-session provenance ceiling.
- [ ] Commit `docs(opencode): document Phase 0 gates`.

### Task 10: End-to-end verification and PR

- [ ] Run all eval tests, `bash tests/install.sh`, `git diff --check`, and direct candidate probes.
- [ ] Verify no production routing file or agent definition changed and Phase R was not invoked.
- [ ] Create the Phase-0-only PR with results, remaining blockers, and explicit no-Phase-R declaration.

## Self-Review

- Coverage: Tasks 1-9 cover every requested Phase-0 gate; Task 10 verifies the branch.
- Placeholders: no implementation placeholder is used; each task names files, tests, and acceptance behavior.
- Scope: routing restoration, Expert activation, Phase 3, and Phase 4 remain excluded.
