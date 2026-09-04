# Reviewer Observability & Attribution Remediation — 2026-09-04

Follow-up to
[the Reviewer fixture-integrity remediation](2026-09-04-reviewer-fixture-integrity-remediation.md).
That work fixed the pagination fixture defects, an admission gate, and
2+-finding scorer ambiguity, but left two gate-soundness issues open:
the R-API observability defect, and single-wrong-finding scorer
attribution. This task closes both, **offline, with zero live model calls
and zero additional AI credits**.

## Phase R status

```text
Phase R: BLOCKED_REVIEWER_RERUN
```

Not `BLOCKED_REVIEWER` (the prior status), and not PASS. The distinction
matters: the Reviewer fixture and scorer are now mechanically admissible
(everything below is proven offline), but a fresh, complete live 5/5 +
clean-zero rerun is still required, and no rerun budget is yet approved.
Build, Explore, Compaction, routing resolution, and security/permission
boundaries are unaffected and remain PASS.

## Budget status (unchanged by this task)

```text
evaluation: >=289.01 / 100 -- BREACHED (floor)
recovery:   349.94 / 250   -- BREACHED (accurate)
remaining evaluation budget: 0
remaining recovery budget:   0
additional live spend authorized: 0
additional live spend this task:  0
```

The historical caps were not retroactively changed. The previously
proposed 238-credit tranche is **superseded by the corrected proposal
below** (see [Future Reviewer gate](#future-reviewer-gate)) — it is
withdrawn, not silently left standing alongside a new number.

## Part 1: R-API observability

### Old failure

The seeded ground truth ("documented public displayName field renamed
without compatibility handling") required knowledge that existed only in
`cases/R-API/ground-truth.json` — the hidden answer key, never copied into
any sandbox. `grep -rn displayName` over the entire persisted historical
R-API dispatch tree returned zero matches. `FIXTURE_DEFECT`, confirmed in
the prior remediation.

### New visible contract witness

`eval/fixtures/reviewer-seeded-defects/clean/api_contract.sh`:

```bash
assert_public_response_contract() { local response; response=$(public_response "$1"); python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "displayName" in d, "public contract violation: displayName missing from public_response"' "$response"; }
```

A downstream consumer's contract expectation — the kind of artifact a real
API fixture would carry — not prose asserting a verdict, and not the seed
ID. It lives in `clean/`, never overridden by R-API's `ground-truth.json`
(`overrides: ["api.sh"]` only), so it survives unmodified into R-API's
sandbox via the fixture's existing base+overrides architecture. No change
to `run-reviewer-gate.sh`'s sandbox construction was needed — it already
copies every `clean/*.sh` file. The Reviewer must still read `api.sh`, read
the contract, and reason about the mismatch itself; nothing states the
verdict.

### Fixture integrity result

```text
clean contract:      PASS (clean/api.sh satisfies its own declared contract)
R-API contract:      FAILS for exactly the intended rename incompatibility
                      (cases/R-API/api.sh does not)
fixture integrity:   exactly R-API's seed present; zero unintended defects
```

`api_violates_public_contract` (`eval/scoring/fixture-defect-detectors.sh`)
proves this mechanically, using the same constructed-sandbox pairing
(`clean/api_contract.sh` + the `api.sh` actually present) every live
dispatch uses — not the override file in isolation, since this defect is
only observable in combination. Wired into `fixture_integrity_check`, the
existing admission gate.

### TDD

`eval/tests/r-api-contract-test.sh`, RED (`1ae68dd`) before the fix — proves
no file in `clean/` other than `api.sh` mentions `displayName` — GREEN
(`913e337`) after. Adversarially verified: deleting the witness file, and
silently repairing R-API's override to emit both field names (satisfying
the contract while removing the defect), both correctly fail
`fixture-integrity-test.sh`.

## Part 2: scorer attribution from first principles

### The actual Reviewer output contract (documented, not assumed)

```json
{"findings":[{"file":"<file name>","severity":"blocking|material|suggestion","summary":"<one sentence>"}]}
```

Three fields: `file`, `severity`, `summary` (one-sentence natural language).
No `line`, `span`, `category`, or `evidence` field existed before this task.
This is the **eval-only dispatch contract** (`run-reviewer-gate.sh`'s
`reviewer_request()`), distinct from the production
`.opencode/agents/reviewer.md` prompt — Section 8 of this task's brief
explicitly permits extending it; Section 0 forbids touching the production
prompt, and this task does not.

### Investigation: is deterministic per-seed witness anchoring achievable?

Inspected the exact literal diff between `clean/` and each case's override:

| Case | Mutation shape | Literal token present in override, absent from clean? |
|---|---|---|
| R-API | substitution (`"displayName"` → `"name"`) | Yes: `{"name"` |
| R-BOUNDARY | substitution (`>= 1` → `>= 0`) | Yes: `10#$1 >= 0` |
| R-ERROR | addition (`2>/dev/null \|\| printf '[]\n'` appended) | Yes: `2>/dev/null` |
| R-AUTH | pure removal (the ownership guard deleted outright) | **No** — verified the override is a strict character-range deletion from clean; nothing new appears anywhere |
| R-CONCURRENCY | removal + incidental rewrite (locking removed) | One incidental new token, `local n` — verified present in override, absent from clean — but this is a refactor artifact, not the semantically meaningful evidence of the mutation (the meaningful fact is the *absence* of locking, not the presence of a local-variable declaration). Using it as a witness would be an arbitrary hack a genuine finding has no natural reason to quote. |

**Result: partial, principled soundness.** Three of five seeds (R-API,
R-BOUNDARY, R-ERROR) admit a genuine, mechanically-derivable witness
substring. Two (R-AUTH, R-CONCURRENCY) do not, because their mutations are
pure removals of safety logic — there is nothing *added* for a witness to
anchor to, without leaking the answer or restructuring the fixture.

This is not `REVIEWER_SCORING_ARCHITECTURE_BLOCKED` in the full sense: a
real, deterministic improvement is achievable and implemented for 3/5
cases. It is also not a silent generalization of that success to the
other 2/5 — their limitation is stated explicitly below, per this task's
own instruction to say so rather than hide it.

### Design: witness-based deterministic attribution

1. **Eval-only contract extended** (`run-reviewer-gate.sh`'s
   `reviewer_request()`) with an `evidence` field: *"the exact smallest
   snippet of code from the file that demonstrates the issue, quoted
   verbatim"*. No seed ID, no category taxonomy, no mention of "R-API" or
   any other seed name is ever requested or shown to the model — the model
   reports normal review evidence, unaware a taxonomy exists.

2. **Witnesses computed mechanically**, stored in each witness-bearing
   case's `ground-truth.json` (`"witness"` field) — never hand-authored
   prose, always the literal diff-derived substring, self-verified by
   `reviewer-witness-attribution-test.sh` against the actual file contents
   (present in override, absent from clean).

3. **Scorer** (`eval/scoring/reviewer.sh::reviewer_structured_gate`): for a
   witness-bearing case, a finding only counts toward attribution if its
   `evidence` field contains the witness substring — **exact string
   containment, not fuzzy or semantic matching, not an LLM judge**. Zero
   matching: missed. Exactly one: detected. Two or more: fails closed as
   ambiguous, same doctrine as the prior fix for 2+ file-matching findings.
   No `evidence` field at all: treated as non-matching, fails closed.

4. **Non-witness cases (R-AUTH, R-CONCURRENCY)** keep file+severity
   attribution — justified specifically because `fixture-integrity-test.sh`
   mechanically proves each of these files carries exactly one known
   material defect and none of the other 9 detector classes apply. This
   does **not** protect against a hallucinated, unrelated finding; that
   residual risk is real and explicitly not claimed to be closed.

### Adversarial test matrix (per Section 10's exact requirement list)

`eval/tests/reviewer-witness-attribution-test.sh` (witness cases) and the
rewritten `eval/tests/reviewer-attribution-test.sh` (non-witness cases,
using R-AUTH as the example):

```text
correct finding                              -> credited
unrelated material finding, another file      -> not credited (missed)
unrelated material finding, same file         -> not credited (missed)
correct file, wrong behavior (no witness overlap) -> not credited
no finding                                    -> missed
multiple findings, only one correct           -> credited exactly once
multiple material findings, none correct      -> missed
```

**The exact historical R-BOUNDARY regression** (Section 10's explicit
requirement), reconstructed from the real dispatch's
`response.txt` — summary about leading-zero octal reinterpretation, evidence
quoting the regex/arithmetic guard, zero mention of the `>= 0` boundary —
is asserted **NOT DETECTED**. Confirmed.

**Known, accepted, explicitly-asserted residual limitation**: a finding
whose evidence quotes the *entire* line rather than a targeted snippet
legitimately contains the witness too, since it's a genuine substring of
that line in the vulnerable sandbox. A dedicated test asserts this exact
scenario is currently `detected` — not hidden, not silently tolerated.
Closing it fully would require restructuring the fixture files so each
concern occupies a separately-quotable region (e.g. multi-line functions),
which is out of scope for this task.

## Admission gate: scorer soundness added

Per Section 13, the admission chain is now:

```text
fixture defect integrity
    ->
scorer attribution (witness) integrity
    ->
live dispatch permitted
```

`fixture_integrity_check` now also verifies, for every witness-bearing
case, that the witness genuinely discriminates (present in override,
absent from clean) — before any live dispatch. Without this, a witness
that drifted stale would silently make attribution always fail closed for
that case, discoverable only after spending credits on a run that could
never pass. Adversarially verified: a witness no longer present in its
override, and a witness that leaked into `clean/`, both correctly refuse
admission, with zero sandbox created and zero credits spent.

## Reviewer fixture/scorer revision

```text
R-API observability fix:       913e337
Admission-gate wiring (R-API): 913e337
Witness attribution fix:       befaa26
Admission-gate wiring (witness): 59bcacf
```

## Historical Reviewer evidence

Unchanged from the prior remediation: all historical Reviewer runs
(`reviewer-run-1-pre-fixture-fix/`, `reviewer/pre-i2-fix/`, `reviewer/`)
remain retained as diagnostic evidence, marked
`phase_r_reviewer_quality_evidence: "invalidated by fixture defect"`. None
were recovered, re-scored, or reused by this task. A future valid Reviewer
gate rerun must restart from zero (5 seeded cases + clean control, one
uninterrupted run) against the current fixture/scorer revision.

## Future Reviewer gate

```text
required dispatches: 6 (5 seeded + 1 clean control) -- unchanged, derived
    from run_reviewer_gate's per-case dispatch loop, one live call per case
model/variant: github-copilot/gpt-5.6-sol, high (unchanged production target)
```

### Corrected cost model

14 real, healthy historical dispatches at this exact target: mean 34.03
credits/dispatch, range 22.54–48.47.

| Basis | Credits (6 dispatches) |
|---|---:|
| Low (min × 6) | 135.2 |
| Central (mean × 6) | 204.2 |
| **High/ceiling (max × 6)** | **290.8** |

**Correcting an internal inconsistency in the prior remediation's
proposal**: it stated this same 135–291 range, then proposed a 238-credit
tranche — below the stated 291 ceiling, so it could not simultaneously
claim to cover the full range plus any replacement allowance. That
proposal is withdrawn.

### Corrected proposal

```text
reviewer_remediation_rerun_budget:
    requested: 340 credits
    derivation: 7 dispatches (6 required + 1 environment-invalid
                replacement allowance, grounded in this session's own
                ~10% observed content-quality retry rate across ~20
                real dispatches), EACH priced at the observed historical
                ceiling (48.47 credits), not the mean -- so the tranche
                remains internally consistent even if every dispatch in
                a run, including the retry, lands at the historical high
                end: 7 x 48.47 = 339.3, rounded up to 340.
    scope: covers ONLY a fresh, complete Reviewer gate restart (5 seeded
                cases + clean control) plus the one bounded
                INVALID_ENVIRONMENT replacement allowance -- no Phase 3,
                no unrelated experimentation, no effort-level exploration
    status: PENDING_HUMAN_APPROVAL
```

Not self-approved. Distinct from, and does not modify, the historical
100/250 caps, which remain breached and unchanged. No new live dispatch
may occur until this tranche is explicitly approved.

## Final classification matrix

```text
R-API:
    old observability failure: CONFIRMED (displayName never observable)
    new visible contract witness: PASS (clean/api_contract.sh, verified)
    fixture integrity result: PASS (exactly R-API's seed, contract violated
                                     only in R-API's sandbox)

scorer:
    current output interface: file, severity, summary (eval-only contract
                               now also: evidence)
    deterministic attribution design: witness-substring containment for
                               addition/substitution mutations
    per-seed result:
        R-API:         WITNESS-ANCHORED, sound (verified adversarially)
        R-BOUNDARY:    WITNESS-ANCHORED, sound (verified adversarially,
                        including the exact historical regression)
        R-ERROR:       WITNESS-ANCHORED, sound (verified adversarially)
        R-AUTH:        file+severity only -- no witness exists (pure
                        removal); residual hallucination risk explicit,
                        not closed
        R-CONCURRENCY: file+severity only -- no witness exists (pure
                        removal + one non-meaningful incidental token);
                        residual hallucination risk explicit, not closed
    single-wrong-finding regression result: FIXED for 3/5 seeds, OPEN
                        (documented, not hidden) for 2/5
    adversarial tests: PASS (full required matrix, all 5 seeds covered)
    architecture-blocked: NO (partial, principled soundness achieved;
                        not a weak universal approximation)

admission gate:
    fixture integrity: PASS
    R-API observability integrity: PASS
    scorer/witness integrity: PASS
    dispatch prevention result: PASS (adversarially verified refusal,
                        zero sandbox created, zero credits spent, for
                        both a broken fixture and a stale witness)

Reviewer fixture/scorer revision: 913e337, befaa26, 59bcacf

historical Reviewer evidence: inadmissible, confirmed, unchanged, not
                        recovered by this task

future gate:
    dispatch count: 6
    model/variant: github-copilot/gpt-5.6-sol, high
    central estimated credits: 204.2
    upper estimated credits: 290.8
    invalid-environment allowance: 1 dispatch, priced at the ceiling
    proposed tranche: 340 credits, PENDING_HUMAN_APPROVAL
```

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
35/35 PASS (33 from the prior remediation + r-api-contract-test.sh +
             reviewer-witness-attribution-test.sh)

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check main...HEAD
(clean, no whitespace errors)
```

Confirmed:

```text
live model calls this task:        0
additional AI credits this task:   0
production routing:                unchanged
global OpenCode config:            unchanged
Build/Explore/Compaction evidence: unchanged (no files under those paths
                                    touched in this branch's commit range)
Phase R:                           BLOCKED_REVIEWER_RERUN, not PASS
Phase 3:                           not started
Phase 4:                           not started
```

Every change followed the same discipline as the prior remediation: root
cause / architecture investigated before any implementation
(systematic-debugging), RED test committed before each fix
(test-driven-development), adversarial mutation verification after, and
full-suite + install-suite verification before considering the work done
(verification-before-completion). The single-wrong-finding limitation for
R-AUTH/R-CONCURRENCY was investigated rigorously and reported honestly as
open, rather than papered over with a fuzzy heuristic or a false claim of
universal soundness.
