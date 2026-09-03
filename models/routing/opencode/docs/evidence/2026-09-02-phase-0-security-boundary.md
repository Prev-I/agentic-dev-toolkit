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

## Runtime result

`eval/records/breakglass-boundary.json` records the live boundary probe:

- explicit `--agent breakglass` selected the primary Breakglass agent and the
  configured direct OpenAI model;
- the normal model did not emit the requested Task attempt in the latest run,
  so no structured runtime denial event was captured;
- the explicit provider call failed with `usage limit has been reached`, so
  this run does not claim a successful Breakglass response.

The generated configuration and deterministic adapter tests establish the
ordered `breakglass: deny` rule, reject unstructured denial or selection text,
and require all live conditions before returning success. The current live
record is therefore correctly blocked rather than accepted as closure. Earlier
direct capability records remain timestamped evidence, not a guarantee of
continuing quota availability.
