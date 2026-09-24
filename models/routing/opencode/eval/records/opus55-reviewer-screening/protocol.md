# Claude Opus 5.5 vs Opus 5 Reviewer Screening

Approved in chat on 2026-09-24 with a 500-credit ceiling. The experiment asks
whether `github-copilot/claude-opus-5.5` high should replace the current
Reviewer target, `github-copilot/claude-opus-5` high.

## Frozen Protocol

- Provider: GitHub Copilot for both models.
- Incumbent: Claude Opus 5 high.
- Challenger: Claude Opus 5.5 high.
- One challenger capability probe with the exact response `CAPABILITY_OK`.
- Use the unchanged Reviewer prompt, five seeded-defect cases, clean control,
  fixture-integrity check, normalization, witness attribution, and deterministic
  scorer.
- Required functional threshold: independently detect all 5 seeded defects and
  report zero material/blocking findings on the clean control.
- Run 12 workload calls: one complete six-case corpus per model. Alternate model
  order by case: clean Opus 5/5.5; R-API 5.5/5; R-AUTH 5/5.5; R-BOUNDARY 5.5/5;
  R-CONCURRENCY 5/5.5; R-ERROR 5.5/5.
- OpenCode 1.18.31 cannot directly execute a subagent, and the loaded Reviewer
  markdown definition overrides an inline mode change on the same agent name.
  Isolated configuration fragments therefore add experiment-only primary agents
  with the same Reviewer prompt, read-only permissions, temperature, model, and
  variant. The live config is not modified.
- Reject any call whose raw stream contains a subagent fallback warning.
- Capability admission projection: 20 credits. Workload admission projection:
  40 credits per call. Reconcile after each call and stop on provider/environment
  failure, unknown cost, or failed admission.
- Functional quality decides first. Timing and observed credits may distinguish
  models only if both clear 5/5 plus clean-zero.
- One attempt per model per case; no retries, replacement cases, extra workloads,
  routing changes, commits, or pull requests.
- Retain raw streams, responses, parsed findings, normalized corpus findings,
  scorer attribution, timing, tokens, and credits.

## Provenance

- Repository commit: `d22c8d81aa5e7360f305a3347cb940d35d7fe06a`
- OpenCode runtime: `1.18.31`
- Execution date: `2026-09-24`

## Discovery

Both model IDs expose the `high` variant. Catalog prices per million tokens:

| Model | Input USD | Output USD | Cache read USD | Cache write USD |
|---|---:|---:|---:|---:|
| Claude Opus 5 | 5 | 25 | 0.5 | 6.25 |
| Claude Opus 5.5 | 4 | 20 | 0.2 | 5 |

Discovery is not capability evidence. Credits are runtime-reported USD times
100 and are not reconciled with the GitHub billing interface.
