# Reviewer Root-Cause & Fixture Integrity Remediation — 2026-09-04

Offline remediation following the I1/I2 corrections recorded in
[`2026-09-04-phase-r-execution.md`](2026-09-04-phase-r-execution.md). This
task performed **zero live model calls and zero additional AI-credit
spend** — every finding below comes from repository contents, persisted raw
evidence, local shell/Python execution, and mechanical tests.

## Phase R status

```text
Phase R: BLOCKED_REVIEWER
```

Unchanged by this task. Build, Explore, Compaction, routing resolution, and
security/permission boundaries (including Breakglass) remain PASS and were
not re-run. This task does not rerun the Reviewer gate and does not restore
a PASS claim — see [Future Reviewer gate](#future-reviewer-gate) for what a
valid rerun requires.

`operational_state: active-provisional` — the restored routing profile
remains installed and active on the real, user-global OpenCode
configuration; that activation is untouched by this task (verified: the
live config file's mtime is unchanged since its Task-16 activation).
`canonical_quality_reference: false`, unchanged.

## Budget status

```text
evaluation_budget:
    approved: 100
    observed: >=289.01
    status: BREACHED
    confidence: FLOOR (6 of the underlying dispatches have no recoverable
                        raw evidence; the true total is higher)

recovery_budget:
    approved: 250
    observed: 349.94
    status: BREACHED
    confidence: COMPLETE_FOR_RECOVERABLE_CURRENT_LEDGER (no unrecoverable
                        entries in this account)

remaining_evaluation_budget: 0
remaining_recovery_budget: 0
additional_live_spend_authorized: 0
additional_live_spend_this_task: 0
```

Historical caps (`eval/manifests/phase-0-budgets.json`: 100 / 250) were
**not** retroactively changed — confirmed via `git log`, one commit, never
touched again. The breach is recorded, not erased.

**Distinct control, not conflated**: the organizational 7,600-credit
guardrail is a separate control (external, GitHub-billing-enforced). No
evidence in this repository shows that guardrail breached — the corrected
evaluation+recovery total (~639 credits) stays under it. This document does
not claim otherwise.

### I1 final state

```text
root cause:          CONFIRMED
implementation fix:  PASS (dispatch-fixture.sh commit 505d35a; sums cost
                      across every step_finish event instead of overwriting)
historical correction: COMPLETE for 17 of 25 dispatches with surviving
                      raw.jsonl; 8 dispatches PARTIAL/UNRECOVERABLE (raw
                      evidence was overwritten on disk by a later dispatch
                      reusing the same output directory before the bug was
                      found — their recorded credits are a floor, not a
                      true figure)
budget consequence:  BREACHED (both evaluation and recovery accounts, per
                      the corrected figures above)
```

No further action taken on I1 in this task — it was already fixed and
corrected before this task began. Restated here only for the classification
matrix's completeness.

## Investigation: the shared pagination bug

### Reproduction

`eval/tests/decimal-pagination-test.sh` (committed RED in `a157136`, GREEN
after the fix in `d9d6235`) exercises `clean/pagination.sh`'s
`validate_page_size` against the required domain table:

| Input | Required | Pre-fix actual | Post-fix actual |
|---|---|---|---|
| `0` | reject | reject | reject |
| `1` | accept | accept | accept |
| `8` | accept | accept | accept |
| `08` | accept (decimal 8) | **crash** (bash arithmetic error) | accept |
| `99` | accept | accept | accept |
| `100` | accept | accept | accept |
| `101` | reject | reject | reject |
| `0144` | reject (decimal 144 > 100) | **accept** (wrong) | reject |
| `-1`, `1x`, `abc`, `''` | reject | reject | reject |

### Root cause

Confirmed via `man bash`, ARITHMETIC EVALUATION section, quoted directly:

> "Constants with a leading 0 are interpreted as octal numbers."

`clean/pagination.sh`'s guard, `[[ "$1" =~ ^[0-9]+$ ]]`, only proves the
input is composed entirely of decimal-digit *characters*; it says nothing
about how bash's own `(( ))` arithmetic evaluator will *parse* the string.
Direct reproduction (`bash -c '(( 0144 ))'` → `100`; `bash -c '(( 08 ))'` →
`bash: ((: 08: value too great for base`) confirms the mechanism exactly:
"0144" is octal 144 = decimal 100 (so the intended-invalid decimal 144
silently passes as if it were the in-range value 100), and "08"/"09"
contain digits invalid in octal (0–7 only), so the arithmetic evaluator
raises a shell error instead of ever reaching a decimal comparison. This is
not an LLM finding rediscovered after the fact — it was independently
reproduced from bash's own manual and direct execution before any fix was
written.

### Classification

**FIXTURE_DEFECT.** `clean/ground-truth.json` declares
`"known_material_defects": 0`; the fixture had one. This is a material bug
(a documented 1..100 boundary is silently bypassed) present in the shared
baseline every one of the six sandboxes (clean + 5 seeded cases) receives —
confirmed structurally: each `cases/<ID>/` directory contains **only** its
declared override file(s) (verified by `fixture-integrity-test.sh` and by
direct `ls`), so every non-override file, including `pagination.sh` for
every case except R-BOUNDARY, is supplied fresh from `clean/` at
sandbox-construction time (`run-reviewer-gate.sh`). There is no stale
hand-copied file that could have drifted independently — the defect's
blast radius is exactly "every sandbox," by the fixture's own declared
architecture, not by any additional propagation bug.

### Fix

Smallest decimal-safe change (`d9d6235`): bash's own `10#` base-prefix
notation, forcing explicit decimal interpretation regardless of leading
zeros — `(( 10#$1 >= 1 && 10#$1 <= 100 ))` — applied to `clean/pagination.sh`
and, because it is a genuine standalone override rather than a derived
copy, independently to `cases/R-BOUNDARY/pagination.sh` (preserving its own
seeded defect: lower bound `0` instead of `1`). No other case file needed
touching — confirmed by the same structural fact above.

### Regression tests

- `decimal-pagination-test.sh`: the full domain table, RED before the fix,
  GREEN after.
- `fixture-integrity-test.sh` (below): proves `clean/` and every case
  mechanically, not just `pagination.sh` in isolation.
- Adversarial verification: reintroducing the bug in `clean/`, and adding
  an unrelated second defect to a case override, both correctly fail.

## Fixture integrity

```text
clean:          PASS (zero known material defects, mechanically proven)
R-CONCURRENCY:  PASS (exactly its own seed, no other known defect)
R-AUTH:         PASS (exactly its own seed, no other known defect)
R-API:          PASS (exactly its own seed, no other known defect)
R-BOUNDARY:     PASS (exactly its own seed, no other known defect —
                 was FAIL before the pagination fix: carried its own
                 zero-boundary seed AND the inherited octal defect)
R-ERROR:        PASS (exactly its own seed, no other known defect)
```

`eval/scoring/fixture-defect-detectors.sh` implements one mechanical,
LLM-free detector per known, code-provable defect class (pagination
zero-boundary, pagination octal/leading-zero, api field-rename, api
JSON-injection, storage swallow-failure, auth ownership-bypass, counter
lacks-locking), each sourcing the target file in a subshell and exercising
it directly — no dispatch, no model. `eval/tests/fixture-integrity-test.sh`
asserts `clean/` triggers zero detectors and each case's override triggers
exactly its own seed's detector and no other. Committed RED in `98ec4e2`
(catching both the `clean/` and the `R-BOUNDARY` violation), GREEN after
the pagination fix in `d9d6235`.

**Permanent admission gate** (`610501c`): `run_reviewer_gate` now calls
`fixture_integrity_check` first and refuses to create a sandbox or spend a
single credit if the fixture fails its own integrity check — adversarially
verified by temporarily breaking the real committed `clean/pagination.sh`
(trap-guaranteed restore) and confirming the runner refuses with zero
output directory created.

## Reviewer scorer attribution

### Root cause

Traced the full credit path from raw finding to gate outcome:

```text
raw Reviewer finding (file, severity, one-sentence summary)
    -> adapter normalization (run-reviewer-gate.sh): filters findings to
       those whose file basename is in the case's override set, picks the
       HIGHEST SEVERITY one among matches
    -> findings.json: {"id", "severity", "summary", "files", "all_reported"}
    -> reviewer_structured_gate: detected = severity in material_severities
    -> gate credit
```

**Answering this remediation's own diagnostic question directly: can any
material finding in the sandbox satisfy the detection requirement, even if
it describes a different defect? YES.** Confirmed against the real
R-BOUNDARY rerun evidence
(`eval/records/phase-r/reviewer/R-BOUNDARY/dispatch/response.txt`): a
single material finding entirely about the (then-undiscovered) octal bug,
zero mention of the seeded zero-boundary defect, was credited as a
detection. `SCORER_DEFECT` confirmed.

### Fix — and its explicit, documented limit

`reviewer_structured_gate` (`3079235`) now credits a case only when
**exactly one** material/blocking finding is reported against its override
file(s), per `findings.json`'s own `all_reported`/`files` evidence. Zero
such findings: missed, as before. **Two or more: fails closed** ("ambiguous",
not credited) instead of silently picking the highest-severity one, which
discarded the ambiguity signal entirely. A new diagnostic companion,
`reviewer_structured_attribution`, reports the per-case classification
(`detected`/`missed`/`ambiguous`) instead of collapsing straight to
pass/block. Backward compatible with the simpler findings-shape used by
`reviewer-ground-truth-test.sh`'s synthetic fixtures (falls back to
trusting the top-level severity field directly when `all_reported`/`files`
are absent).

**This does not, and cannot, fix the actual shape of the real incident.**
R-BOUNDARY's live rerun had exactly **one** material finding against
`pagination.sh` — not two — and that one finding was about the wrong
defect. A single wrong finding and a single correct finding are the *same
input shape* to this scorer: `(file="pagination.sh", severity="material")`.
Re-scored directly against the archived evidence to confirm this
explicitly:

```text
$ reviewer_structured_attribution oracle.json eval/records/phase-r/reviewer/findings.json
{
  "R-API": "missed",
  "R-AUTH": "detected",
  "R-BOUNDARY": "detected",   <- still wrongly credited, confirmed
  "R-CONCURRENCY": "detected",
  "R-ERROR": "detected"
}
```

**Stopped, not worked around.** Fully solving single-finding attribution
requires either (a) an LLM semantic judge comparing the finding's prose
against the expected defect description — explicitly out of scope for this
remediation, or (b) a change to the Reviewer's own output contract (e.g., a
structured defect-identity or evidence-anchor field) so a future scorer
*could* attribute deterministically — which is a change to the Reviewer
prompt/contract, and this remediation is explicitly barred from tuning the
Reviewer prompt. Per this task's own Hard Stop conditions ("deterministic
attribution requires an LLM judge"), this is recorded as an **open
interface-limitation finding**, not silently patched around with a fuzzy
heuristic. **Recommendation for a future, separately-scoped task**: extend
the Reviewer output contract with a stable per-finding evidence anchor
(e.g., a quoted code span, or a short defect-class tag drawn from a fixed
vocabulary) that a deterministic scorer could match against — this is a
prompt/contract design decision requiring its own human review, not
something to bundle into this remediation.

