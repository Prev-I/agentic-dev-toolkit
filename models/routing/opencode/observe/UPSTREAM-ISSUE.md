# Issue draft — not submitted

Target repository: `anomalyco/opencode`

## Title

Compaction inherits the parent message variant instead of its configured agent variant (1.18.32)

## Version

OpenCode **1.18.32**.

## Observed behavior

Automatic compaction honors its configured agent model but inherits the
variant from the parent user message. With parent `xhigh` and compaction `low`,
assistant metadata records `xhigh`; configured `low` does not govern variant
selection on this code path.

This report includes no session IDs, prompts, responses, tool results or file
contents. It is based on metadata inspection and version-pinned source; no new
inference reproduction was run.

## Example configuration

```json
{
  "agent": {
    "plan": {"model": "github-copilot/claude-opus-5.5", "variant": "xhigh"},
    "compaction": {"model": "github-copilot/claude-sonnet-5.5", "variant": "low"}
  }
}
```

Available variants depend on the provider/model. Stored `xhigh` is not proof
that the provider applied that effort. If absent from the compaction model's
variant map, variant-specific options may be absent instead of using `low`.

## Source references

- [`session/compaction.ts` at v1.18.32](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/compaction.ts),
  `processCompaction`: selects `agent.model`, assigns
  `variant: userMessage.model.variant` and passes `user: userMessage` to
  `processor.process`.
- [`session/llm/request.ts` at v1.18.32](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/llm/request.ts),
  `LLMRequestPrep.prepare`: selects
  `input.model.variants[input.user.model.variant]` and merges variant options
  after agent options.

## Expected behavior

An explicit compaction agent variant should be validated against the selected
model and used consistently in assistant metadata and prepared provider
options. Inheritance when no variant is configured, if intended, should be
documented with an explicit fallback for unsupported variants.

## Proposed correction

Resolve the compaction agent variant first and validate it against the model.
Pass a copied user request with that variant to LLM preparation and record the
same value in assistant metadata. Do not mutate the parent user message.

Add source-level regression tests covering parent `xhigh` / compaction `low`,
absent configured variant, unsupported inherited variant, and unchanged parent
metadata. Assert the resolved variant in both metadata and provider options.

No runtime patch, plugin, hook or configuration workaround has been applied.
