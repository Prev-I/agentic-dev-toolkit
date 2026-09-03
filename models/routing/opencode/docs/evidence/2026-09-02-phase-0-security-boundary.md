# Phase 0 Routing Security Boundary

## Scope

This evidence uses a generated non-production profile. It does not alter or
activate the published routing profile.

## Reviewer and Expert

`opencode debug agent` was captured into the sanitized records
`eval/records/reviewer-permissions.json` and
`eval/records/expert-permissions.json` on OpenCode `1.18.26`.

- Reviewer resolves as a subagent with edits and nested Task denied. Bash is
  deny-by-default with only `git status*`, `git diff*`, `git log*`, and
  `git show*` allowed.
- Expert resolves as a subagent with edits, Bash, nested Task, web fetch, and
  web search denied.

These checks inspect resolved V1 permissions and tool availability rather than
assuming frontmatter semantics.

## Breakglass

Investigation established that `mode: primary` alone is not a Task security
boundary in OpenCode V1: a Task caller can attempt a named primary agent. The
effective boundary is the normal caller's ordered Task permission:

```json
{
  "*": "allow",
  "breakglass": "deny"
}
```

The specific deny removes or blocks Breakglass from normal Task routing while
retaining direct human selection of the primary agent. The non-production
profile validator therefore requires all of these conditions:

- profile is explicitly non-production;
- Breakglass mode is `primary`;
- model and variant are `openai/gpt-5.6-sol` and `max`;
- human selection only is true;
- Task routability is false;
- normal-agent Task permission explicitly denies `breakglass`.

`hidden` is intentionally ignored by the validator because discoverability is
not authorization. No autonomous escalation path is present.

## Normal-agent runtime result

OpenCode V1 `1.18.26` exposes resolved agent permissions and inventory through
`opencode debug agent`, but no standalone command was found that serializes the
exact model-facing Task-target schema. The strongest prompt-independent runtime
evidence is therefore `resolved_permission_and_inventory`:

- the normal non-production agent resolves broad Task allow followed by a
  specific `breakglass` deny under V1's last-match-wins semantics;
- Breakglass resolves as `primary`, `openai/gpt-5.6-sol`, `max`;
- prompt behavior is not used as the oracle.

`eval/records/breakglass-normal-agent-non-exposure.json` records this boundary
as passing. A model is not required to emit a forbidden Task attempt merely to
prove non-exposure.

## Human-primary runtime result

`eval/records/breakglass-boundary.json` records the live boundary probe:

- explicit `--agent breakglass` selected the primary Breakglass agent and the
  configured direct OpenAI model;
- the normal model did not emit the requested Task attempt in the latest run,
  so no structured runtime denial event was captured;
- the explicit provider call failed with `usage limit has been reached`, so
  this run does not claim a successful Breakglass response.

The previous combined probe required a model-emitted Task attempt and therefore
does not determine the normal-agent non-exposure result. Its failed direct
OpenAI execution remains valid historical evidence and is preserved. A separate
human-primary attempt on 2026-09-03 selected the resolved primary
`openai/gpt-5.6-sol` `max` agent, completed successfully, and returned the exact
`BREAKGLASS_PRIMARY_OK` text event. The immutable attempt record is
`eval/records/breakglass-primary-attempt-2026-09-03.json` and is classified
`PASS` with retry count zero. Earlier direct capability records remain
timestamped evidence, not a guarantee of continuing quota availability.