### Tests

`eval/tests/reviewer-attribution-test.sh` (committed RED in `dbb40b2`, GREEN
in `3079235`), covering: single correct-file finding credited; single
correct-file finding with different wording still credited (file match is
the only structured identity this contract supports); no finding missed;
non-material-only finding missed; **the documented limitation, asserted
explicitly** (single wrong-content finding still credited — not hidden);
two conflicting findings (one correct, one wrong) now fails closed; two
findings, neither correct, fails closed via the identical mechanism;
backward-compatible legacy shape unaffected.

## R-API zero-signal investigation

Investigated entirely offline from persisted evidence in
`eval/records/phase-r/reviewer/R-API/` — no live model calls.

### Exact fixture delta (section 13)

```text
$ diff clean/api.sh cases/R-API/api.sh
< public_response() { ...json.dumps({"displayName": sys.argv[1]})... }
> public_response() { ...json.dumps({"name": sys.argv[1]})... }
```

Confirmed: the *only* difference is the field key. No other change, no
comment, no scope creep.

### Public-contract observability (section 14) — the deciding factor

Searched the **entire** fixture tree for any evidence that `displayName`
is a documented, compatibility-relevant public contract, visible to a
Reviewer with no external context:

```text
$ grep -rl "displayName" eval/fixtures/reviewer-seeded-defects/
cases/R-API/ground-truth.json    <- the hidden answer key; NEVER supplied
                                     to the Reviewer's sandbox
clean/api.sh                     <- a DIFFERENT sandbox than R-API's own
```

