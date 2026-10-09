# The Hook Pins Effort

## Decision

`hooks/pin-agent-model.sh` removes `effort` as well as `model` from Agent calls
to `reviewer`, `expert`, `scout`, `Explore` and `planner`. `general-purpose`
stays unpinned for both. The routing policy's first rule now tells the caller
to omit `effort` too. No agent's model or effort changes.

## Rationale

- **A per-call `effort` beats the frontmatter.** "When you ask Claude to run a
  non-fork subagent at a specific effort level, it can also pass an `effort`
  parameter for that invocation. The parameter overrides the `effort` field
  and stays in effect when the subagent is resumed. … The per-invocation
  parameter requires Claude Code v2.1.292 or later." [Subagents] This is the
  same override the hook already removes for `model`.
- **Observed.** Evidence E2: with the hook stripping `model` only, a scout
  dispatched with `effort: "max"` ran Haiku 5.5 at `max` against its
  frontmatter's `low`. With `effort` stripped too it ran at `low`.
- **The frontmatter stays the single routing authority.** The bundle already
  treats `effort` as a routing field: `profile-test.sh` pins it and the
  alignment check reports it as `DRIFT`. A pin that covered only `model` left
  half of each role's routing to whatever the caller passed.
- **`general-purpose` stays open** for the same reason as for `model`:
  Superpowers picks per task.

## What the hook does not cover

`CLAUDE_CODE_EFFORT_LEVEL` "takes precedence over both" the per-call parameter
and the `effort` field [Subagents], and over Build's saved level too. It is an
environment variable, not part of the Agent call, so no `PreToolUse` hook can
remove it. Exported in the shell, the alignment check cannot see it; set under
`env` in `settings.json`, it is the user's own setting, which the check never
reports. It is left as the user's explicit override and documented in the
README: unset, the profile applies.

## Consequences

The hook's input contract is unchanged: it still never sets
`permissionDecision`, still exits 0 with no output when there is nothing to
strip, and still fails open. An installed profile needs the hook re-copied;
until then the alignment check reports its content as `DRIFT`.

## Evidence boundary

Evidence E2 in
[`../evidence/2026-10-09-capability.md`](../evidence/2026-10-09-capability.md),
on Claude Code 2.1.295. Documentation as read on 2026-10-09:

- [Subagents]

[Subagents]: https://code.claude.com/docs/en/subagents#choose-an-effort-level

Later corrections are appended as dated addenda, never edited in place.
