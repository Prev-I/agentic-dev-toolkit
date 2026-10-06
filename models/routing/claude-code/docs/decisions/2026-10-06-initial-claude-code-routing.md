# Initial Claude Code Routing

## Decision

The user selected the first Claude Code routing profile:

| Role | Model | Effort |
|---|---|---|
| Build (main session) | `claude-opus-5-5` | `high` |
| Plan (`planner`) | `claude-opus-5-5` | `xhigh` |
| General (`general-purpose`) | `claude-sonnet-5-5` | `medium` |
| Explore | `claude-haiku-4-5` | — |
| Scout | `claude-haiku-4-5` | — |
| Reviewer | `claude-opus-5-5` | `high` |
| Expert | `claude-fable-5-1` | `xhigh` |
| Background (haiku slot) | `claude-haiku-4-5` | — |

## Rationale

- **Build on Opus 5.5 `high`** is the closest Anthropic counterpart to the
  OpenCode Build on GPT-6.1 Sol `high`. An earlier draft of the design put
  Build on Sonnet 5.5; the user moved it to Opus.
- **Fable 5.1 only on Expert.** At $10/$50 per MTok against Opus 5.5's $4/$20
  it is the scarce tier, taking the place of OpenCode's direct-OpenAI quota
  rule.
- **No Breakglass.** In OpenCode it existed to reach a separate provider and
  credential; on a single Anthropic account it has no reason to exist.
- **Enforcement by hook.** Superpowers passes an explicit `model` on every
  dispatch, and a per-call `model` beats frontmatter, so a policy-only port
  would be unreliable by construction.

## Consequences

Reviewer and Build share Opus 5.5 `high`: review independence rests on a fresh
context and a read-only prompt, not on a different model. Moving Reviewer to
Fable 5.1 is the first lever if review quality falls short.

## Evidence boundary

Prices and effort support come from Anthropic's model documentation as of
2026-10-06. Live capability evidence is in
`../evidence/2026-10-06-capability.md`. No role-fixture evidence exists.
Later corrections are appended as dated addenda, never edited in place.

## Addendum — 2026-10-06 Reviewer and Explore lose Bash

The design gave Reviewer and Explore `Bash` limited by `Bash(git diff:*)`-style
patterns in their `tools` frontmatter. Live probe P5 showed Claude Code 2.1.291
ignores those patterns there: with Bash permitted to the session, the probe
reviewer ran `touch` and created a file. A plain allowlist (`Read, Grep, Glob`)
is enforced (probe P5b: no Write, no Bash). Per the design's declared fallback,
both agents now have `Read, Grep, Glob` only, and the routing policy tells the
caller to hand Reviewer the change as a file. Superpowers' review templates
that run `git diff` themselves are adapted by the caller, not edited.