There is no README, schema, consumer, contract test, or comment anywhere
in the fixture. Critically: **the R-API sandbox itself never contains the
string "displayName" at all** — confirmed by listing the exact sandbox
contents captured at dispatch time
(`eval/records/phase-r/reviewer/R-API/sandbox/api.sh`, which reads
`"name"`, not `"displayName"`). A reviewer looking only at this sandbox has
no way — none — to learn that `"name"` used to be something else, because
nothing it can observe ever shows the old name.

**Classification: FIXTURE_DEFECT.** The ground truth's own claim ("public
displayName field renamed without compatibility handling") requires
knowledge that exists only in a hidden oracle file the Reviewer never
sees. Per this remediation's own stated rule: "the Reviewer cannot be
expected to infer hidden ground truth."

### Dispatch/response verification (sections 15–16), for completeness

Even though the classification is already determined by the observability
failure above, verified the remaining chain for due diligence:

- **Dispatch complete**: `api.sh` was present in the sandbox (confirmed by
  listing); `dispatch.json` shows `classification: OK`, `exit_status: 0`,
  no truncation events anywhere in `raw.jsonl`.
- **Context not materially truncated**: `wall_clock_ms: 108102` (~108s,
  nowhere near the 900s timeout); the raw tool-use trace shows the model
  actually sourcing and executing `api.sh` directly with adversarial
  injection payloads (`'Bob "the Builder"'`, `'","admin":true'`, a tab
  character).
