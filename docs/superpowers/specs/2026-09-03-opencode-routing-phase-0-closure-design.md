# OpenCode V1 Routing Phase 0 Evidence Closure Design

**Date:** 2026-09-03
**Scope:** Remaining Phase-0 evidence only
**Governing decision:** `models/routing/opencode/docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md`

## Objective

Close the remaining Phase-0 evidence gates without changing production routing
or beginning Phase R. The work records approved numeric budgets, corrects the
Breakglass normal-agent evidence semantics, executes a bounded self-variance
measurement, freezes practical continuous thresholds, and publishes one final
readiness matrix.

Phase 0 remains incomplete if the direct OpenAI Breakglass execution remains
quota-blocked or any other required gate is not `PASS`.

## Hard Boundaries

The closure must not:

- modify `models/routing/opencode/opencode.jsonc`;
- modify production `.opencode/agents/*` definitions;
- restore or activate production routing;
- change Expert production effort;
- execute Phase R;
- run Build Opus-vs-Sonnet A/B, Reviewer effort, or Phase-4 Expert experiments;
- expose candidate A/B results before continuous thresholds are committed;
- borrow from the Phase-R recovery budget for evaluation work.

## Approved Budgets

The human operational owner approved these separate allocations in the task
conversation on 2026-09-03:

```text
eval_budget_credits = 100
phase_r_recovery_budget_credits = 250
```

The recovery allocation is reserved for future Phase-R bisection and forward
recovery. It is not evaluation contingency.

The organization-level Copilot guardrail remains separate:

```text
standard Copilot Business allowance = 1,900 credits per user per billing cycle
maximum user consumption guardrail = 4 x 1,900 = 7,600 credits
```

Paid usage is allowed. Enforcement belongs to GitHub billing and organizational
controls; OpenCode has no native spending-cap mechanism. At the guardrail,
execution stops and escalates to the spend owner without automatic fallback.

The repository contains a historical observation of 331 credits consumed on
2026-09-01. It does not contain a current billing snapshot or pooled-seat state,
so current remaining organizational headroom is recorded as unknown. The
historical arithmetic headroom was 7,269 credits, but that is not treated as the
current available balance.

Existing capability records emitted approximately 0.27998832 in OpenCode
runtime cost across 11 calls. For Copilot, this is treated as provider-reported
USD telemetry only where the runtime contract supports that interpretation;
GitHub's public conversion is 1 AI credit = USD 0.01. The records do not prove
that direct OpenAI zero values or every provider's cost field share that billing
contract. Budget accounting therefore preserves source and units and does not
silently convert incompatible telemetry.

## Breakglass Evidence

### Normal-Agent Boundary

The security property is:

```text
normal LLM routing cannot invoke Breakglass as a subagent
```

OpenCode V1 may remove denied agents from the Task tool description, so model
prompt behavior is not the oracle and a model is not required to attempt a
denied call.

The audited runtime exposes resolved agent configuration through
`opencode debug agent`. It does not expose a standalone command that serializes
the exact model-facing Task-target schema. The strongest deterministic evidence
available without relying on prompt behavior is therefore:

1. the generated non-production normal agent resolves an ordered Task ruleset
   containing broad allow followed by `breakglass: deny`;
2. the generated Breakglass agent resolves as `mode: primary` with the exact
   direct OpenAI model and `max` variant;
3. the runtime agent inventory classifies Breakglass as primary, not subagent or
   all-mode;
4. if an explicit structured Task rejection is obtainable without depending on
   model choice, retain it as additional evidence, not as the required oracle.

The final record names this mechanism `resolved_permission_and_inventory`.
Prompt refusal or failure to emit a Task call is neither pass nor fail evidence.

### Human-Primary Boundary

The positive gate requires all of:

```text
explicit --agent breakglass selection
resolved primary / openai/gpt-5.6-sol / max configuration
successful provider execution
exact BREAKGLASS_PRIMARY_OK text event
```

The previous failed record is preserved. The closure performs at most one new
direct OpenAI attempt if current usage is available. A quota, authentication,
network, or provider failure is classified `BLOCKED_EXTERNAL`, preserved with
sanitized error evidence, and not retried repeatedly. It is never reclassified
as a routing or configuration failure and never weakened into a pass.

## Self-Variance Measurement

The harness currently scores supplied run records but does not execute repeated
runs. The closure adds a small non-candidate runner around the existing OpenCode
V1 adapter.

