# Haiku Roles on Haiku 5.5

## Decision

The user moved every role that ran Haiku 4.5 to Haiku 5.5, and gave the two
agents an effort level now that the model supports one:

| Role | Where | Before | After |
|---|---|---|---|
| Explore | `agents/Explore.md` | `claude-haiku-4-5`, no effort | `claude-haiku-5-5`, `medium` |
| Scout | `agents/scout.md` | `claude-haiku-4-5`, no effort | `claude-haiku-5-5`, `low` |
| Background (haiku slot) | `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `claude-haiku-4-5` | `claude-haiku-5-5` |

Build, Plan, General, Reviewer and Expert are unchanged. This record amends
[the initial routing decision](2026-10-06-initial-claude-code-routing.md); it
does not replace it.

## Rationale

- **Cost.** Haiku 5.5 lists at $0.10 input and $0.50 output per MTok for
  prompts up to 100,000 tokens, against $1 and $5 for Haiku 4.5. [Pricing]
- **Capability.** Haiku 5.5 is described as "built for high-volume,
  latency-sensitive work such as classification, routing, extraction, and
  subagent tasks", with a 1M-token context window and up to 128k output
  tokens, up from 200k and 64k on Haiku 4.5. [What's new]
- **Effort is now available.** Haiku 4.5 is not among the models that support
  the effort parameter; "Claude Haiku 5.5 supports all five effort levels, and
  `medium` is the default." [Effort] The README's note that Haiku 4.5 does not
  support effort levels no longer applies to the profile and is removed.
- **`medium` for Explore, `low` for Scout** matches the OpenCode bundle, which
  runs `explore` on GPT-6 Luna `medium` and `scout` on GPT-6 Luna `low`
  ([OpenCode README](../../../opencode/README.md)). It also follows Anthropic's guidance:
  "**Start with `medium`** for most work, including agentic coding. Use `low`,
  the cheapest and fastest level, for chat, short tool tasks, and simple,
  high-volume requests." [Effort]
- **The slot stays pinned.** On the Anthropic API the `haiku` alias already
  resolves to Haiku 5.5 [Model config], and the 2026-10-09 evidence shows it
  does with the variable unset. The pin is kept so that background tasks do
  not move with Claude Code's default, and so the alignment check has a value
  to compare.

## Known risks

- **Prompt-length price threshold.** "Claude Haiku 5.5 is priced by prompt
  length: a request whose prompt is over 100,000 tokens pays higher prices. A
  request's prompt length counts all of its input tokens, including cache reads
  and cache writes." "Each request is priced on its own: a request over the threshold
  pays the higher prices", which are $0.50 input and $2.50 output per MTok.
  [Pricing] An Explore run that reads many
  large files can cross it, since each request carries the subagent's whole
  context.
- **New tokenizer.** "The same input text produces approximately 30% more
  tokens on Claude Haiku 5.5 than on Claude Haiku 4.5." [What's new] Haiku 5.5
  also "keeps thinking blocks from all earlier assistant turns in context",
  and adaptive thinking "is on by default" [What's new]; "thinking tokens are
  billed as output tokens" [Costs]. Per-request token counts will therefore
  rise. At list prices, even a request above the threshold stays below Haiku
  4.5's per-MTok rates after a 30% increase. That bounds the rate per unit of
  text, not the cost per request, which also depends on thinking output; it is
  arithmetic on list prices, not a measurement.
- **`low` and searching.** The effort guidance warns: "In long agent
  prompts, the model is more likely to skip a search, stop early, or skip a
  check at `low`." [Effort] Scout's job is searching. If its answers come back
  thin, `medium` is the first lever.
- **Frontmatter effort can be overridden.** Since Claude Code 2.1.292 the Agent
  tool takes a per-invocation `effort` that overrides the agent's `effort`
  field, and `CLAUDE_CODE_EFFORT_LEVEL` overrides both. [Subagents] The hook
  removes `model` only, so the effort pinned here holds only while callers do
  not pass `effort`. Extending the hook is a separate decision.

## Background effort

There is no separate effort setting for the haiku slot. Checked as follows:

1. The model configuration page documents `ANTHROPIC_DEFAULT_HAIKU_MODEL` as
   "The model to use for `haiku`, or background functionality" [Model config],
   and documents no effort control specific to background functionality. The
   background-usage section it links to names none either. [Costs]
2. `modelSettings` is an "object mapping a model name to an object" whose
   fields include `effortLevel`, and Claude Code writes "each entry under the
   model's canonical name". [Settings] So a level can be stored for
   `claude-haiku-5-5`; whether background requests read it is not documented.
3. On the wire the value is not observable: with `ANTHROPIC_LOG=debug` the
   SDK log shows a Haiku 5.5 request carrying `output_config` but collapses
   its contents (2026-10-09 evidence).

So the slot's effort is not configurable by this bundle. To re-check on a later
Claude Code, look for a documented background effort setting first; failing
that, set `modelSettings.claude-haiku-5-5.effortLevel` in a scratch project and
look for the value in a background request, which needs a log that shows
`output_config`'s contents.

## Consequences

`profile-test.sh` now pins `effort` for Explore and Scout, and the alignment
check reports a drifted `effort` as `DRIFT`, as it already did for the other
agents. An installed profile needs the two agent files re-copied and the
fragment re-merged.

## Evidence boundary

Live capability evidence is in
[`../evidence/2026-10-09-capability.md`](../evidence/2026-10-09-capability.md).
No role-fixture evidence exists. Documentation as read on 2026-10-09:

- [Pricing]
- [Effort]
- [What's new]
- [Model config]
- [Costs]
- [Settings]
- [Subagents]

[Pricing]: https://platform.claude.com/docs/en/about-claude/pricing
[Effort]: https://platform.claude.com/docs/en/build-with-claude/effort
[What's new]: https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5
[Model config]: https://code.claude.com/docs/en/model-config
[Costs]: https://code.claude.com/docs/en/costs#background-token-usage
[Settings]: https://code.claude.com/docs/en/settings-reference#modelsettings
[Subagents]: https://code.claude.com/docs/en/subagents

Later corrections are appended as dated addenda, never edited in place.

## Addendum — 2026-10-09 effort is observable through a proxy

Point 3 under "Background effort" no longer holds in general: a local logging
proxy shows each request's `output_config` (evidence addendum "effort observed
on the wire"). It confirms that Explore runs Haiku 5.5 at `medium` and Scout at
`low`. No background request was captured, since a `-p` run gives no reliable
trigger for one, so the conclusion that the slot's effort is not configurable
by this bundle stands. The proxy is the way to re-check it from an interactive
session.