- **Raw response genuinely contains zero signal for the rename** — not
  lost in parsing. `response.txt`'s own prose is explicit and unambiguous:
  > "**Verified correct (no findings):** `api.sh` — `json.dumps` correctly
  > escapes quotes and control chars; the value is passed as `argv`, not
  > interpolated into the Python source, so no injection. Confirmed with
  > `","admin":true` and tab payloads."

  The model deliberately tested `api.sh` for the injection class of defect
  (the *other* thing this file type is known to carry, per the earlier
  clean-control incident) and correctly found it safe. It had no basis to
  question the field name.
- **Parser/scorer preservation**: `response.txt`'s final JSON line and
  `reported.json` match exactly — nothing was dropped in normalization.

### Final classification (section 17)

```text
fixture integrity:        FAIL (public API contract not observable)
public API contract:      FAIL (never shown anywhere in the sandbox)
dispatch:                 PASS (complete, file supplied)
required files:           PASS (api.sh present)
context:                  PASS (not truncated)
raw response:              PASS (genuinely, deliberately, zero signal — verified)
parser/scorer:             PASS (no evidence lost)

-> R-API classification: FIXTURE_DEFECT
   (NOT VALID_CONTROLLER_FAILURE — per this remediation's own rule, one
   failing condition is sufficient; the model's review was thorough and
   well-reasoned given what it could actually observe)
```

