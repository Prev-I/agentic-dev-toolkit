# OpenCode V1 Phase 0 Readiness - 2026-09-03

## Outcome

Every required Phase-0 gate is `PASS`. Phase 0 is complete as an evidence and
readiness stage. This does not authorize or start Phase R.

## Gate matrix

| Gate | Status | Evidence | Rationale |
|---|---|---|---|
| Candidate model capability | `PASS` | `2026-09-02-phase-0-capability-matrix.md` | Required candidates completed explicit calls. |
| Variant/effort capability | `PASS` | `2026-09-02-phase-0-capability-matrix.md` | Required variants completed explicit calls. |
| Agent inventory | `PASS` | `2026-09-02-phase-0-capability-matrix.md` | Expected V1 agents and modes were recorded. |
| Reviewer permissions | `PASS` | `eval/records/reviewer-permissions.json` | Resolved permissions enforce the read-only boundary. |
| Expert permissions | `PASS` | `eval/records/expert-permissions.json` | Resolved permissions deny mutation, delegation, shell, and web access. |
| Breakglass normal-agent non-exposure | `PASS` | `eval/records/breakglass-normal-agent-non-exposure.json` | Resolved Task rules deny Breakglass and inventory marks it primary. |
| Breakglass human-primary execution | `PASS` | `eval/records/breakglass-primary-attempt-2026-09-03.json` | Explicit primary execution returned the exact expected response. |
| Evaluation budget | `PASS` | `eval/manifests/phase-0-budgets.json` | The human owner approved 100 credits. |
| Phase-R recovery budget | `PASS` | `eval/manifests/phase-0-budgets.json` | The human owner reserved 250 non-reclaimable credits. |
| Harness self-variance | `PASS` | `eval/records/self-variance/summary.json` | Three valid non-candidate runs passed all consistency checks. |
| Continuous thresholds | `PASS` | `eval/thresholds/continuous.json` | Thresholds derive from previously committed self-variance evidence. |
| Eval provenance | `PASS` | `eval/records/self-variance/attempt-*.json` | Every measured run records the required runtime and usage fields. |
| Installed-profile manifest | `PASS` | `eval/manifests/installed-profile.json` | Schema and provenance ceiling are recorded without activation. |
| Build restoration fixture/state rules | `PASS` | `eval/fixtures/build-workloads/build-restoration-gate/fixture.json` | Mechanical oracle and immutable state rules are committed and tested. |
| Reviewer clean control | `PASS` | `eval/fixtures/reviewer-seeded-defects/fixture.json` | Seeded and clean controls provide grounded denominators. |
| Compaction invariants | `PASS` | `eval/fixtures/compaction-invariants/fixture.json` | Tagged invariants use exact N/N preservation. |
| Governance | `PASS` | `2026-09-02-governance-blockers.md` | Local ownership and external-control boundaries are resolved. |
| Sol pricing-regime handling | `PASS` | `2026-09-02-phase-0-capability-matrix.md` | Promotional observations cannot become canonical steady-state cost. |

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
  exact response succeeded on the single closure attempt following the
  preserved historical failure.

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
