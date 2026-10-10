# Dispatch Trigger Evidence — 2026-10-10

Recorded with
[Explore and Escalation Triggers](../decisions/2026-10-10-explore-and-escalation-triggers.md).
Claude Code 2.1.296.

## S1 — smoke tests on the installed profile

The profile as merged on 2026-10-09 was installed under `~/.claude`, the
alignment check reported `STATUS: ALIGNED`, and smoke tests 1, 2 and 4 from
the README were run by the human in one fresh interactive session. Read
afterwards from that session's transcript and its subagent transcripts:

| Test | Prompt (Italian, as typed) | Observed | Verdict |
|---|---|---|---|
| 1 | where the alignment check computes `DRIFT`, change nothing | Build ran four read-only shell commands and answered; no dispatch | `FAILED` |
| 2 | what changed in OpenSpec's latest release, from upstream notes | `scout` dispatched with no `model` or `effort`; every turn on `claude-haiku-5-5`; WebFetch only | `PASSED` |
| 4 | open security decision: should the pin hook fail open or closed; recommend, do not implement | Build recommended fail-open itself, no dispatch. After the human asked for a second opinion: `expert` dispatched with no `model` or `effort` and a seven-item packet; every turn on `claude-fable-5-1`; Read, Grep and Glob only | `PARTIAL` |

The transcript does not record whether the Fable usage-credit consent prompt
appeared, or the effort of any request.

## D1 — the triggers, old policy against new

Each run was `claude -p` with `--setting-sources project,local`, `--model
claude-opus-5-5 --effort high`, and the parent session's `CLAUDE_*` and
`ANTHROPIC_DEFAULT_HAIKU_MODEL` variables unset, in a local clone of this
repository at `main`. The clone's `.claude/` held the bundle's `Explore`,
`scout` and `expert` agents and the policy under test as
`.claude/rules/model-routing.md`; a run asked to list its loaded instruction
files named only the clone's `CLAUDE.md`, `AGENTS.md` and that rule. The
`expert` copy ran `claude-haiku-5-5` at `low` instead of Fable 5.1 `xhigh`,
with its prompt and description unchanged, so that no run billed usage
credits; the runs measure Build's decision to dispatch, not the expert's
answer. Read, Grep, Glob, Agent and read-only Bash patterns were
pre-approved, plus WebFetch and WebSearch from the intermediate wording's test
2 and test 4 runs on. Two runs recorded permission denials, all for Bash
commands outside those patterns and none for a dispatch: a `main` test 4 run
was refused one compound `ls`, `cat` and `git log` command, and used Read,
Glob and Grep otherwise; a first-wording test 4 run, after it had escalated, was
refused two commands that would have written a planted `json.py` to a
temporary directory and run the hook against it. Prompts were the S1
prompts, and for the control, a question naming `eval/lib/check_alignment.py`
and its `compare()` function.

| Policy | Prompt | Runs | Dispatched |
|---|---|---|---|
| `main` | test 1 | 3 | none in 3; Build used 3–4 Grep, Glob and Read calls |
| first wording ("unless you already know which file…") | test 1 | 3 | none in 3; one run used 4 lookups |
| intermediate wording | test 1 | 3 | `Explore` in 3 |
| intermediate wording | control, file named | 3 | none in 3 |
| as committed | test 1 | 3 | `Explore` in 3 |
| as committed | control, file named | 3 | none in 3 |
| `main` | test 4 | 3 | none in 3 |
| first wording, first escalation paragraph | test 4 | 3 | `expert` in 3, seven-item packet in 3 |
| intermediate wording, first escalation paragraph | test 4 | 3 | `expert` in 3, seven-item packet in 3 |
| as committed | test 4 | 3 | `expert` in 3, seven-item packet in 3 |
| intermediate wording | test 2 | 2 | `scout` in 2 |
| as committed | test 2 | 2 | `scout` in 2 |

The intermediate wording is rule 5 without "If you can dispatch subagents",
the skill clause and the history clause; the first escalation paragraph let
"a human who asks for your view without an escalation" opt out, and rule 3
deferred to all ten conditions. The committed text differs from them only in
those places.

No call carried `model` or `effort`. In every test 1 run that dispatched,
Build first grepped `eval/check-alignment.sh`, the one file it expected to
hold the answer, found no `DRIFT` there, said so and that it was handing the
search to `Explore`, and after `Explore` returned read the cited lines itself
before answering. In the committed policy's test 4 runs Build read the hook
and nearby files first, then escalated, saying in each that it did so
because the human had framed the question as a security decision. In
test 2 it grepped the clone for OpenSpec, before dispatching `scout` under
the intermediate wording and after it under the committed one.

Two or three runs per row on a single prompt show that the wording moves the
decision on these prompts. They do not establish a rate.