No fixture change was made for R-API in this task (out of scope: this task
performs no live rerun, and any fixture repair requires the same explicit
human-authorization pattern used for every prior fixture touch this
session). A future repair would need to make the compatibility claim
externally observable *through the fixture itself* — e.g., a documented
schema/consumer artifact showing `displayName` as the prior contract — not
by adding "this is a breaking change" to the Reviewer's prompt (explicitly
disallowed).

## Historical Reviewer runs — admissibility

```text
reviewer-run-1-pre-fixture-fix/:  diagnostic/historical only
                                   (superseded by R_ERROR_FIXTURE_AMBIGUITY
                                   repair AND invalidated by the pagination
                                   FIXTURE_DEFECT — two independent reasons)
reviewer/pre-i2-fix/:             diagnostic/historical only
                                   (superseded by the I2 repair AND
                                   invalidated by the pagination
                                   FIXTURE_DEFECT — two independent reasons)
reviewer/:                        diagnostic/historical only
                                   (invalidated by the pagination
                                   FIXTURE_DEFECT — every sandbox in this
                                   run, including R-API's, R-AUTH's,
                                   R-CONCURRENCY's and R-ERROR's, carried
                                   the unfixed clean/pagination.sh)
```

Nothing deleted. Each directory's `outcome.json` (and, for the two
pre-i2-fix archives, their own `README.md`) now carries
`phase_r_reviewer_quality_evidence: "invalidated by fixture defect"` and
`diagnostic_historical_evidence: "retained"`.

## Future Reviewer gate

Per this remediation's own rule (section 18): a valid rerun **restarts from
zero** — all 5 seeded cases plus the clean control, in one run, against the
fixture-integrity-proven revision (commit `d9d6235` onward) — never spliced
together from any historical run and a new one.

```text
number of model dispatches required: 6 (5 seeded cases + 1 clean control)
expected model/variant: github-copilot/gpt-5.6-sol, high (unchanged
    production target; no effort escalation authorized or needed)
independence: each of the 6 dispatches is independent (its own sandbox,
    its own live call) -- confirmed by the harness's own architecture
    (run_reviewer_gate's per-case run_one loop)
```

### Estimated credits, derived from real measured evidence

14 real, healthy dispatches at this exact target
(`github-copilot/gpt-5.6-sol`, `high`) exist in the current I1-corrected
ledger:

```text
n=14, min=22.54, max=48.46, mean=34.03 credits/dispatch
```

| Basis | Credits (6 dispatches) |
|---|---:|
| Low (min × 6) | 135.2 |
| Central (mean × 6) | 204.2 |
| Conservative ceiling (max × 6) | 290.8 |

This session's own history shows a real, non-model-quality retry rate: 2 of
roughly 20 real dispatches needed a clean retry for content-quality reasons
unrelated to model correctness (a denied permission request, a truncated
JSON response) — roughly 10%. A 1-retry allowance at the mean cost is a
reasonable, evidence-grounded buffer, not an open-ended contingency.

```text
uncertainty/range: 135 - 291 credits (6 clean dispatches)
proposed tranche, including a 1-retry allowance: 204.2 + 34.0 = ~238 credits
```

## Prospective budget proposal (not self-approved)

```text
reviewer_remediation_rerun_budget:
    requested: 238 credits
    derivation: 6 required dispatches at the measured historical mean
                (34.03 credits, n=14, github-copilot/gpt-5.6-sol high) plus
                a 1-dispatch retry allowance at the same mean, grounded in
                this session's own ~10% observed content-quality retry rate
    range: 135 - 291 credits (min-mean-max of 14 real samples x 6, no
                retry allowance included in the range bounds)
    scope: covers ONLY a fresh, complete Reviewer gate restart (5 seeded
                cases + clean control) plus a reasonable environment-invalid
                replacement allowance -- no Phase 3, no unrelated
                experimentation, no effort-level exploration
    status: PENDING_HUMAN_APPROVAL
```

