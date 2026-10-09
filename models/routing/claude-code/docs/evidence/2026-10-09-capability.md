# Claude Code Routing Capability Evidence — 2026-10-09

Claude Code 2.1.295, 2026-10-09. The 2026-10-06 evidence was taken on 2.1.291,
so the mechanism probes the bundle depends on were repeated before any model
change. Method as in [`2026-10-06-capability.md`](2026-10-06-capability.md):
`claude -p` in a scratch project whose `.claude/` held probe copies of the
agents, each probe agent on a different model from its session, read through
`modelUsage` in the JSON output.

One difference: the routing bundle is now installed under `~/.claude`, and its
user-level hook would contaminate the no-hook control. Every probe therefore
ran with `--setting-sources project,local` and without the parent session's
`CLAUDE_*` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` variables, so no user setting,
hook or env applied. Nothing under `~/.claude` was changed.

## Mechanism probes, repeated

| Probe | Question | Setup | Observed | Verdict |
|---|---|---|---|---|
| P1 | Does a per-call `model` beat frontmatter? | Sonnet session; probe `reviewer` on Haiku 4.5; dispatch with `model: "sonnet"`; no hook | `modelUsage`: `claude-sonnet-5-5` only; reviewer answered `PONG` | `CONFIRMED` |
| P2 | Does the hook pin the frontmatter model? | Same as P1, with `pin-agent-model.sh` registered as a project `PreToolUse` hook on `Agent` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5`; reviewer answered `PONG` | `EFFECTIVE`, with no `permissionDecision` |
| P3 | Does a project `Explore.md` override the built-in? | Haiku 4.5 session; probe `Explore` on Sonnet; dispatch without `model` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5` | `OVERRIDES` |
| P4 | Does `--agent` apply the agent model to the main thread? | `claude -p --agent planner`, probe planner on Haiku 4.5, no `--model` | `modelUsage`: `claude-haiku-4-5` only; result `OK` | `APPLIES` |
| P5b | Is a plain `tools` allowlist enforced? | Probe reviewer `tools: Read, Grep, Glob`; session `--allowedTools Bash Write Edit`; reviewer asked to Write `written-probe` and `touch touched-probe` | Neither file created; reviewer reported only Read, Grep and Glob available | `ENFORCED` |

Every verdict matches 2.1.291. P5 was not repeated: its outcome only removed
`Bash(...)` patterns, and P5b covers the allowlist that replaced them.

## Successful-call capability

`claude -p --model <id> [--effort <level>] --output-format json 'Reply with exactly OK'`:

| Model | Effort | Role | is_error | result | modelUsage |
|---|---|---|---|---|---|
| `claude-haiku-5-5` | `medium` | Explore | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-haiku-5-5` | `low` | Scout | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-fable-5-1` | `xhigh` | Expert (proposed; the profile still runs Opus 5.5 `max`) | `False` | `'OK'` | `claude-fable-5-1` |

The Fable call that failed on 2026-10-06 with "Fable 5.1 requires usage
credits" now succeeds.

## Haiku slot

`ANTHROPIC_DEFAULT_HAIKU_MODEL` decides what the `haiku` alias resolves to,
which is the model Claude Code uses for background functionality. Calls with
`--model haiku`, no effort:

| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | is_error | result | modelUsage |
|---|---|---|---|
| `claude-haiku-5-5` | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-haiku-4-5` (control) | `False` | `'OK'` | `claude-haiku-4-5` |
| unset | `False` | `'OK'` | `claude-haiku-5-5` |

The control shows the variable is what selects the model. Unset, the alias
already resolves to Haiku 5.5 on the Anthropic API, as the model configuration
documentation states; the fragment pins it so the profile does not move with
Claude Code's default.

No background task was observed directly: a `-p` run gives no reliable trigger
for one. What is shown is that the slot resolves to the pinned model.

## Dispatch from a Build session

Build session `--model claude-opus-5-5 --effort high`, the hook registered,
probe copies of the agents as committed (`Explore`: `claude-haiku-5-5`,
`effort: medium`; `scout`: `claude-haiku-5-5`, `effort: low`). Each was
dispatched the way Superpowers does, with an explicit `model: "sonnet"`, and
logged with `--debug-file`. The session's haiku slot was set to
`claude-haiku-4-5`, so a background request or a built-in agent on the `haiku`
alias would show as Haiku 4.5, and `claude-haiku-5-5` can only come from the
agent's frontmatter.

| Agent | Hook in the debug log | Model dispatches in the debug log, in order | modelUsage | Result |
|---|---|---|---|---|
| `Explore` | `modified tool input keys: [description, prompt, subagent_type, run_in_background]` (`model` removed) | `claude-opus-5-5`, hook, `claude-haiku-5-5` ×2, `claude-opus-5-5` | `claude-haiku-5-5`, `claude-opus-5-5` | listed the directory |
| `scout` | same keys, `model` removed | `claude-opus-5-5`, hook, `claude-haiku-5-5`, `claude-opus-5-5` | `claude-haiku-5-5`, `claude-opus-5-5` | `PONG` |

**Model: `VERIFIED`.** The frontmatter model applies: `sonnet` never appears,
and neither does the slot's `claude-haiku-4-5`.

**Effort: `NOT_OBSERVABLE`**, as P6 was on 2.1.291. The debug log names each
request's model and no effort value. A repeat of the scout dispatch with
`ANTHROPIC_LOG=debug` shows the Haiku 5.5 request carrying an `output_config`
body field and the `effort-2025-11-24` beta, but the SDK log collapses the
field to `[Object ...]`, so the value cannot be read. The field is kept: it is
documented, and nothing reported it as unknown.

## Evidence boundary

Discovery and successful-call evidence only; no role-fixture evidence. Haiku
5.5's fitness for Explore and Scout, and Fable 5.1's for Expert, are not shown
here.

## Addendum — 2026-10-09 Expert dispatch on Fable 5.1

Recorded with the [Expert on Fable 5.1](../decisions/2026-10-09-expert-on-fable-5-1.md)
decision. Same setup as the Build-session dispatch above, with the probe
`expert` as committed (`claude-fable-5-1`, `effort: xhigh`, `maxTurns: 6`),
dispatched with `model: "sonnet"` and asked to reply `PONG`:

| Agent | Hook in the debug log | Model dispatches in the debug log, in order | modelUsage | Result |
|---|---|---|---|---|
| `expert` | `modified tool input keys: [description, prompt, subagent_type, run_in_background]` (`model` removed) | `claude-opus-5-5`, hook, `claude-fable-5-1`, `claude-opus-5-5` | `claude-fable-5-1`, `claude-opus-5-5` | `PONG` |

`-p` asks for no consent before billing usage credits, so this shows the route
works, not how an interactive session's consent prompt behaves on a subagent.
