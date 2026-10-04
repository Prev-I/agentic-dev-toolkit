# Current Routing Alignment

## Decision

The user selected a new current OpenCode routing profile:

| Role | Model | Variant |
|---|---|---|
| Plan | `github-copilot/claude-opus-5.5` | `xhigh` |
| Build | `github-copilot/gpt-6.1-sol` | `high` |
| General | `github-copilot/gpt-6.1-sol` | `medium` |
| Explore | `github-copilot/gpt-6-luna` | `medium` |
| Scout | `github-copilot/gpt-6-luna` | `low` |
| Reviewer | `github-copilot/claude-opus-5.5` | `high` |
| Compaction | `github-copilot/claude-sonnet-5.5` | `low` |
| Title | `github-copilot/gpt-6-luna` | `low` |
| Summary | `github-copilot/gpt-6-luna` | `low` |
| Expert | `openai/gpt-6-astra` | `xhigh` |
| Breakglass | `openai/gpt-6.1-sol` | `max` |

The default model follows Build at `github-copilot/gpt-6.1-sol`. Direct OpenAI
remains confined to Expert and the human-selected Breakglass primary. All
permissions, prompts, delegation boundaries, modes, temperatures, step limits,
and escalation rules remain unchanged.

## Evidence Boundary

The exact model IDs and requested variants were present in the GitHub Copilot
and direct OpenAI provider catalogs exposed by OpenCode 1.18.32 on 2026-10-03.
This is discovery evidence, not proof of successful inference or a role-quality
benchmark. No new trivial-call record exists for Plan Opus 5.5 `xhigh`, General
GPT-6.1 Sol `medium`, Compaction Sonnet 5.5 `low`, Title or Summary GPT-6 Luna
`low`, Breakglass direct OpenAI GPT-6.1 Sol `max`, or Expert direct OpenAI Astra
`xhigh`. No new role-fixture evidence exists for those targets. These are
explicit user selections and do not rewrite historical experiment records or
their conclusions.

In particular, the prior GPT-6.1 Sol Build screening retained GPT-5.6 Sol under
its frozen promotion rule. Selecting GPT-6.1 Sol now is a later operational
choice, not a reinterpretation of that result. Expert inference and role fitness
remain unverified exceptions to the usual capability-probe prerequisite.

## Monitoring And Rollback

The GPT-6.1 Sol Build screening recorded approval-gate adherence in two of three
attempts and one human-correction finding where shared test setup masked a
WSL-dependent check. Monitor Build and General for repeated skipped approval
gates, edits outside the requested scope, or human corrections that exceed the
previous profile. Monitor Plan, General, Compaction, Title, Summary, Breakglass,
and Expert for provider errors and material correctness regressions because
their selected targets lack new successful-call or role-fixture evidence.

Rollback to profile `v5-build-quality-rollback-2026-09-29` if these problems are
repeated or block normal work. Restore that profile from commit `215d086`:
Build/default use `github-copilot/gpt-5.6-sol` `high`; Plan uses Opus 5.5 `max`;
General uses GPT-6 Luna `high`; Compaction uses GPT-5.6 Terra `medium`;
Title/Summary use GPT-5.6 Luna `low`; and Breakglass uses direct OpenAI GPT-6
Sol `max`. A role-specific regression may be rolled back independently by
changing only that role and recording a new profile decision. This decision
supersedes the 2026-09-29 current-profile selection without changing its
historical evidence or decision record.

## Verification Contract

`opencode.jsonc` remains the single routing authority. The target manifest
declares profile `v6-current-routing-2026-10-03`; the parsed-profile test permits
only the selected model, default-model, and variant substitutions while pinning
permissions and modes to the restored reference profile.

Activation remains a separate backup-and-merge operation. It must preserve all
user-owned global configuration outside the routing-owned keys.

## Addendum — 2026-10-04 successful-call capability

The historical discovery and evidence-gap statements above are retained as
written. New evidence is in `eval/records/current-routing-capability-2026-10/`.
Plan Opus 5.5 xhigh, General GPT-6.1 Sol medium, Compaction Sonnet 5.5 low,
and separate Title/Summary GPT-6 Luna low probes returned `CAPABILITY_OK` on
Copilot. Expert GPT-6 Astra xhigh also returned `CAPABILITY_OK` on direct OpenAI.
These are direct model/variant calls, not agent or role-quality fixtures.

The five Copilot probes spent 2.26529 observed credits. Execution stopped on
Expert because the existing dispatcher's direct-OpenAI credit accounting is
unavailable (`derived_credits: null`); its zero runtime cost is not proof of
zero billing. Breakglass Sol 6.1 max was therefore not dispatched and its
successful-call gap remains open. Resolved permission/inventory checks confirm
Breakglass remains direct OpenAI primary and Task-denied without a model call.

Routing and global configuration remain unchanged. The quality-profile cycle
is closed by the ACCEPTED `2026-10-04-quality-profile-closure.md`; General
screening is DEFERRED. No capability evidence here promotes a model or revises
any existing quality adjudication.

## Addendum — 2026-10-04 Breakglass subscription-call completion

After explicit user approval of a separate subscription-quota account, the
Breakglass gap above is closed by
`eval/records/current-routing-capability-2026-10/breakglass-completion/`.
One experiment-only primary request using `openai/gpt-6.1-sol`, requested variant
`max`, and permissions equivalent to active Breakglass returned `CAPABILITY_OK`.
No Task invocation or retry occurred. OAuth subscription metadata was verified
before dispatch, with no API-key field, environment key or provider-options
override; credential values and account identifiers were not recorded.

The separate OpenAI account uses unit `calls` for primary probe dispatches:
one historical Expert probe was
recorded retroactively without changing its dispatch, and one newly authorized
Breakglass call consumed its 1-call allowance. The user explicitly excluded
Expert's historical usage from that allowance. Total primary probe dispatches are two;
`derived_credits: null` means subscription quota, not metered consumption spend.
Runtime tokens are retained, without converting subscription calls to Copilot
credits or treating runtime cost zero as free billing. Ledger-observed Copilot
spend stays 2.26529 credits, not a total provider-spend claim. Historical
accounting-stop evidence remains unchanged.

All seven previously listed targets now have successful-call evidence. This is
not provider attestation of reasoning effort or role-quality evidence. Routing,
global configuration, Task exclusion and the accepted quality-profile closure
remain unchanged.

### Accounting clarification — auxiliary requests (POST_RUN_DIAGNOSTIC)

OpenCode's operational log also shows an auxiliary title request: Expert's
historical session used OpenAI GPT-6 Astra for title generation, while the new
Breakglass session used Copilot GPT-6 Luna. These auxiliary streams are not
metered by the dispatcher ledger. The two sessions therefore contain three
observed OpenAI provider streams (two historical and one new), not just two
provider requests; `calls` counts the primary probe dispatches. The new allowance
still used only one new OpenAI request. One auxiliary Copilot title request has
unobserved cost, so 2.26529 is only the ledger-observed Copilot amount. Sanitized
excerpts and the limits of permission parity/variant attestation are documented
in the completion record. No historical dispatch or adjudication is rewritten.