The historical 100-credit evaluation and 250-credit recovery caps are
**not** modified by this proposal — they remain approved, breached, and
historical. This is a distinct, forward-looking tranche a human must
explicitly approve before any future dispatch. No new live run may occur
until that approval is given.

## Final classification matrix

```text
I1 cost undercounting
    root cause: CONFIRMED
    implementation fix: PASS
    historical correction: COMPLETE (17/25 dispatches) / PARTIAL (8/25,
                            raw evidence unrecoverable, floor only)
    budget consequence: BREACHED (both accounts)

shared Bash decimal/octal defect
    root cause: CONFIRMED (man bash ARITHMETIC EVALUATION + direct
                reproduction, independent of the original live-model finding)
    classification: FIXTURE_DEFECT
    clean repaired: PASS
    all cases regenerated: PASS (structurally unnecessary for 4 of 5 cases
                — no case besides R-BOUNDARY ever carried its own copy of
                pagination.sh — confirmed and directly fixed for R-BOUNDARY)

Reviewer scorer attribution
    root cause: CONFIRMED (SCORER_DEFECT -- any material finding against
                the override file was credited regardless of content)
    classification: SCORER_DEFECT (partially fixed)
    repair: multi-finding ambiguity now fails closed (mechanically fixable
                part, fixed and tested). Single wrong-content finding still
                credited -- explicit, tested, documented open limitation;
                fixing it needs an LLM judge or a Reviewer contract change,
                both out of scope here. STOP condition genuinely triggered
                for the unfixed part, not silently worked around.

R-API zero signal
    fixture observability: FAIL (displayName never shown anywhere in the
                R-API sandbox; only in the hidden ground-truth.json)
    dispatch completeness: PASS
    raw response verified: PASS (genuinely, deliberately zero signal for
                the rename, confirmed via full response.txt read)
    parser/scorer preservation: PASS
    final classification: FIXTURE_DEFECT
                (not VALID_CONTROLLER_FAILURE -- the observability
                condition alone is sufficient to fail the strict
                five-condition test this remediation's own rules require)

Reviewer fixture integrity
    clean: PASS (zero known material defects, mechanically proven)
    five seeded cases: PASS (exactly one known defect each, mechanically
                proven; R-BOUNDARY was FAIL before the pagination fix)
    permanent admission gate: PASS (run_reviewer_gate refuses to dispatch
                against a fixture that fails this check; adversarially
                verified)

Reviewer live gate:
    NOT RUN (zero live model calls made in this task, by design)
    status: BLOCKED_PENDING_BUDGET_AND_RERUN
```

## Verification

```text
$ bash models/routing/opencode/eval/run-tests.sh
33/33 PASS (30 pre-existing + decimal-pagination-test.sh +
             fixture-integrity-test.sh + reviewer-attribution-test.sh)

$ bash tests/install.sh
PASS: installer compatibility tests

$ git diff --check main...HEAD
(clean, no whitespace errors)
```

Confirmed:

```text
live model calls in this task:     0
additional AI credits this task:   0
production routing:                unchanged (real global opencode.jsonc
                                    mtime unchanged since its Task-16
                                    activation; verified directly)
effective user-global routing:     unchanged
Build evidence:                    untouched (no files under
                                    eval/records/phase-r/build/ modified)
Explore evidence:                  untouched
Compaction evidence:               untouched
Phase R:                           still BLOCKED_REVIEWER
Phase 3:                           not started
Phase 4:                           not started
```

Every fixture/scorer change in this task went through the same discipline
established across this whole Phase-R effort: root cause proven with
evidence before any fix (systematic-debugging), RED test committed before
the fix (test-driven-development), adversarial mutation verification after
(a mutation that should fail the test does), and full-suite + install-suite
verification before considering the work done
(verification-before-completion). No fixture, scorer, or prompt change was
made without first tracing it to a root cause; two findings (R-API content
attribution, R-BOUNDARY-shape single-finding attribution) were explicitly
left unfixed and reported as open, rather than worked around with a fuzzy
heuristic or a threshold relaxation.
