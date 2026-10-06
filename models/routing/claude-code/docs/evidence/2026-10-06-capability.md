# Claude Code Routing Capability Evidence

Claude Code 2.1.291, 2026-10-06. Probes ran with `claude -p` in a scratch
project whose `.claude/` held probe copies of the agents. Each probe agent ran
a different model from its session, so `modelUsage` in the JSON output shows
which configuration won. Nothing under `~/.claude` was changed.

## Mechanism probes

| Probe | Question | Setup | Observed | Verdict |
|---|---|---|---|---|
| P1 | Does a per-call `model` beat frontmatter? | Sonnet session; probe `reviewer` on Haiku; dispatch with `model: "sonnet"`; no hook | `modelUsage`: `claude-sonnet-5-5` only; reviewer answered `PONG` | `CONFIRMED` |
| P2 | Does the hook pin the frontmatter model? | Same as P1, with `pin-agent-model.sh` registered as a project `PreToolUse` hook on `Agent` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5`; reviewer answered `PONG` | `EFFECTIVE`, with no `permissionDecision` |
| P3 | Does a project `Explore.md` override the built-in? | Haiku session; probe `Explore` on Sonnet; dispatch without `model` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5` | `OVERRIDES` |
| P4 | Does `--agent` apply the agent model to the main thread? | `claude -p --agent planner`, probe planner on Haiku, no `--model` | `modelUsage`: `claude-haiku-4-5` only; result `OK` | `APPLIES` |
| P5 | Do `Bash(...)` patterns in `tools` restrict the subagent? | Probe reviewer `tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*)`; session `--allowedTools Bash`; reviewer asked to `touch denied-probe` | `denied-probe` was created; the reviewer reported `touch` succeeded | `FALLBACK`: the patterns are ignored and Bash is unrestricted |
| P5b | Is a plain `tools` allowlist enforced? | Probe reviewer `tools: Read, Grep, Glob`; session `--allowedTools Bash Write Edit`; reviewer asked to Write a file and `touch` another | Neither file created; reviewer reported only Read, Grep and Glob available | `ENFORCED` |
| P6 | Is frontmatter `effort` applied? | `--debug` reviewer dispatches, once with `ANTHROPIC_LOG=debug`; probe reviewer on Sonnet with `effort: high`, session `--effort low` | The debug log names each request's model (`dispatching to firstParty model=…`) but no effort value; nothing reported the field as unknown | `NOT_OBSERVABLE`: field kept, as it is documented |

P2 against P1 is the control pair. The only difference is the hook, and
Haiku, the frontmatter model, appears only with the hook present.

P6 also shows that dispatching `reviewer` with no `model` runs the frontmatter
model: the debug log has one `claude-haiku-4-5` dispatch in a Sonnet session.

## Successful-call capability

`claude -p --model <id> [--effort <level>] --output-format json 'Reply with exactly OK'`:

| Model | Effort | is_error | result | modelUsage |
|---|---|---|---|---|
| `claude-opus-5-5` | `high` | `False` | `'OK'` | `claude-opus-5-5` |
| `claude-opus-5-5` | `xhigh` | `False` | `'OK'` | `claude-opus-5-5` |
| `claude-opus-5-5` | `max` | `False` | `'OK'` | `claude-opus-5-5` |
| `claude-sonnet-5-5` | `medium` | `False` | `'OK'` | `claude-sonnet-5-5` |
| `claude-haiku-4-5` | — | `False` | `'OK'` | `claude-haiku-4-5` |
| `claude-fable-5-1` | `xhigh` | `True` | `'Fable 5.1 requires usage credits. Switch to another model to continue.'` | — |

The Fable failure moved Expert to `claude-opus-5-5` at `max`; see the
decision record's addendum. The `max` row was run after that decision.

## Consequences applied

- P5: Reviewer and Explore now have `tools: Read, Grep, Glob`. The routing
  policy tells the caller to hand Reviewer the change as a file.
- Fable: Expert moved to Opus 5.5 `max`.

## Evidence boundary

Discovery and successful-call evidence only; no role-fixture evidence. The
user-level rules check and the installed hook are recorded in the addendum
after installation.
