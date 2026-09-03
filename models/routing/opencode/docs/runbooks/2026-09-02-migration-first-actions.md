# OpenCode Routing V3.4.3 — First Implementation Actions

**Source of truth:** [approved routing plan](../decisions/2026-09-02-multi-model-routing-v3.4.3.md)

The design is closed. Do not change routing rows or reopen model selection while executing these first actions.

## 1. Close negative capability evidence

Run direct trivial calls against:

```text
github-copilot/claude-opus-4.6
github-copilot/claude-sonnet-4.6
```

For each attempt record:

```text
timestamp
opencode version
provider/model ID
command or invocation method
result
error class
error text/reference
```

Rules:

- absence from `opencode models` is not sufficient;
- auth, rate-limit, network, or policy failures are not retirement/unavailability proof;
- only publish the capability statement supported by the observed call result.

## 2. Land Track A

Update:

```text
models/routing/opencode/README.md
models/routing/opencode/.opencode/model-routing.md
```

Track A must:

- state the actual observed Opus 4.6 capability result;
- state that GPT-5.3-Codex currently resolves;
- label migration away from Codex as a risk decision, not a capability finding;
- instruct users to verify model usability with runtime resolution plus a trivial successful call.

Track A changes no routing.

## 3. Close named ownership/governance blockers

Record named accountable owners for:

### Copilot spend

```text
owner
overage allowed: yes/no
cap
behavior at allowance exhaustion
escalation path
```

Preserve the observed starting datum:

```text
331 AI credits consumed on 2026-09-01
```

as observation, not forecast.

### Direct OpenAI Expert governance

Record:

```text
account/workspace owner
contract/DPA applicability
retention/data-use terms
credential ownership
budget owner
approved usage boundary
incident/revocation path
```

### OpenCode V2 RFC ownership

Record the accountable routing/toolkit maintainer who must open the RFC when:

1. upstream promotes V2/2.x to stable/default and V1 enters maintenance/deprecation; or
2. remaining on V1 blocks a required capability/security remediation.

## 4. Stop condition

Do not begin Phase R until Phase 0 gates in the proposal are satisfied.

In particular, do not treat the historical profile as a rollback plan and do not substitute a synthetic Opus 4.7/4.8 baseline.

## 5. Preserve evidence

Commit or archive generated capability/governance records under a stable repository path so future routing changes can distinguish:

```text
capability fact
policy fact
risk decision
fixture result
```

## Phase-R ground-truth closure

The dated readiness record at
`../evidence/2026-09-03-phase-r-ground-truth-readiness.md` closes the executable
Reviewer, Explore, and Compaction ground truth, exact Scout/Compaction variants,
and user-global activation contract. Use that amendment with the approved
V3.4.3 decision when preparing Phase R.
