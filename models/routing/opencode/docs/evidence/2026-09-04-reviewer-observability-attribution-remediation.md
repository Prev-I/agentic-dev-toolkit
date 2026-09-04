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
Phase R: BLOCKED_REVIEWER_RERUN (status at the time this document was written)
```

Not `BLOCKED_REVIEWER` (the prior status), and not PASS. The distinction
matters: the Reviewer fixture and scorer are now mechanically admissible
(everything below is proven offline), but a fresh, complete live 5/5 +
clean-zero rerun was, at the time this document was written, still
believed required before Phase R could close. Build, Explore, Compaction,
routing resolution, and security/permission boundaries are unaffected and
remain PASS.

**Superseded 2026-09-04 by the
[Phase-R scope amendment](../decisions/2026-09-04-phase-r-scope-amendment.md):**
that live rerun turned out not to be required at all. The amendment
separates restoration from optimization and reclassifies this whole
benchmark — unchanged threshold, fixture, and scorer, all the hardening
below fully retained — as Phase-3 quality evidence rather than a Phase-R
gate. Phase R now gates Reviewer's *operational* integration, which was
already evidenced without any of this remediation's work. This section is
preserved as the historical record of what was believed true when this
document was written, not rewritten to claim the amendment existed then.

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
   attribution. Stated precisely (corrected after independent review, see
   [Independent review findings](#independent-review-findings)):
   `fixture-integrity-test.sh` proves these files trigger none of the 8
   detectors in `FIXTURE_KNOWN_CHECKS` — but only ONE detector each is
   currently defined for `authorization.sh`/`counter.sh`, so this means
   "no other KNOWN defect class has a detector here yet", not "nothing
   else could possibly be wrong". This does **not** protect against a
   hallucinated, unrelated finding; that residual risk is real, weaker
   than for the witness-bearing files, and explicitly not claimed to be
   closed.

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

**Known, accepted, explicitly-asserted residual limitation**, widened
after independent review (see
[Independent review findings](#independent-review-findings)): a finding
whose evidence quotes the *entire* line legitimately contains the witness
too — but so can a **sub-line** quote about a genuinely different concern
that happens to overlap the witness's position, since every fixture file
is a single line packing multiple concerns closely together. Two dedicated
tests assert this: the whole-line case (R-BOUNDARY), and a reconstructed
sub-line coincidental match (R-API: a hallucinated JSON-injection finding
whose natural targeted quote, `json.dumps({"name": ...})`, happens to
contain the witness `{"name"`). Both are currently `detected` — not
hidden, not silently tolerated. Closing this fully would require
restructuring the fixture files so each concern occupies a
separately-quotable region (e.g. multi-line functions), out of scope for
this task.

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

## Independent review findings

Before finalizing, the full branch was sent to an adversarial independent
review (a fresh agent with no access to earlier drafts). It reproduced the
contract check, the witness derivation, and the admission gate itself
(mutating scratch copies, not the real fixture), and probed the scorer
with hand-built findings rather than trusting the tests. It found six real
issues, all fixed before this document was finalized:

```text
Moderate -- clean/api_contract.sh used Python's `assert`, stripped
    entirely under PYTHONOPTIMIZE=1/-O, silently defeating the contract
    check (and a plausible lint finding in its own right, risking a false
    positive in the zero-tolerance clean control). Fixed: explicit
    sys.exit(0/1), verified PYTHONOPTIMIZE=1 still detects the violation.

Moderate -- R-ERROR's witness ("2>/dev/null") anchored the non-causal half
    of its mutation. storage.sh's actual seeded defect is the RETURN-CODE
    masking ("|| printf '[]'"); a finding purely about stderr suppression,
    explicitly disclaiming the return-code issue, was wrongly credited.
    Fixed: witness re-anchored to "|| printf '[]", the causal substring.
    (This fix also exposed and fixed a real bash quoting bug in
    reviewer-runner-test.sh's fake dispatch scripts, unrelated to the
    scorer itself.)

Moderate -- the R-AUTH/R-CONCURRENCY file+severity justification was
    overstated ("none of the other 9 detector classes apply" -- both the
    count and the framing were wrong: only ONE detector is defined for
    each of these files, so integrity proves "no other KNOWN class has a
    detector yet", not "nothing else could be wrong"). Corrected wording
    throughout; no behavior change, since the actual scoring rule was
    already file+severity for these two.

Moderate -- reviewer.sh's load_witness silently returned None on any read
    failure (missing/malformed ground-truth.json), identical to "this case
    has no witness" -- so witness enforcement silently vanished for EVERY
    case whenever oracle.json was used detached from its fixture tree
    (reproduced: 5 fully hallucinated findings scored "pass" against a
    detached oracle.json copy, "block" against the real one, same
    findings, no diagnostic). Fixed: an UNREADABLE sentinel distinguishes
    "genuinely no witness" from "could not determine", and the latter now
    fails closed with a loud stderr warning.

Low -- evidence that is present but not a string (e.g. a list) could match
    a witness via Python's implicit str() containing the substring. Fixed:
    requires isinstance(evidence, str).

Low -- an empty-string witness ("witness": "") is a substring of every
    string in Python, so it would match any evidence at all; the admission
    gate silently skipped validating it instead of rejecting it. Fixed:
    routed through the same UNREADABLE/fail-closed path in the scorer, and
    treated as an integrity violation (refuses admission) in the gate.
```

The review's broader framing correction, also incorporated: the original
"3/5 sound, 2/5 open" scorecard understated how the 3 witness-bearing
cases actually differ. After the fixes above, the honest scorecard is:

```text
R-BOUNDARY: solid -- witness-anchored, no coincidental-match failure mode
            found (the guard and the boundary comparison are adjacent but
            distinguishable substrings)
R-ERROR:    solid, as of the witness re-anchoring fix above -- was
            previously anchored to the wrong half of its own mutation
R-API:      witness-anchored and causally correct, but demonstrably
            defeated by the most natural targeted quote for a plausible
            unrelated concern (JSON-injection) in the same line -- a real,
            disclosed, unresolved gap, not claimed to be solid
R-AUTH, R-CONCURRENCY: open, unchanged -- file+severity only, weaker
            justification than originally stated (see above)
```

Still not `REVIEWER_SCORING_ARCHITECTURE_BLOCKED`: two cases are now
genuinely solid, one is a real, disclosed, narrower gap rather than an
unsolved problem, and two are honestly reported as open. Every issue the
review found was a bug in this task's own implementation or documentation,
not evidence that the underlying design is unsound.

## Reviewer fixture/scorer revision

```text
R-API observability fix:            913e337
Admission-gate wiring (R-API):      913e337
Witness attribution fix:            befaa26
Admission-gate wiring (witness):    59bcacf
R-ERROR witness correction:         9922d3e
api_contract.sh assert->exit fix:   74feae6
Scorer/admission fail-open fixes:   bbe9af2
Documentation accuracy corrections: d85756b
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
    status: NOT_REQUIRED_FOR_PHASE_R / NOT_AUTHORIZED (superseded 2026-09-04
                by the scope amendment -- was PENDING_HUMAN_APPROVAL when
                this document was written)
```

Not self-approved, and never was. Distinct from, and does not modify, the
historical 100/250 caps, which remain breached and unchanged. **Superseded
by the [scope amendment](../decisions/2026-09-04-phase-r-scope-amendment.md)**:
the derivation and arithmetic above remain accurate, but the rerun this
tranche would have funded is no longer needed to close Phase R, since the
benchmark it targets is no longer a Phase-R gate. No live spend was ever
authorized against this proposal, and none is authorized now. If a future
Phase-3 Reviewer evaluation is opened, its own budget must be proposed and
approved at that time.

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
    per-seed result (corrected after independent review -- see
                     "Independent review findings"):
        R-BOUNDARY:    SOLID -- witness-anchored, verified adversarially
                        including the exact historical regression, no
                        coincidental-match failure mode found
        R-ERROR:       SOLID, as of the witness re-anchoring fix -- was
                        initially anchored to the non-causal half of its
                        own mutation (independent review finding, fixed)
        R-API:         WITNESS-ANCHORED but DEMONSTRABLY DEFEATABLE -- a
                        plausible unrelated finding's natural targeted
                        quote coincidentally overlaps the witness (verified
                        adversarially, disclosed explicitly, not claimed
                        solid)
        R-AUTH:        file+severity only -- no witness exists (pure
                        removal); residual hallucination risk explicit,
                        not closed; justification narrower than originally
                        stated (only 1 detector defined for this file)
        R-CONCURRENCY: file+severity only -- no witness exists (pure
                        removal + one non-meaningful incidental token);
                        same narrower justification as R-AUTH
    single-wrong-finding regression result: FIXED and SOLID for 2/5 seeds
                        (R-BOUNDARY, R-ERROR), a real but narrower gap for
                        1/5 (R-API), OPEN (documented, not hidden) for 2/5
                        (R-AUTH, R-CONCURRENCY)
    adversarial tests: PASS (full required matrix, all 5 seeds covered,
                        plus the coincidental-match case independent review
                        surfaced)
    architecture-blocked: NO (2 cases genuinely solid, 1 case a disclosed
                        narrower gap rather than unsolved, 2 cases honestly
                        reported open; not a weak universal approximation)

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
    proposed tranche: 340 credits, NOT_REQUIRED_FOR_PHASE_R / NOT_AUTHORIZED
                       (superseded by the 2026-09-04 scope amendment; was
                       PENDING_HUMAN_APPROVAL when this document was written)
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
                                    (status when this document was written;
                                    superseded 2026-09-04 -- Phase R is now
                                    PASS under the amended, operational-
                                    restoration gate set -- see the scope
                                    amendment)
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
