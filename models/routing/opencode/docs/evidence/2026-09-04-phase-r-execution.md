# OpenCode V1 Phase R Execution — 2026-09-04

## Status

**Phase R: PASS.** Every committed ground-truth gate passed. The restored
routing profile is active on the real, user-global OpenCode configuration.

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
fixture control. Total cost 5.569 credits.

| Attempt | Oracle | Dispatch | Credits |
|---|---|---|---:|
| 1 | pass | OK | 2.238925 |
| 2 | pass | OK | 1.657875 |
| 3 | pass | OK | 1.67235 |

`eval/records/phase-r/build/outcome.json`.

## Reviewer seeded-defect gate

**PASS — 5/5**, after a fixture repair. Full detail in the section below.

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
   original bounds semantics exactly preserved, zero interference with any of
   the five seeded cases' own detection scoring, a proactive check for other
   files sharing the same vulnerability class found none in scope).

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
`"material"`. **5/5, clean control still genuinely clean.** The `xhigh`
diagnostic authorized for a genuine `VALID_CONTROLLER_FAILURE` was never
needed — the fixture repair alone resolved it on the first complete rerun at
production effort.

The superseded 4/5 run is preserved historically (not deleted, not
overwritten) at `eval/records/phase-r/reviewer-run-1-pre-fixture-fix/`,
explicitly marked non-adjudicating in its own `outcome.json`.

## Budget

- Evaluation credits consumed: **96.754087 / 100**
- Phase-R recovery credits consumed: **42.486075 / 250**
  (two single-case retries for R-API/R-BOUNDARY content-quality failures, plus
  the complete 6-dispatch Reviewer gate rerun against the repaired fixture —
  both authorized explicitly given evaluation-budget exhaustion)
- Organization guardrail: 7600 credits/billing cycle, externally enforced via
  GitHub billing; this repository holds no current billing snapshot, so
  headroom against the guardrail is reported as unavailable rather than
  estimated.
- No OpenCode-native spending cap was created.

## Pricing regime

The Reviewer/Sol probe and every Reviewer dispatch in this execution were
captured on 2026-09-04 — on or after the promotional-pricing cutoff
(2026-09-04) named in the decision doc. Recorded pricing regime: `standard`
(post-promotional). This observation is eligible to become, and is recorded
as, the canonical Reviewer/Sol steady-state cost reference
(`canonical_cost_reference: true` in both the capability-preflight record and
the Reviewer gate's `outcome.json`).

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
