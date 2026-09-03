# OpenCode V1 Phase-R Ground-Truth Readiness - 2026-09-03

## Outcome

All ground-truth and activation decisions required to begin a future Phase R
are `READY`. This record does not activate routing or authorize model runs.

| Item | Status | Committed decision/evidence |
|---|---|---|
| Build restoration fixture | `READY` | Existing mechanical oracle and immutable 3-to-5 state machine |
| Reviewer seeded corpus | `READY` | Five independent cases under `eval/fixtures/reviewer-seeded-defects/cases/` |
| Reviewer clean control | `READY` | `eval/fixtures/reviewer-seeded-defects/clean/` with zero known material defects |
| Reviewer threshold | `READY` | 5/5 stable IDs; zero material/blocking clean findings |
| Explore fixture | `READY` | Exact `entry -> facade -> service -> adapter -> protocol` chain |
| Explore required hop count | `READY` | 4 |
| Compaction corpus | `READY` | Distributed noisy context plus four canonical invariant IDs |
| Compaction threshold | `READY` | 4/4 preserved; zero contradictions |
| Scout production variant | `READY` | `github-copilot/gpt-5.6-luna` `low` |
| Compaction production variant | `READY` | `github-copilot/gpt-5.6-terra` `medium` |
| Activation target | `READY` | Canonical `~/.config/opencode/opencode.jsonc` |
| Activation selector | `READY` | Exactly one top-level global config remains active |
| Effective configuration preservation | `PASS` | Normalized resolved explicit configuration is unchanged |
| Project routing override | `PASS` | Ancestor/project configuration contains no routing-owned keys |

## Activation contract

Future Phase R uses an existing sole user-global `opencode.json` or
`opencode.jsonc`; if neither exists it targets `opencode.jsonc`; if both exist it
stops. Project-local activation is not the Phase-R target, and no repository-owned
installer is introduced this cycle.

The manual/repository-guided merge must preserve unrelated global fields,
credentials, and secrets, create an uncommitted local backup, and merge only
routing-owned fields. After activation, Phase R must verify the effective
resolved profile because project configuration may override global values. The
installed-profile evidence must record target path, source routing commit,
activation timestamp, OpenCode version, and resolved effective routing.

The workstation ambiguity was resolved by the redacted activation preflight in
`2026-09-03-activation-preflight.md`. The current selector now resolves the
canonical JSONC target unambiguously. This normalization preserves the
pre-Phase-R routing and does not itself begin activation.

## Historical decisions

This dated record resolves the earlier approved `low/medium` alternatives
without rewriting the historical V3.4.3 decision. Codex migration remains an
explicit risk decision, not a capability-failure claim.

## Scope

Production `opencode.jsonc`, production agent definitions, real user-global
configuration, and all Phase-0 gates remain unchanged. No model calls, Phase-R
execution, Phase 3, or Phase 4 occurred in this closure.
