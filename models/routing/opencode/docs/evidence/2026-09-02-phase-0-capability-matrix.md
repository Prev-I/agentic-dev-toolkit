# OpenCode V1 Phase 0 Capability Matrix - 2026-09-02

## Scope

This is runtime capability evidence, not routing-fitness evidence and not
authorization to enter Phase R. Every row is an explicit fresh invocation that
overrode the published routing profile. Production routing configuration and
agent definitions were not changed.

## Environment

- Repository commit: `2176b4647e28fe94b8dd30edef6decf9191848a9`
- OpenCode version: `1.18.26`
- Runtime: `Linux 6.18.33.2-microsoft-standard-WSL2 x86_64`
- Probe window: `2026-09-02T17:04:08+02:00` to
  `2026-09-02T17:04:55+02:00`
- Prompt: `Reply with exactly: CAPABILITY_OK`
- Retries: zero for every recorded probe

`opencode models` listed every provider/model pair below before the direct
probes. Listing is only a discovery signal; the successful calls establish the
capability result.

## Accepted syntax

The runtime accepted this noninteractive form for every matrix row:

```bash
opencode run --model <provider/model> --variant <variant> --format json \
  "Reply with exactly: CAPABILITY_OK"
```

The semantic highest-supported Opus effort has exact accepted syntax `max` in
this runtime. The required `high`, `medium`, `low`, `xhigh`, and `max` values all
had exact accepted syntax where used; no nearest-value substitution or amendment
was required.

## Matrix

| Candidate | Variant | Result | Time (ms) | Observed cost | Pricing | Record |
|---|---|---:|---:|---:|---|---|
| `github-copilot/claude-opus-5` | `max` | `USABLE` | 9250 | 0.1126975 | standard | `eval/records/claude-opus-5-max.json` |
| `github-copilot/claude-opus-5` | `high` | `USABLE` | 9818 | 0.1126975 | standard | `eval/records/claude-opus-5-high.json` |
| `github-copilot/claude-sonnet-5` | `high` | `USABLE` | 9016 | 0.045259 | standard | `eval/records/claude-sonnet-5-high.json` |
| `github-copilot/gpt-5.6-terra` | `high` | `USABLE` | 11264 | 0.0022196 | standard | `eval/records/gpt-5.6-terra-high.json` |
| `github-copilot/gpt-5.6-terra` | `medium` | `USABLE` | 9081 | 0.0022196 | standard | `eval/records/gpt-5.6-terra-medium.json` |
| `github-copilot/gpt-5.6-terra` | `low` | `USABLE` | 11342 | 0.0022196 | standard | `eval/records/gpt-5.6-terra-low.json` |
| `github-copilot/gpt-5.6-luna` | `medium` | `USABLE` | 13630 | 0.00024836 | standard | `eval/records/gpt-5.6-luna-medium.json` |
| `github-copilot/gpt-5.6-luna` | `low` | `USABLE` | 11609 | 0.00022196 | standard | `eval/records/gpt-5.6-luna-low.json` |
| `github-copilot/gpt-5.6-sol` | `high` | `USABLE` | 11418 | 0.0022052 | promotional | `eval/records/gpt-5.6-sol-copilot-high.json` |
| `openai/gpt-5.6-sol` | `xhigh` | `USABLE` | 14255 | 0 | standard | `eval/records/gpt-5.6-sol-openai-xhigh.json` |
| `openai/gpt-5.6-sol` | `max` | `USABLE` | 12529 | 0 | standard | `eval/records/gpt-5.6-sol-openai-max.json` |

Observed cost is the value emitted by the runtime. It is not a normalized price
estimate. `normalized_steady_state_cost` remains `null` in every record because
no approved normalization basis exists. Copilot Sol usage before 2026-09-04 is
tagged `promotional`; it must not establish canonical steady-state cost. The
direct OpenAI provider's emitted zero is retained as observed telemetry, not
interpreted as free steady-state service.

## Agent inventory

`opencode agent list` returned these names and modes in the audited repository:

```text
build (primary)
compaction (primary)
explore (subagent)
general (subagent)
plan (primary)
summary (primary)
title (primary)
expert (subagent)
reviewer (subagent)
scout (all)
```

All expected routing roles are present. This inventory records current runtime
resolution only; it does not validate the historical production model IDs or
activate replacement routing.

## Conclusion

The required Phase 0 candidates and variants are callable through the accepted
OpenCode V1 syntax in this environment. Role fitness, comparative selection,
continuous thresholds, budgets, and restoration remain separate gated work.
