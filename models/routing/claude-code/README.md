# Claude Code model routing

A Claude Code port of the [OpenCode routing bundle](../opencode/README.md),
using Anthropic models only. It carries over the deterministic role-to-model
map, the semantic routing policy and the alignment check (layers A and B of
the OpenCode bundle). Role fixtures and session observation (layer C) are not
part of it.

Design: [`docs/superpowers/specs/2026-10-06-claude-code-model-routing-design.md`](../../../docs/superpowers/specs/2026-10-06-claude-code-model-routing-design.md).
Selection rationale: [initial routing decision](docs/decisions/2026-10-06-initial-claude-code-routing.md),
amended by [Haiku roles on Haiku 5.5](docs/decisions/2026-10-09-haiku-roles-on-haiku-5-5.md) and
[Expert on Fable 5.1](docs/decisions/2026-10-09-expert-on-fable-5-1.md).

## Model map

| Role | Where | Model | Effort |
|---|---|---|---|
| Build (main session) | `settings.fragment.json` | `claude-opus-5-5` | `high` |
| Plan | `agents/planner.md` | `claude-opus-5-5` | `xhigh` |
| General | `agents/general-purpose.md` | `claude-sonnet-5-5` | `medium` |
| Explore | `agents/Explore.md` | `claude-haiku-5-5` | `medium` |
| Scout | `agents/scout.md` | `claude-haiku-5-5` | `low` |
| Reviewer | `agents/reviewer.md` | `claude-opus-5-5` | `high` |
| Expert | `agents/expert.md` | `claude-fable-5-1` | `xhigh` |
| Background tasks | `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `claude-haiku-5-5` | — |

The background slot has no effort setting of its own; see deviation 4.
`eval/tests/docs-test.sh` fails if this table disagrees with the agent files or
the settings fragment.

## How routing works

Two layers, as in the OpenCode bundle:

- **Deterministic: which model a role runs on.** Each agent's frontmatter
  declares `model` and `effort`; the settings fragment does the same for the
  main session. These files are the only routing authority.
- **Semantic: which role gets which work.** `model-routing.md` tells the
  controller when to use `general-purpose`, `reviewer`, `expert`, `Explore`,
  `scout` and `planner`. It never names a model.

Superpowers passes an explicit `model` on every subagent dispatch, and on
Claude Code a per-call `model` beats the agent's frontmatter.
`hooks/pin-agent-model.sh` is a `PreToolUse` hook on `Agent` that removes
`model` from calls to `reviewer`, `expert`, `scout`, `Explore` and `planner`,
so their frontmatter applies. `general-purpose` is left alone, so Superpowers
can still pick a cheaper or stronger model per task.

The hook pins `model` only. Frontmatter `effort` is overridden by a per-call
`effort` on the Agent tool (Claude Code 2.1.292 and later) and by
`CLAUDE_CODE_EFFORT_LEVEL`. The hook pins neither and the alignment check,
which reads files only, cannot see either; see the [Haiku 5.5 decision](docs/decisions/2026-10-09-haiku-roles-on-haiku-5-5.md).

The hook never approves anything and never blocks: if it fails, Claude Code
reports a non-blocking error and routing falls back to the policy alone.

Planning is a separate session: `claude --agent planner` runs the planner as
the main thread. Its plan is then handed to an ordinary (Build) session.

## Known deviations from the OpenCode bundle

1. **Reviewer is not independent of Build by model.** Both run Opus 5.5
   `high`. Independence comes from a fresh context and a read-only,
   review-only prompt. Moving Reviewer to Fable 5.1 is the lever if reviews
   fall short. On this account Fable 5.1 bills to usage credits (see the
   [Expert decision record](docs/decisions/2026-10-09-expert-on-fable-5-1.md)),
   and the move is a profile change with its own decision record.
2. **No provider separation for Expert.** Everything runs on one Anthropic
   account. Model and cost-tier separation is restored: Expert runs Fable 5.1
   `xhigh`, the scarce tier, while Build, Plan and Reviewer run Opus 5.5. It
   also differs by a six-turn cap and escalation-only use. On this account
   Fable 5.1 bills to usage credits, and an interactive session asks for
   consent before the first Fable request that does; see the
   [Expert decision record](docs/decisions/2026-10-09-expert-on-fable-5-1.md).
3. **No Breakglass.** It existed for a separate provider and credential, and
   there is none here.
4. **Compaction and session titles are not routable per role.** Claude Code
   has no separate compaction setting; background tasks use the haiku slot,
   pinned to Haiku 5.5. Its effort is not configurable separately: Claude Code
   documents no effort control for background functionality, so it runs at
   whatever effort Claude Code applies to Haiku 5.5, not one this bundle sets.
5. **Plan is a launch choice, not a mode switch.** OpenCode switches primary
   agents inside a session; here planning is its own session.
6. **Reviewer and Explore have no shell.** OpenCode let Reviewer run
   `git status/diff/log/show` only. Claude Code ignores `Bash(...)` patterns in
   a subagent's `tools` and grants unrestricted Bash instead (evidence P5), so
   both get `Read, Grep, Glob` only. The caller hands Reviewer the diff as a
   file; `model-routing.md` says how.

## Install

These are copies, not links. They assume the default `~/.claude`; with
`CLAUDE_CONFIG_DIR` set, use that directory everywhere below, including in the
fragment's hook command. Back up first; each install gets its own dated copy:

```bash
[ ! -e ~/.claude/settings.json ] || \
  cp ~/.claude/settings.json ~/.claude/settings.json.pre-claude-code-routing.$(date +%Y%m%d%H%M%S)