Exactly three valid repeated calls use:

```text
provider/model: github-copilot/gpt-5.6-luna
variant: low
fixture: fixed Phase-0 instrumentation fixture
oracle: exact deterministic response
candidate A/B data: excluded
```

Luna-low is used as harness instrumentation, not as comparative role-fitness
evidence. The fixture, prompt, scorer, runtime adapter, and instrumentation
schema remain identical across runs.

Each individual run preserves:

- `routing_profile_id`;
- `routing_profile_commit`;
- `runtime_version`;
- `eval_runner_version`;
- timestamp and environment;
- provider, model, and variant;
- pricing regime;
- exit status and environment classification;
- exact fixture digest and structured score;
- observed runtime cost with source and units;
- derived credits only when an explicit conversion contract applies;
- token usage and wall-clock duration;
- retry count.

Environment-invalid runs are retained and classified separately. They do not
enter the valid self-variance denominator, and replacement requires recorded
evidence. Valid inconvenient runs are never discarded. The eval runner refuses
to exceed the approved 100-credit allocation.

The summary measures:

- fixture digest determinism;
- structured scoring repeatability;
- instrumentation schema consistency;
- credit-report field/type consistency;
- observed wall-clock range and relative range;
- observed cost/credit range and relative range where units are comparable.

No statistical-significance claim is made from three runs.

## Continuous Thresholds

Threshold ordering is enforced as:

```text
persist self-variance runs
-> commit measured summary
-> derive practical thresholds
-> commit thresholds
-> future candidate results may become visible
```

For each comparable continuous metric, the operational separation threshold is:

```text
max(2 x measured relative self-variance range, practical floor)
```

Practical floors are:

| Metric | Floor | Rationale |
|---|---:|---|
| Wall-clock time | 20% | Avoid selecting on small environmental timing noise. |
| Comparable observed cost or credits | 10% | Avoid selecting on minor billing/instrumentation variation. |

The measured relative range is `(maximum - minimum) / median`. A future arm
separates on a continuous metric only when its median improvement over the other
arm meets or exceeds the frozen threshold and all values use compatible units
and pricing regimes. A lower median alone is insufficient.

If a metric lacks comparable units or valid measurements, its threshold is
recorded as unavailable and it cannot separate candidates. In particular,
promotional Copilot Sol cost cannot establish canonical steady-state Reviewer
cost, and direct OpenAI zero telemetry is not interpreted as free service.

These are operational decision thresholds, not confidence intervals or tests of
statistical significance.

## Readiness Matrix

The final evidence document classifies every required gate using only:

```text
PASS
BLOCKED_EXTERNAL
BLOCKED_DECISION
FAIL
```

It includes candidate and variant capability, agent inventory, Reviewer and
Expert permissions, both Breakglass sides, both budgets, self-variance,
continuous thresholds, eval provenance, installed-profile manifest, Build
fixture/state rules, Reviewer clean control, Compaction invariants, governance,
and Sol pricing handling.

Phase 0 is complete only when every required row is `PASS`. Any direct OpenAI
quota failure leaves Breakglass human-primary execution `BLOCKED_EXTERNAL` and
the overall Phase-0 status incomplete.

## Files And Interfaces

Prefer extending existing files over adding general-purpose infrastructure:

- correct `eval/runtime/opencode-v1-adapter/probe-breakglass.sh` to separate
  normal-agent non-exposure from positive execution;
- add one bounded self-variance runner under the existing V1 adapter;
- extend `eval/scoring/self-variance.sh` to report measured ranges;
- add a machine-readable budget decision under `eval/manifests/`;
- persist individual closure runs under `eval/records/` without overwriting the
  prior failed Breakglass record;
- update `eval/thresholds/continuous.json` only after measured evidence exists;
- update Phase-0 evidence docs and create the final readiness record;
- add focused Bash tests to the existing test runner.

Production routing files are out of scope.

## Verification

Run:

```bash
bash models/routing/opencode/eval/run-tests.sh
bash tests/install.sh
git diff --check
```

Also compare the branch against `main` and require no changes under:

```text
models/routing/opencode/opencode.jsonc
models/routing/opencode/.opencode/agents/*
```

Review the branch independently before opening a pull request. The PR must
distinguish infrastructure changes, measured evidence, external blockers, and
human-approved budget decisions. It must not state that Phase 0 is complete
unless every readiness row is `PASS`.
