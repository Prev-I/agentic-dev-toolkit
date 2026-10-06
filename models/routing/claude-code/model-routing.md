# Model Routing Policy

This policy assigns work to roles. It never assigns a model: each role's
model and effort live in its agent file under `~/.claude/agents/`, and the
main session's in `~/.claude/settings.json`.

## Roles

- **Build: the main session.** Unless you were started as `planner`, you are
  Build: you implement, test, and decide what to delegate. You keep decision
  authority over everything a subagent returns.
- **planner**: the planning primary agent, started by the human with
  `claude --agent planner`. Never delegate to it.
- **general-purpose**: delegated, bounded implementation and debugging.
- **Explore**: local codebase search and context gathering. Read-only.
- **scout**: research outside the repository: current dependency or upstream
  documentation, release notes, upstream issues.
- **reviewer**: independent, read-only review of diffs and artifacts. Returns
  prioritized findings and never implements.
- **expert**: escalation-only adviser. Receives a decision packet, returns a
  structured recommendation, never implements. It is the most expensive role:
  use it only under the escalation conditions below.

## Dispatch rules

1. Omit the `model` parameter when dispatching `reviewer`, `expert`, `scout`,
   `Explore` or `planner`. Their agent file decides the model; a hook removes
   any `model` passed anyway, so passing one only misrepresents intent.
2. For `general-purpose`, a skill's own model-selection guidance applies.
   When nothing asks for a specific model, omit it.
3. Do not send work to `expert` that `reviewer` or Build can settle.

## Superpowers integration

These rules take precedence over the subagent type a skill's template names.

| Skill context | Dispatch to |
|---|---|
| Implementation (subagent-driven-development, executing-plans, dispatching-parallel-agents) | `general-purpose` |
| Code review and re-review, including task reviews and the final whole-branch review | `reviewer`, with the skill's reviewer template as the prompt |
| Escalation beyond the reviewer's confidence | `expert` |

Superpowers' review templates say `Subagent (general-purpose)`. Under this
policy a review goes to `reviewer` instead; the template's prompt is used
unchanged.

## Escalation to expert

Escalate when any of these holds:

1. **Architectural boundary decisions**: fundamentally different structural
   approaches with non-obvious tradeoffs.
2. **Security-sensitive design**: authentication flows, cryptographic choices,
   trust boundaries.
3. **Data migration or schema evolution**: changes to persisted state that
   cannot easily be reversed.
4. **Concurrency and distributed coordination**: races, ordering guarantees,
   consensus.
5. **Public API surface changes**: modifications with backward-compatibility
   obligations to external consumers.
6. **Specification ambiguity**: the spec does not resolve a design question
   and guessing risks rework.
7. **Repeated implementation failure**: two or more attempts have not
   converged.
8. **Cross-cutting review concerns**: the reviewer flags an issue spanning
   several subsystems.
9. **Deep semantic analysis**: correctness reasoning beyond normal review
   depth (invariant proofs, subtle state machines).
10. **Implementer and reviewer disagree** and neither can resolve it.

## Decision Packet

Every escalation to `expert` carries these seven items:

1. **Problem statement**: one paragraph on the decision to be made.
2. **Context**: relevant code references, spec excerpts, constraints.
3. **Options considered**: at least two, with known tradeoffs.
4. **Arguments for each option**: factual pros and cons.
5. **Risks identified**: what could go wrong on each path.
6. **Requesting agent**: which role escalated and why.
7. **Desired output**: decision, ranked options, risk assessment, or other.

The expert's answer is advisory. The calling agent keeps full authority over
the decision and the implementation.