mkdir -p ~/.claude/agents ~/.claude/hooks ~/.claude/rules
cp models/routing/claude-code/agents/*.md ~/.claude/agents/
cp -p models/routing/claude-code/hooks/pin-agent-model.sh ~/.claude/hooks/
cp models/routing/claude-code/model-routing.md ~/.claude/rules/
```

`cp` overwrites agent files with the same names. Check `~/.claude/agents/`
before copying if you keep your own `Explore.md` or `general-purpose.md`.

Merge the settings fragment. This sets the routing-owned keys, adds to `env`,
appends the hook entry once, and leaves every other key alone:

```bash
python3 - models/routing/claude-code/settings.fragment.json ~/.claude/settings.json <<'PY'
import json, sys
from pathlib import Path
fragment = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
settings = json.loads(target.read_text()) if target.exists() else {}
settings["model"] = fragment["model"]
settings["effortLevel"] = fragment["effortLevel"]
settings.setdefault("env", {}).update(fragment["env"])
pre = settings.setdefault("hooks", {}).setdefault("PreToolUse", [])
for entry in fragment["hooks"]["PreToolUse"]:
    if entry not in pre:
        pre.append(entry)
target.write_text(json.dumps(settings, indent=2) + "\n")
PY
```

To roll back, remove exactly what the merge added, and keep every change you
made since:

```bash
python3 - ~/.claude/settings.json <<'PY'
import json, sys
from pathlib import Path
target = Path(sys.argv[1])
settings = json.loads(target.read_text())
settings.pop("model", None)
settings.pop("effortLevel", None)
env = settings.get("env", {})
env.pop("ANTHROPIC_DEFAULT_HAIKU_MODEL", None)
if not env:
    settings.pop("env", None)
hooks = settings.get("hooks", {})
hooks["PreToolUse"] = [
    entry for entry in hooks.get("PreToolUse", [])
    if not any(str(hook.get("command", "")).rstrip("\"'").endswith("pin-agent-model.sh")
               for hook in entry.get("hooks", []))
]
if not hooks["PreToolUse"]:
    hooks.pop("PreToolUse")
if not hooks:
    settings.pop("hooks", None)
target.write_text(json.dumps(settings, indent=2) + "\n")
PY
rm ~/.claude/agents/{planner,general-purpose,Explore,scout,reviewer,expert}.md \
  ~/.claude/hooks/pin-agent-model.sh ~/.claude/rules/model-routing.md
```

This removes `model` and `effortLevel` outright. If you had your own values
before installing, take them back from the dated backup.

## Alignment check

```bash
bash models/routing/claude-code/eval/check-alignment.sh [--json report.json]
```

It compares the bundle with `$CLAUDE_CONFIG_DIR` (default `~/.claude`). It
makes no model calls and changes nothing. Exit `0` aligned, `1` drift, `2`
usage error or nothing installed.

| Severity | Covers | Fails |
|---|---|---|
| `DRIFT` | settings `model`, `effortLevel`, `env.ANTHROPIC_DEFAULT_HAIKU_MODEL`, the hook registration; each agent's `model`, `effort`, `tools`, `disallowedTools`, `maxTurns`, `permissionMode`; the hook script's content and exec bit; a missing agent, hook or policy file | yes |
| `STALE` | agent prompt bodies; the policy's content | no |

Everything else in your configuration is yours and is never reported. It
never repairs: decide per item, then re-copy the bundle file or fix the
repository.

## Tests

```bash
bash models/routing/claude-code/eval/run-tests.sh
```

No model calls. The suites cover the parser, the hook, the pinned profile,
the alignment check, this README's model map, and its merge and rollback
snippets, which they run verbatim against a sample `settings.json`.

## Verification status

The profile is **capability-verified, not role-verified**. Live checks of the
mechanisms this bundle relies on, and one trivial successful call per model
and effort pair, are recorded in
[`docs/evidence/2026-10-06-capability.md`](docs/evidence/2026-10-06-capability.md)
and, for Claude Code 2.1.295 and the Haiku 5.5 and Fable 5.1 pairs,
[`docs/evidence/2026-10-09-capability.md`](docs/evidence/2026-10-09-capability.md).
Role fixtures, which would show each model is fit for its role, are out of
scope.

## Smoke tests

After installing, in a new session:

1. Ask where something is implemented before editing. Expected helper: `Explore`.
2. Ask how a dependency's current release behaves. Expected helper: `scout`.
3. Run a Superpowers task review. Expected reviewer: `reviewer`, not `general-purpose`.
4. Present an unresolved security or public-API decision. Expected: escalation
   to `expert` with a seven-item decision packet, and no implementation by it.
5. Start `claude --agent planner` and ask for a plan. Expected: a plan, no edits.
