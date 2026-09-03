# OpenCode V1 Phase 0 Readiness - 2026-09-03

## Outcome

Every required Phase-0 gate is `PASS`. Phase 0 is complete as an evidence and
readiness stage. This does not authorize or start Phase R.

## Gate matrix

| Gate | Status | Evidence |
|---|---|---|
| Candidate model capability | `PASS` | `2026-09-02-phase-0-capability-matrix.md` |
| Variant/effort capability | `PASS` | `2026-09-02-phase-0-capability-matrix.md` |
| Agent inventory | `PASS` | `2026-09-02-phase-0-capability-matrix.md` |
| Reviewer permissions | `PASS` | `eval/records/reviewer-permissions.json` |
| Expert permissions | `PASS` | `eval/records/expert-permissions.json` |
| Breakglass normal-agent non-exposure | `PASS` | `eval/records/breakglass-normal-agent-non-exposure.json` |
| Breakglass human-primary execution | `PASS` | `eval/records/breakglass-primary-attempt-2026-09-03.json` |
| Evaluation budget | `PASS` | `eval/manifests/phase-0-budgets.json` |
| Phase-R recovery budget | `PASS` | `eval/manifests/phase-0-budgets.json` |
| Harness self-variance | `PASS` | `eval/records/self-variance/summary.json` |
| Continuous thresholds | `PASS` | `eval/thresholds/continuous.json` |
| Eval provenance | `PASS` | `eval/records/self-variance/attempt-*.json` |
| Installed-profile manifest | `PASS` | `eval/manifests/installed-profile.json` |
| Build restoration fixture/state rules | `PASS` | `eval/fixtures/build-workloads/build-restoration-gate/fixture.json` |
| Reviewer clean control | `PASS` | `eval/fixtures/reviewer-seeded-defects/fixture.json` |
| Compaction invariants | `PASS` | `eval/fixtures/compaction-invariants/fixture.json` |
| Governance | `PASS` | `2026-09-02-governance-blockers.md` |
| Sol pricing-regime handling | `PASS` | `2026-09-02-phase-0-capability-matrix.md` |

## Decisions and measurements

- Approved evaluation budget: `100` credits.
- Approved, separately reserved Phase-R recovery budget: `250` credits.
- Organizational user guardrail: `7600` credits per billing cycle, externally
  enforced; no OpenCode-native cap or automatic cheaper fallback.
- Self-variance: three valid Luna-low runs, zero invalid runs, `0.311881`
  derived credits, `31980` tokens.
- Frozen wall-clock threshold: `37.8885%`.
- Frozen comparable-credit threshold: `2194.8831%`, reflecting observed
  cold-vs-warm cache variance.
- Breakglass normal boundary: resolved permission and inventory evidence;
  prompt behavior was not used as the oracle.
- Breakglass positive boundary: explicit direct OpenAI primary selection and
  exact response succeeded on the single approved retry.

The installed-profile manifest passes as the ordinary-session provenance schema
and ceiling record. `installed_at` remains null because this closure did not
install or activate a production profile.

## Remaining blockers

No Phase-0 gate remains blocked. Phase R still requires a separate explicit
start decision and must follow its committed fixture, state, and recovery rules.
This record is not that authorization.

Production routing and production agent definitions remain unchanged. Phase R,
Build A/B, Reviewer effort experiments, and Phase-4 Expert experiments were not
started.
