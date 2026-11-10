# Claude Code Routing Capability Evidence — 2026-11-10

Claude Code 2.1.322, 2026-11-10. Recorded with the
[Expert on Fable 5.2](../decisions/2026-11-10-expert-on-fable-5-2.md) decision.
Method as in [`2026-10-09-capability.md`](2026-10-09-capability.md), with one
difference: the call ran from a scratch directory with the user's installed
`~/.claude` settings and hook loaded, not with `--setting-sources
project,local`. `CLAUDE_CODE_EFFORT_LEVEL` was unset, and the installed
settings carry no top-level `effortLevel`, so `--effort xhigh` was the only
effort input.

## Successful-call capability

`claude -p --model <id> --effort <level> --output-format json 'Reply with exactly OK'`:

| Model | Effort | Role | is_error | result | modelUsage |
|---|---|---|---|---|---|
| `claude-fable-5-2` | `xhigh` | Expert | `False` | `'OK'` | `claude-fable-5-2` |

## Evidence boundary

One successful call only. The mechanism probes and the Build-session dispatch
were not repeated on 2.1.322, and Fable 5.2's fitness for Expert is not shown.
`-p` bills without a consent prompt, so this says nothing about how billing or
consent behave for 5.2.
