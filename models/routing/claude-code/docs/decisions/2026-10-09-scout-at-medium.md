# Scout at medium

## Decision

The user raised Scout's effort from `low` to `medium`. Its model stays
`claude-haiku-5-5`, and `tools` are unchanged. No other role changes.

| Role | Where | Before | After |
|---|---|---|---|
| Scout | `agents/scout.md` | `claude-haiku-5-5`, `low` | `claude-haiku-5-5`, `medium` |

## Rationale

- **`low` works against searching.** The effort guidance for Haiku 5.5 warns:
  "In long agent prompts, the model is more likely to skip a search, stop
  early, or skip a check at `low`." [Effort] Scout exists to search and to cite
  what it finds; skipping a search is the failure that matters most for it.
- **`medium` is the recommended starting point.** "**Start with `medium`** for
  most work, including agentic coding. Use `low`, the cheapest and fastest
  level, for chat, short tool tasks, and simple, high-volume requests." [Effort]
  Scout's research tasks are neither chat nor short tool tasks.
- **It is the lever already named.** [Haiku roles on Haiku 5.5](2026-10-09-haiku-roles-on-haiku-5-5.md)
  recorded this risk and named `medium` as the first lever.

## Consequences

- Scout and Explore now run the same model at the same effort; they differ by
  tools and prompt, not by routing.
- Scout no longer matches the OpenCode bundle, whose scout runs GPT-6 Luna
  `low`. The README lists this as deviation 7.
- Each Scout request may think more and so bill more output tokens than at
  `low`. That is expected from the effort guidance, not measured here.
- An installed profile needs `agents/scout.md` re-copied; until then the
  alignment check reports Scout's `effort` as `DRIFT`.

## Evidence boundary

No new live run. The pair `claude-haiku-5-5` at `medium` returned `OK`, and
evidence E1 shows a frontmatter `medium` on a Haiku 5.5 agent reaching the API
as `medium`, both in
[`../evidence/2026-10-09-capability.md`](../evidence/2026-10-09-capability.md)
(the Explore rows). Scout itself has not been observed at `medium` on the wire.
No role-fixture evidence shows that `medium` improves Scout's answers.
Documentation as read on 2026-10-09:

- [Effort]

[Effort]: https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-haiku-5-5

Later corrections are appended as dated addenda, never edited in place.
