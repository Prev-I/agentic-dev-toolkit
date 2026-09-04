# OpenCode V1 Phase R Execution — 2026-09-04

## Status

**Phase R status: `BLOCKED_REVIEWER`.** Build, Explore, Compaction, routing
resolution, and security/permission boundaries (including Breakglass) all
PASS and are not re-run by anything in this correction. The Reviewer
seeded-defect gate is BLOCKED — originally reported "PASS — 5/5", corrected
first to BLOCK (4/5) via the I2 rerun below, and as of the Reviewer
fixture-integrity remediation (see that record) still not cleared for a
valid rerun. Budget: both the evaluation and recovery caps are corrected and
confirmed exceeded — see [Budget](#budget).

`operational_state: active-provisional` — the restored routing profile is
installed and active on the real, user-global OpenCode configuration; that
activation is independent of the Reviewer gate's status and is not reversed
by this correction. `canonical_quality_reference: false` — this profile is
not currently the quality-verified reference for Phase 3 or any other
purpose, pending a clean Reviewer gate rerun.

Two post-hoc corrections were made to this record on 2026-09-04, after the
original "PASS" status above was first written — see
[Post-hoc corrections (I1, I2)](#post-hoc-corrections-i1-i2) before relying
on any cost figure or the Reviewer gate's original "5/5 PASS" claim
elsewhere in this document. The I2 repair itself surfaced further findings
during its rerun — see [I2 rerun result](#i2-rerun-result-block-45) — which
are traced to root cause and classified in the Reviewer fixture-integrity
remediation record (`docs/evidence/2026-09-04-reviewer-fixture-integrity-remediation.md`).

## Runtime

- OpenCode version: `1.18.27`
- Routing profile ID: `v1-restored-2026-09`
- Routing profile source commit at activation: `0fd2d942dd6d71a7f9fcb5545edc6d815272b6cb`
- Activation timestamp: `2026-09-04T10:48:49.505314+02:00`
- Activation target: `~/.config/opencode/opencode.jsonc` (user-global)
- Installed-profile manifest: `eval/manifests/installed-profile.json`

## Exact effective routing map

| Role | Provider / model | Variant | Mode |
|---|---|---:|---|
| `plan` | `github-copilot/claude-opus-5` | `max` | `primary` |
| `build` | `github-copilot/claude-opus-5` | `high` | `primary` |
| `general` | `github-copilot/gpt-5.6-terra` | `high` | `subagent` |
| `explore` | `github-copilot/gpt-5.6-luna` | `medium` | `subagent` |
| `scout` | `github-copilot/gpt-5.6-luna` | `low` | `all` |
| `reviewer` | `github-copilot/gpt-5.6-sol` | `high` | `subagent` |
| `compaction` | `github-copilot/gpt-5.6-terra` | `medium` | `primary` |
| `title` | `github-copilot/gpt-5.6-luna` | `low` | `primary` |
| `summary` | `github-copilot/gpt-5.6-luna` | `low` | `primary` |
| `expert` | `openai/gpt-5.6-sol` | `xhigh` | `subagent` |
| `breakglass` | `openai/gpt-5.6-sol` | `max` | `primary` |

Resolved via `opencode debug agent <role>` from a neutral working directory
and independently from a project working directory; both agreed exactly, with
no project-level override on any role (`eval/records/phase-r/effective-routing.json`,
`status: "PASS"`).

## Restoration invariants — the required RED-to-GREEN evidence

Before the routing change (Task 7) landed, the committed restoration-invariant
test failed for the required reasons, confirming the invariants genuinely held
the pre-restoration profile accountable rather than trivially passing:

```
FAIL: plan: model 'github-copilot/claude-opus-4.6' != 'github-copilot/claude-opus-5'
FAIL: build: model 'github-copilot/claude-opus-4.6' != 'github-copilot/claude-opus-5'
FAIL: general: model 'github-copilot/claude-opus-4.6' != 'github-copilot/gpt-5.6-terra'
FAIL: general: variant 'xhigh' != 'high'
FAIL: explore: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-luna'
FAIL: explore: variant 'high' != 'medium'
FAIL: scout: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-luna'
FAIL: scout: variant 'high' != 'low'
FAIL: reviewer: missing routing row
FAIL: compaction: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-terra'
FAIL: compaction: variant None != 'medium'
FAIL: title: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-luna'
FAIL: title: variant None != 'low'
FAIL: summary: model 'github-copilot/gpt-5.3-codex' != 'github-copilot/gpt-5.6-luna'
FAIL: summary: variant None != 'low'
FAIL: expert: missing routing row
FAIL: breakglass: missing routing row
FAIL: routing rows ['breakglass', 'expert', 'reviewer'] differ from the declared target
FAIL: default model 'github-copilot/claude-opus-4.6' != 'github-copilot/claude-opus-5'
FAIL: a production routing row still references claude-opus-4.6
```

After Task 7's routing rewrite, the same test passed unmodified:
`PASS: Phase R routing restoration invariants (11 agents)`.

## Capability-forced rows

```
plan, build, general
```

Reason: `github-copilot/claude-opus-4.6` — `MODEL_UNRESOLVABLE` /
`ProviderModelNotFoundError` per the Phase-0 capability closure.

## Risk-decision rows

```
explore, scout, reviewer, compaction, title, summary
```

Reason: explicit decision not to depend on `github-copilot/gpt-5.3-codex` for
the staged migration; Codex still resolved at the recorded Phase-0 capability
check and is not described as retired or unavailable.

## Expert bump

`openai/gpt-5.6-sol` `high` → `xhigh`. Landed atomically with the Reviewer
move in the same commit (Task 7, `ee7092d`) — there was never a supported
installed state with Reviewer Sol `high` and Expert Sol `high` simultaneously.
Verified: `eval/records/phase-r/reviewer/*/dispatch/dispatch.json` show
`reviewer` resolving `github-copilot/gpt-5.6-sol` `high`; the Breakglass
primary-selection dispatch (`eval/records/phase-r/security/breakglass-primary.json`)
shows `expert`'s sibling target `openai/gpt-5.6-sol` at `xhigh` in the
effective routing map above.

## Breakglass

`openai/gpt-5.6-sol`, `max`, `mode: primary`. Denied to ordinary Task-routing
at the top level and on every delegating agent (`plan`, `build`, `general`).
Human-primary selection independently confirmed live: one real dispatch
returned exactly `BREAKGLASS_PRIMARY_OK`
(`eval/records/phase-r/security/breakglass-primary.json`, `classification: "OK"`).

## Fresh runtime capability preflight

`eval/manifests/phase-r-capability-preflight.json`, `status: "PASS"`. All 11
declared roles resolved and completed a trivial call as `USABLE`, zero
capability regressions, zero transient blocks. 34.146787 evaluation credits
consumed. Reviewer/Sol probe captured 2026-09-04 (on/after the promotional
cutoff — see Pricing below).

## Security outcomes

| Boundary | Result | Evidence |
|---|---|---|
| Reviewer permission boundary | PASS | `eval/records/phase-r/security/reviewer.json` |
| Expert permission boundary | PASS | `eval/records/phase-r/security/expert.json` |
| Breakglass normal-agent non-exposure | PASS | `eval/records/phase-r/security/breakglass-non-exposure.json` |
| Breakglass human-primary execution | PASS | `eval/records/phase-r/security/breakglass-primary.json` |

All four use resolved-permission-and-inventory evidence from `opencode debug
agent`, never prompt behavior, as the oracle.

**Unplanned discovery, resolved with explicit authorization:** the real
workstation carried separate global agent files at
`~/.config/opencode/agents/{reviewer,expert}.md` (pre-dating this plan, never
in its file list) whose own `model:`/`variant:` frontmatter was overriding
`opencode.jsonc`'s routing for those two roles — the opposite of what Task 7's
project-local probe had found. Backed up, then had `model:`/`variant:`
stripped (mirroring the repository's own already-reviewed edit to these
files), re-verified `PASS`.

## Build restoration gate

**PASS.** 3/3 valid attempts, all `oracle_passed: true`, all dispatch
`classification: "OK"`. No classification needed, no n=5 escalation, no
fixture control. Gate verdict is unaffected by I1 (cost has no bearing on
`oracle_passed`). Total cost, corrected per I1: 74.096 credits (originally
recorded as 5.569 — see [Post-hoc corrections](#post-hoc-corrections-i1-i2)).

| Attempt | Oracle | Dispatch | Credits (corrected) | Credits (originally recorded) |
|---|---|---|---:|---:|
| 1 | pass | OK | 26.191575 | 2.238925 |
| 2 | pass | OK | 23.1935 | 1.657875 |
| 3 | pass | OK | 24.711275 | 1.67235 |

`eval/records/phase-r/build/outcome.json`.

## Reviewer seeded-defect gate

**BLOCK — 4/5**, as of the I2 repair's live rerun on 2026-09-04. Previously
reported here as "PASS — 5/5"; that claim is corrected — see
[Post-hoc corrections](#post-hoc-corrections-i1-i2) and
[I2 rerun result](#i2-rerun-result-block-45). The fixture-repair narrative
below (R-ERROR / `load_items_or_fail`) remains accurate and is unaffected by
either correction — it addresses a different case.

`eval/records/phase-r/reviewer/outcome.json`.

## Explore dependency-chain gate

**PASS**, first attempt, no retry. Reported chain
`entry -> facade -> service -> adapter -> protocol`, 4 hops,
`PROTOCOL_VERSION=v3` — all four required elements matched simultaneously.

`eval/records/phase-r/explore/outcome.json`.

## Compaction invariant gate

**PASS**, first attempt, no retry. All 4 invariants (`INV-RUNTIME`,
`INV-BREAKGLASS`, `INV-BUDGET`, `INV-FAILURE`) preserved exactly, 0
contradictions.

`eval/records/phase-r/compaction/outcome.json`.

## The Reviewer gate's path to PASS

The Reviewer gate did not pass on the first attempt, and its resolution
involved real engineering work worth recording in full.

### Two harness bugs, found only by live execution, fixed with independent re-verification each round

1. **`dispatch_extract_json` quote-desync** (shared primitive, `dispatch-fixture.sh`,
   used by all four gate runners). The hand-rolled string-tracking JSON
   extractor desynced whenever a live model's own prose contained a single
   unpaired double-quote character — extremely common in natural-language code
   review ("a value containing a double quote"). This corrupted extraction on
   2 of the first 6 real Reviewer dispatches. Fixed by replacing the scanner
   with `json.JSONDecoder().raw_decode()` tried at every `{` position, keeping
   the last successful decode. Independently re-reviewed: exact intended
   algorithm confirmed, scope confirmed limited to the one function, both
   shipped regression tests confirmed genuinely discriminating, plus three
   additional adversarial cases constructed and run by the reviewer
   independently, all correct. This was the fifth and final fix round for this
   primitive across the whole plan (the other four: null-cost handling, IFS
   field-splitting, RETURN-trap isolation plus idempotent skip, and a
   shared-stdin corruption bug — all discovered the same way, all
   independently verified).

2. **Fixture "clean" control defect** (`eval/fixtures/reviewer-seeded-defects/clean/{api.sh,pagination.sh}`,
   pre-existing from Phase 0, not part of this plan). The clean control
   genuinely contained the two vulnerabilities its own ground truth
   (`clean/ground-truth.json`, `"known_material_defects": 0`) claimed did not
   exist: unescaped JSON interpolation in `api.sh`, and unquoted-arithmetic
   command injection in `pagination.sh`. A real live Reviewer dispatch
   correctly and consistently flagged both. Treated as `FIXTURE_DEFECT` by
   analogy to the Build gate's own state-machine taxonomy, repaired with
   explicit human authorization, independently reviewed and approved
   (confirmed: both vulnerabilities genuinely closed via adversarial testing,
   original bounds semantics exactly preserved in `clean/`). **The
   "zero interference with the five seeded cases' own detection scoring" and
   "proactive check for other files sharing the same vulnerability class
   found none in scope" claims here are corrected as of 2026-09-04 — both
   were wrong.** `cases/R-API/api.sh` and `cases/R-BOUNDARY/pagination.sh`
   are self-contained files carrying this exact same vulnerability class and
   were never checked; see [I2](#post-hoc-corrections-i1-i2).

### Two content-quality dispatch failures, resolved by clean retry

After both harness fixes, a full run still needed two retries: `R-API`
produced no usable final answer after the model's own experimental
verification command was denied by its correctly-enforced read-only
permission boundary and it did not recover; `R-BOUNDARY`'s final JSON was
syntactically truncated (3 open braces, 2 close). Both dispatch classifications
were `"OK"` — these were content-quality issues, not dispatch failures. Both
were retried cleanly (fresh, independent attempts, no modification of any
model output) and succeeded. Charged to the Phase-R recovery budget, since the
evaluation budget was nearly exhausted at that point — authorized explicitly.

### The R-ERROR root cause: a structured H1/H2/H3 investigation

The clean run above still landed at 4/5: every seeded case passed except
`R-ERROR`, whose defect (a storage backend failure silently converted to a
false-successful empty result) was correctly and precisely identified in the
model's own prose, but rated `"suggestion"` severity rather than
`"material"`/`"blocking"` — below the scorer's detection threshold.

A structured hypothesis tree was worked in order:

- **H1 — REVIEWER_CONTRACT_DEFECT (ruled out).** The severity rubric
  ("material/blocking = incorrect behavior, data loss, or a security
  exposure") produced correct material/blocking classifications for 4 of the
  5 seeded cases using identical wording — not systematically insufficient.
- **H2 — R_ERROR_FIXTURE_AMBIGUITY (confirmed).** Comparing all five seeded
  functions: `public_response`, `read_resource(caller, owner, value)`,
  `increment_counter`, and `validate_page_size` each signal their materiality
  purely through the function's own name or parameter names, with zero
  comments anywhere in this fixture. `load_items(storage)` gave no such
  signal — nothing in the name hints that callers rely on distinguishing
  failure from genuinely-empty. The model's own reasoning confirmed this
  exactly: *"This looks like an intentional fallback; it would only be a
  defect if a spec required errors to propagate."*
- **H3 — VALID_CONTROLLER_FAILURE.** Not reached; ruled moot once H2 was
  confirmed and repaired.

**Fixture repair** (human-approved, independently reviewed): renamed
`load_items` → `load_items_or_fail` in both `clean/storage.sh` and
`cases/R-ERROR/storage.sh`, matching the fixture's existing
naming-only-signals-materiality convention. No comments added, the seeded
swallow-and-fallback defect itself unchanged, `oracle.json` and
`ground-truth.json` untouched, the other four cases untouched. A new
regression test proves the two files differ by nothing except the seeded
defect, independently verified discriminating against both a reverted-rename
and an unrelated-divergence mutation.

**Result: the complete Reviewer gate was re-run in full** (all 5 seeded cases
plus the clean control, fresh sandboxes, one uninterrupted session) against
the repaired fixture, at the **same production target**
(`github-copilot/gpt-5.6-sol`, `high` — no effort change). All 6 dispatches
were healthy on the first attempt. `R-ERROR` now correctly resolved
`"material"`. **5/5 was reported here at the time, clean control still
genuinely clean.** The `xhigh` diagnostic authorized for a genuine
`VALID_CONTROLLER_FAILURE` was never needed for R-ERROR — the fixture
repair alone resolved it on the first complete rerun at production effort.
**This "5/5" claim is corrected as of 2026-09-04 — see
[Post-hoc corrections](#post-hoc-corrections-i1-i2), I2:** 2 of these 5
detections (R-API, R-BOUNDARY) are now known to be attributable to a
different, reintroduced vulnerability rather than the seeded defect they
were credited for detecting. This does not affect the R-ERROR finding
documented in this section, which remains a correctly-diagnosed and
correctly-repaired case.

The superseded 4/5 run is preserved historically (not deleted, not
overwritten) at `eval/records/phase-r/reviewer-run-1-pre-fixture-fix/`,
explicitly marked non-adjudicating in its own `outcome.json`.

## Post-hoc corrections (I1, I2)

Two Important findings surfaced by the final whole-branch review and
independently confirmed on 2026-09-04, **after** the sections above were
first written. Both are now fixed or in progress; this section is the
authoritative correction — where it disagrees with wording elsewhere in this
document (e.g. "PASS — 5/5", the credit figures in the Budget section
below), this section governs.

### I1 — cost/credit undercounting (fixed; historical figures corrected)

`dispatch-fixture.sh`'s raw-stream parser recorded only the **last**
`step_finish` event's `cost`, overwriting rather than summing every prior
turn's cost in a multi-turn dispatch (`probe.sh`'s single-turn capability
probes were unaffected — verified via `cache.read: 0` in every preflight
record). Fixed 2026-09-04, commit `505d35a`, with a regression test proving
cost sums across turns while `tokens` (already a cumulative running
snapshot per event) correctly keeps the last value.

Every committed `dispatch.json` with surviving `raw.jsonl` evidence (17 of
25 real dispatches) was recomputed from that raw evidence and corrected in
place; each carries a `cost_correction` block recording the original and
corrected figures. **8 dispatches have no recoverable true cost**: their
`raw.jsonl` was overwritten on disk by a later dispatch reusing the same
output directory before this bug was found. Their ledger entries are
flagged `cost_correction: "UNRECOVERABLE"` and their recorded credits are a
**known-undercounted floor**, not the true spend — every sibling dispatch in
the same batch showed a 6-12x undercount.

Full detail: `eval/records/phase-r/budget-ledger.json`'s `i1_correction`
block.

### I2 — clean-control fixture repair was incomplete (open; repair pending human authorization)

The clean-control repair (commit `a96c0ce`, authorized during the original
Reviewer gate investigation) fixed
`eval/fixtures/reviewer-seeded-defects/clean/{api.sh,pagination.sh}` but was
never propagated to the case override files
`cases/R-API/api.sh` and `cases/R-BOUNDARY/pagination.sh`, which are
self-contained and still carried the pre-repair vulnerable patterns.
Independent verification of both cases' actual response transcripts
confirms their "blocking" findings are entirely about the reintroduced old
vulnerability (JSON-escaping for R-API, arbitrary command execution via
array-subscript substitution for R-BOUNDARY), with zero mention of either
case's seeded ground-truth defect. 2 of the 5 detections credited toward the
reported 5/5 do not detect what they were meant to detect.

Full detail: `eval/records/phase-r/reviewer/outcome.json`'s
`i2_correction_note`. Repair and rerun require the same human-authorization
pattern used for the R-ERROR fixture repair above.

### I2 rerun result: BLOCK, 4/5

The fixture was repaired (commit `5d157e7`): `cases/R-API/api.sh` now
adopts `clean/api.sh`'s safe JSON-escaping scaffolding but keeps the `name`
field key (vs. clean's `displayName`), preserving only the seeded
field-rename defect; `cases/R-BOUNDARY/pagination.sh` now adopts
`clean/pagination.sh`'s numeric-format guard but keeps the lower bound at
`0` (vs. clean's `1`), preserving only the seeded zero-boundary defect. Both
changes were independently reviewed and confirmed correct — each case
differs from `clean/` by exactly its seeded defect and nothing else, and
both defects were confirmed real and reachable by direct execution.
New regression tests (mirroring the existing R-ERROR/storage.sh block)
proved the repair is minimal and that reverting either defect, or
introducing an unrelated divergence, correctly fails the test.

R-API and R-BOUNDARY were then redispatched live against the repaired
fixture (same production target, `github-copilot/gpt-5.6-sol` `high`,
charged to the recovery account per explicit human authorization given the
recovery cap was already exceeded — see [Budget](#budget)). The prior
mis-attributed evidence is archived, not deleted, at
`eval/records/phase-r/reviewer/pre-i2-fix/`.

**Result: still not 5/5.** The gate's committed scorer
(`eval/scoring/reviewer.sh::reviewer_structured_gate`, unmodified) returns
`block`, detected 4/5:

| Case | Result |
|---|---|
| R-API | **none** — zero findings reported against `api.sh` in this dispatch |
| R-AUTH | blocking (unaffected by I2, unchanged from the original run) |
| R-BOUNDARY | material, but **mis-attributed** (see below) |
| R-CONCURRENCY | blocking (unaffected by I2, unchanged) |
| R-ERROR | material (unaffected by I2, unchanged) |

Two new findings, neither yet root-caused or authorized for any further
fixture change:

1. **R-API: the seeded defect received no signal at all.** Unlike the
   original run (which flagged the wrong vulnerability), this dispatch
   reported zero findings — not even a suggestion — against `api.sh`. A
   single-sample model-judgment outcome, structurally similar to the
   original R-ERROR shortfall, but not yet investigated with the same
   H1/H2/H3 rigor.
2. **R-BOUNDARY's "material" credit is itself mis-attributed.** The
   mechanical scorer credits any material/blocking finding against the
   case's override file, regardless of which vulnerability it names. This
   dispatch's finding is genuine but is about a **newly-discovered defect**
   in the numeric-format guard shared by every case's sandbox copy of
   `pagination.sh`: `[[ "$1" =~ ^[0-9]+$ ]]` accepts leading-zero strings,
   which bash's `(( ))` then reinterprets as octal — `"0144"` passes as
   decimal 100 (bypassing the intended 1..100 bound), and `"08"` raises a
   bash arithmetic error instead of a clean rejection, because `8` is not a
   valid octal digit. This guard pattern originates in `clean/pagination.sh`
   from the original clean-control repair (commit `a96c0ce`) and was
   propagated verbatim into `cases/R-BOUNDARY/pagination.sh` by this
   session's I2 fix. It is present in **every** case sandbox's copy of
   `pagination.sh` (all six sandboxes include `clean/pagination.sh`
   unmodified), not only R-BOUNDARY's. The clean-control dispatch's own
   result (0 material findings) does not disprove this — it reflects
   model-response variance across independently-sampled dispatches against
   the same file content, not evidence the defect is absent.

No further fixture modification, live dispatch, or effort escalation was
made after this rerun. Both findings above are open and require the same
explicit human-authorization pattern as every other fixture touch in this
plan before any further action. Full detail:
`eval/records/phase-r/reviewer/outcome.json`'s `i2_rerun_note`.

## Budget

**Both figures below are corrected for I1.** Where corrected credits could
not be recovered (8 dispatches, all Reviewer-gate related), the account
total is a **floor** — the true total is known to be higher.

- Evaluation credits consumed: **289.012037 / 100 — cap exceeded** (floor;
  6 of the 8 unrecoverable dispatches are charged to this account, so the
  true total is higher still)
- Phase-R recovery credits consumed: **349.944275 / 250 — cap exceeded**
  (this account has no unrecoverable entries, so this figure is accurate,
  not a floor; includes the 2 I2-rerun dispatches — 82.03 credits — charged
  here per explicit human authorization given the account was already over
  cap before that spend)
- Every `ledger_admit` check performed live during original Phase R
  execution compared against the undercounted figures and reported
  "admitted" at each step; this correction shows both caps were almost
  certainly breached in real terms at the time, without any check catching
  it, because the same bug that undercounted spend also undercounted what
  was being checked against the cap. The I2-rerun spend above was made with
  full knowledge that the recovery cap was already exceeded, by explicit
  human decision, not by a ledger check that failed to catch it.
- Organization guardrail: 7600 credits/billing cycle, externally enforced via
  GitHub billing; this repository holds no current billing snapshot, so
  headroom against the guardrail is reported as unavailable rather than
  estimated. Even the corrected evaluation+recovery total (~639 credits)
  stays under this guardrail.
- No OpenCode-native spending cap was created.

## Pricing regime

The Reviewer/Sol probe and every Reviewer dispatch in this execution were
captured on 2026-09-04 — on or after the promotional-pricing cutoff
(2026-09-04) named in the decision doc. Recorded pricing regime: `standard`
(post-promotional). **`canonical_cost_reference` is corrected to `false`** in
both `eval/records/phase-r/reviewer/outcome.json` and
`eval/records/phase-r/reviewer-run-1-pre-fixture-fix/outcome.json` (the
capability-preflight probes in `eval/records/phase-r/preflight/` carry no
such field and are unaffected — they are single-turn, verified unaffected by
I1): the pricing *regime* classification (standard vs. promotional) is unaffected
by I1 and remains correct, but the cost figures originally cited alongside
it were undercounted, so this observation is not fit to serve as the
canonical steady-state cost reference until re-verified against the I1-
corrected figures.

## Installed-profile manifest

`eval/manifests/installed-profile.json` — `canonical: false` as of this
document; flipped to `true` alongside the restored-reference snapshot once
every gate above is confirmed passing (Task 23).

## Architecture note

The four behavioral gate runners (Build, Reviewer, Explore, Compaction) are
thin adapters over one shared dispatch primitive
(`eval/runtime/opencode-v1-adapter/dispatch-fixture.sh`). None of the four
committed oracles or scorers (`eval/decision-rules/build-gate.sh`,
`eval/scoring/{reviewer,explore,compaction}.sh`) were modified by this plan.
The only ground-truth-adjacent change was the R-ERROR fixture naming repair
above, made under the plan's own `FIXTURE_DEFECT` doctrine with explicit
human authorization at each step, never by lowering a threshold or by
changing what the scorers require.

## Known limitations, recorded for the final whole-branch review

Deferred minor findings accumulated across the plan's task reviews (test
fidelity gaps, a cosmetic blank-provider ledger field in `--agent` mode, a
pre-existing arrow-alignment nit in the README, and similar) are listed in the
SDD ledger (`.superpowers/sdd/2026-09-03-opencode-routing-phase-r/progress.md`)
and are triaged by the final whole-branch review, not individually re-litigated
here.

I1 and I2 (see [Post-hoc corrections](#post-hoc-corrections-i1-i2)) were the
two Important findings from that same final whole-branch review. I1 is fixed
and its historical figures corrected. I2 is confirmed and open: repair of
`cases/R-API/api.sh` and `cases/R-BOUNDARY/pagination.sh`, and a rerun of the
affected cases, are pending explicit human authorization for the fixture
touch, per the same pattern used for every other fixture change in this
plan.
