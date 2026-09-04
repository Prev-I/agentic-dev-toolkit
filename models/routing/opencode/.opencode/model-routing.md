# Model Routing Policy

This document defines how agent roles map to model families and when to escalate.

## Capability and migration status (Track A)

The source bundle's capability closure at
`models/routing/opencode/docs/evidence/2026-09-02-capability-closure.md`
records that the explicit `github-copilot/claude-opus-4.6` and
`github-copilot/claude-sonnet-4.6` IDs were not resolvable in the audited
OpenCode V1 runtime. This is runtime capability evidence, not a routing change.

`github-copilot/gpt-5.3-codex` resolved in discovery at the recorded capability
check. Moving away from Codex — including the reviewer role, previously part
of the Codex family and now routed to GPT-5.6 Sol on Copilot — was an explicit
migration-risk decision, not a claim that Codex was retired or unavailable.

Evidence has a strict hierarchy: documentation and policy provide candidate
information; `opencode models` provides a discovery/resolution signal; a
successful trivial call proves usable capability; and a role fixture proves
routing fitness. The organization policy page is authoritative for policy
state, not runtime capability state.

## Model Family Assignments

Four model families divide the workload by cognitive profile:

| Family | Strengths | Assigned Roles |
|--------|-----------|----------------|
| **Claude Opus 5** | Deep reasoning, nuanced code generation, architectural judgment | plan, build |
| **GPT-5.6 Terra** | Efficient bounded execution and summarization | general, compaction |
| **GPT-5.6 Luna** | Fast retrieval and broad pattern matching | explore, scout, title, summary |
| **GPT-5.6 Sol** | Deep analytical review and escalation | reviewer (Copilot), expert and breakglass (direct OpenAI) |

Role-to-model assignment lives in `opencode.jsonc`. This document assigns work
to roles; it never assigns a model.

### Why different families for different jobs

Placing the reviewer on a separate model family from the implementers (build, general) is a design
heuristic intended to introduce a more independent analytical perspective. It may reduce the risk of
shared blind spots, but it does not guarantee better review quality.

Reviewer and Expert both run GPT-5.6 Sol, on different providers and at
different reasoning efforts. Provider diversity is operational diversity, not
cognitive independence; this correlated-reasoning risk is tracked as
`R-EXPERT-CORRELATED-REASONING`.

## Role Descriptions

### plan
Owns high-level decomposition: reads specifications, produces ordered task lists, identifies risks,
and defines acceptance criteria. Never writes production code directly — delegates to build.

### build
The primary coding agent. Receives tasks from plan or the user and produces working, tested
implementations. Has full file-edit and shell access; any `git push` requires
confirmation (`ask`, not a blanket deny).

### general
Handles requests that span multiple concerns or do not clearly belong to plan or build. Also serves
as the default Superpowers implementation agent (brainstorming, TDD, subagent-driven-development).

### explore
Searches the codebase, reads documentation, and assembles context for other agents. Read-only by
design — it reports findings but does not modify files.

### scout
Similar to explore but optimized for narrow, targeted lookups: finding a specific function, tracing
a dependency, or confirming a fact across repositories.

### reviewer
An independent quality gate. Reviews diffs and implementation artifacts for correctness, spec
compliance, architectural fit, security, and maintainability. Operates read-only on a different
model family than the implementers to introduce an independent analytical perspective. Prompt and
permissions are defined in `.opencode/agents/reviewer.md`; model and variant are assigned by
`opencode.jsonc`.

### expert
A heavyweight advisory agent invoked only through explicit escalation. Provides structured
guidance on hard problems but never writes code. Prompt and permissions are defined in
`.opencode/agents/expert.md`; model and variant are assigned by `opencode.jsonc`.

### breakglass
Human-selected primary agent, never reachable through Task delegation. The `task` permission
denies it explicitly, at the top level and on every agent that can delegate. `hidden` is not
treated as a security property.

## Superpowers Integration

When Superpowers skills dispatch sub-agents, the following mapping applies:

| Skill context | Dispatched role |
|---------------|-----------------|
| Implementation work (brainstorming, TDD, parallel agents) | **general** |
| Code review (requesting-code-review, receiving-code-review) | **reviewer** (Copilot Sol high) |
| Escalation beyond reviewer confidence | **expert** (direct OpenAI Sol xhigh) |

## Escalation to Expert

The expert agent is advisory-only and requires an OpenAI subscription. Escalate when any of these
conditions is met:

1. **Architectural boundary decisions** — choosing between fundamentally different structural
   approaches where the tradeoffs are non-obvious.
2. **Security-sensitive design** — authentication flows, cryptographic choices, or trust boundaries.
3. **Data migration or schema evolution** — changes that affect persisted state and cannot be
   easily reversed.
4. **Concurrency and distributed coordination** — race conditions, ordering guarantees, or
   consensus requirements.
5. **Public API surface changes** — modifications that affect external consumers and carry
   backward-compatibility obligations.
6. **Specification ambiguity** — the spec does not clearly resolve a design question and
   guessing risks rework.
7. **Repeated implementation failure** — two or more attempts have not converged on a working
   solution.
8. **Cross-cutting review concerns** — the reviewer flags an issue that touches multiple
   subsystems and needs holistic judgment.
9. **Deep semantic analysis** — correctness reasoning that exceeds normal review depth
   (invariant proofs, subtle state-machine transitions).
10. **Implementer–reviewer disagreement** — the build agent and reviewer reach conflicting
    conclusions and neither can resolve it.

### Decision Packet

Every escalation to expert must include a structured packet with these seven items:

1. **Problem statement** — one-paragraph summary of the decision to be made.
2. **Context** — relevant code references, spec excerpts, and constraints.
3. **Options considered** — at least two alternatives with known tradeoffs.
4. **Arguments for each option** — factual pros and cons, not preferences.
5. **Risks identified** — what could go wrong with each path.
6. **Requesting agent** — which role triggered the escalation and why.
7. **Desired output** — what form the answer should take (decision, ranked options, risk
   assessment, etc.).

The expert returns a structured advisory response. The calling agent retains full authority
over the final decision and implementation.
