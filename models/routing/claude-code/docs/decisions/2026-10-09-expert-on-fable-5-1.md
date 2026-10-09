# Expert on Fable 5.1

## Decision

The user moved Expert from `claude-opus-5-5` at `max` to `claude-fable-5-1` at
`xhigh`, the pair the [initial routing decision](2026-10-06-initial-claude-code-routing.md)
originally selected. `maxTurns: 6`, `tools` and `disallowedTools` are
unchanged. No other role changes.

## The condition that is now met

The initial decision's addendum "Expert moves to Opus 5.5 `max`" recorded that
the `claude-fable-5-1` `xhigh` capability call failed with "Fable 5.1 requires
usage credits. Switch to another model to continue.", and that "Returning
Expert to Fable 5.1 requires usage credits and a new decision record". The
account now has usage credits: the same call returned `OK` on Claude Code
2.1.295, with `modelUsage` showing `claude-fable-5-1`, and a Build session's
dispatch of `expert` ran on Fable 5.1 with the hook removing the caller's
`model` ([2026-10-09 evidence](../evidence/2026-10-09-capability.md)). This is
that record.

## Rationale

- **The cost-tier separation is restored.** Fable 5.1 lists at $10 input and
  $50 output per MTok, against $4 and $20 for Opus 5.5. [Pricing] Expert is
  again the one role on the scarce tier, which is what the initial decision
  meant it to be, and escalation-only use keeps that spend bounded.
- **`xhigh`, not `max`.** "Claude Fable 5.1 supports all five effort levels.
  **Start with `high`, the default.** Step up to `xhigh` or `max` for the most
  capability-sensitive agentic and coding work, …" [Effort] Expert's six-turn,
  read-only analysis of a decision packet is capability-sensitive but short;
  `xhigh` is the original selection, and `max` remains the lever if its
  recommendations fall short.
- **Provider separation stays absent.** Expert, Build, Plan and Reviewer are
  all on one Anthropic account. Model separation from Build returns; provider
  separation does not, and cannot within this bundle.

## Known risks

- **Usage credits are billed, not plan limits.** "Depending on your plan and
  seat tier, Fable usage can bill to usage credits instead of drawing on your
  plan's included limits." [Model config] Pro plans, standard Team seats and
  standard seat-based Enterprise seats run Fable on pay-as-you-go usage
  credits. [Fable billing] This account is one where it does: the 2026-10-06
  call failed with "Fable 5.1 requires usage credits". Every escalation is
  therefore a direct cost.
- **Consent prompt in interactive sessions.** "In interactive sessions, Claude
  Code shows a consent prompt before a Fable request bills usage credits."
  Dismissed mid-session, "Claude Code continues the turn on your default
  model". Read for a subagent, an escalation would then run on the default
  model (`claude-opus-5-5` from the fragment), not Fable, without the profile
  changing; this is inferred from the documentation, not observed. With Remote
  Control connected or in a background session, an unanswered prompt ends the
  turn after `dialogExpiry`, five minutes by default. In `-p` mode Claude Code
  bills without asking. After the user once chooses to continue on Fable, the
  prompt does not return. [Model config]
- **Credits can run out.** The 2026-10-06 failure is what a missing credit
  balance looked like; an exhausted one is expected to fail similarly, but that
  was not observed. If it recurs, the fallback is the
  2026-10-06 one: Expert on `claude-opus-5-5` `max`, with its own record.
- **Effort can be overridden per call.** A per-invocation `effort` on the
  Agent tool overrides the agent's `effort` field, and
  `CLAUDE_CODE_EFFORT_LEVEL` overrides both. [Subagents] The hook pins
  Expert's model, not its effort.

## Consequences

The README's deviation 2 no longer says Expert has no model separation: it
differs from Build, Plan and Reviewer by model and cost tier again, and still
by its six-turn cap and escalation-only use. Deviation 1 is unchanged:
Reviewer stays on Opus 5.5 `high`, and Fable 5.1 remains only a possible
future lever for it, with its own decision record.

`profile-test.sh` pins `claude-fable-5-1` `xhigh` for Expert. An installed
profile needs `agents/expert.md` re-copied.

## Evidence boundary

Live capability evidence is in
[`../evidence/2026-10-09-capability.md`](../evidence/2026-10-09-capability.md).
No role-fixture evidence exists. Documentation as read on 2026-10-09:

- [Pricing]
- [Effort]
- [Model config]
- [Fable billing]
- [Subagents]

[Pricing]: https://platform.claude.com/docs/en/about-claude/pricing
[Effort]: https://platform.claude.com/docs/en/build-with-claude/effort
[Model config]: https://code.claude.com/docs/en/model-config#fable-and-usage-credits
[Fable billing]: https://support.claude.com/en/articles/15424964
[Subagents]: https://code.claude.com/docs/en/subagents

Later corrections are appended as dated addenda, never edited in place.
