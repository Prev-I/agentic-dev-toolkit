# Claude Code Model Routing Design

## Context

`models/routing/opencode/` routes OpenCode work across model families and
providers. It has three layers: (A) a deterministic role-to-model map with
custom `reviewer`, `expert` and `breakglass` agents plus a semantic routing
policy, (B) an alignment check that detects drift between the bundle and the
installed configuration, and (C) an evaluation and observation harness.

This design ports layers A and B to Claude Code, using only Anthropic models.
Layer C is out of scope; it can follow as a separate project.

Three facts shape the port:

- **No provider separation.** OpenCode confined Expert and Breakglass to a
  direct OpenAI connection for quota and credential separation. Claude Code
  runs every role on one Anthropic account. The nearest equivalent is **cost
  separation**: Fable 5.1 costs 2.5× Opus 5.5 per token ($10/$50 vs $4/$20 per
  MTok), so it becomes the scarce tier and is confined to Expert.
- **No model-family diversity.** OpenCode kept Reviewer on a different family
  from the implementers. Here the best available is a different *model*.
- **Superpowers always passes an explicit `model`.** On Claude Code its
  subagent-driven-development skill says "Always specify the model explicitly
  when dispatching a subagent", and a per-invocation `model` takes precedence
  over a subagent's frontmatter `model`. Without enforcement, a role declared on
  Opus can silently run on another model.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Scope | Layers A + B | Usable routing with drift detection; evaluation deferred |
| Profile | Build on Sonnet 5.5; Plan and Reviewer on Opus 5.5; Fable 5.1 only for Expert | Reviewer differs from the implementer model without spending Fable on every review |
| Breakglass | **Dropped** | It existed for a separate provider and credential; there is none here |
| Enforcement | Frontmatter + policy + `PreToolUse` hook on `Agent` | Superpowers' per-call `model` makes a policy-only port unreliable by construction |
| Authority | Agent frontmatter and the settings fragment | No second manifest to keep in sync; the hook knows role names, never models |
| Model IDs | Full IDs, not aliases | An alias follows new releases silently; pinned IDs make drift visible |

Rejected: a policy-only port (soft rule competing with Superpowers'
instructions), and a manifest plus generator (a generator to maintain for seven
files).

## Model map

| Role | Claude Code mechanism | Model | Effort |
|---|---|---|---|
| Build (controller) | main session: settings `model`, `effortLevel` | `claude-sonnet-5-5` | `high` |
| Plan | primary agent `planner`, started with `claude --agent planner` | `claude-opus-5-5` | `xhigh` |
| General | override of built-in `general-purpose` | `claude-sonnet-5-5` | `medium` |
| Explore | override of built-in `Explore` | `claude-haiku-4-5` | — |
| Scout | subagent `scout` | `claude-haiku-4-5` | — |
| Reviewer | subagent `reviewer` | `claude-opus-5-5` | `high` |
| Expert | subagent `expert` | `claude-fable-5-1` | `xhigh` |
| Background | settings `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `claude-haiku-4-5` | — |

Haiku 4.5 does not support `effort`; Explore and Scout declare none.

The agent is named `planner`, not `plan`, to avoid the built-in `Plan`
subagent that Claude Code uses in plan mode.

## Bundle layout

```
models/routing/claude-code/
  README.md                  model map, install, known deviations, smoke tests
  settings.fragment.json     routing-owned keys to merge into ~/.claude/settings.json
  model-routing.md           semantic policy, installed as ~/.claude/rules/model-routing.md
  agents/
    planner.md
    general-purpose.md
    Explore.md
    scout.md
    reviewer.md
    expert.md
  hooks/
    pin-agent-model.sh
  eval/
    run-tests.sh
    check-alignment.sh
    tests/*-test.sh
  docs/
    decisions/2026-10-06-initial-claude-code-routing.md
    evidence/2026-10-06-capability.md
```

The agents deliberately do **not** live under a `.claude/` path. Claude Code
discovers `.claude/agents/` relative to the working directory, so a `.claude/`
directory in the bundle would load these agents into sessions working on the
toolkit itself. The OpenCode bundle avoids the same trap by keeping `.opencode/`
away from the repository root.

## Components

### `settings.fragment.json`

The routing-owned keys, and only those:

```json
{
  "model": "claude-sonnet-5-5",
  "effortLevel": "high",
  "env": { "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5" },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/pin-agent-model.sh" }
        ]
      }
    ]
  }
}
```

Merging means adding these keys. When there is already an `env` object or a
`hooks.PreToolUse` array, the entries are appended without replacing anything
already there. Everything else in the user's settings belongs to the user.

### Agents

Each agent file carries routing fields (`model`, `effort`), permission fields
(`tools`, `disallowedTools`, `maxTurns`, `permissionMode`) and a prompt.

| Agent | Routing and permission contract |
|---|---|
| `planner` | Primary use only. No `Edit`, `Write` or `NotebookEdit`. `permissionMode: plan`. Produces decomposition, risks and acceptance criteria, then hands off to the main session. |
| `general-purpose` | Same tools as the built-in. Delegated implementation and debugging. |
| `Explore` | Read-only: `Read`, `Grep`, `Glob`, and `Bash` limited to `ls`, `git log`, `git show` and `git grep`. Returns context; edits nothing. |
| `scout` | `WebSearch`, `WebFetch`, `Read`, `Grep`, `Glob`. External and upstream research, narrow lookups. |
| `reviewer` | Read-only: `Read`, `Grep`, `Glob`, and `Bash` limited to `git status`, `git diff`, `git log` and `git show`. No `Agent`. Independent review returning findings. |
| `expert` | `Read`, `Grep`, `Glob` only. `disallowedTools` covers `Edit`, `Write`, `NotebookEdit`, `Bash`, `WebFetch`, `WebSearch` and `Agent`. `maxTurns: 6`. Advisory response to a decision packet; never implements. |

### `model-routing.md`

It is the Claude Code version of `.opencode/model-routing.md`: it assigns work
to roles and never assigns a model. It contains:

- **Role descriptions** for the seven roles above.
- **Superpowers mapping:**
  - implementation goes to `general-purpose`, with Superpowers' own model
    tiering left intact;
  - code review and re-review go to `reviewer`, using Superpowers'
    `code-reviewer.md` template as the prompt;
  - escalation beyond the reviewer's confidence goes to `expert`.
- **The escalation conditions and the seven-item decision packet**, carried
  over unchanged from the OpenCode policy.
- **An instruction to omit `model`** when dispatching `reviewer`, `expert`,
  `scout`, `Explore` or `planner`. The hook enforces this anyway; the
  instruction keeps the transcript honest about intent.

It loads from `~/.claude/rules/`, keeping personal orchestration policy out of
any project's `CLAUDE.md`, for the same reason the OpenCode bundle used
`instructions`.

### `hooks/pin-agent-model.sh`

A `PreToolUse` command hook matched on `Agent`. It reads the hook JSON from
stdin and:

1. If `tool_input.subagent_type` is one of `reviewer`, `expert`, `scout`,
   `Explore` or `planner`, **and** `tool_input` contains `model`, it prints a
   `hookSpecificOutput` with `hookEventName: PreToolUse` and an `updatedInput`
   equal to `tool_input` without `model`. Resolution then falls to the agent's
   frontmatter.
2. Otherwise it prints nothing and exits 0. `general-purpose` and every other
   agent pass through unchanged.

It never sets `permissionDecision`, so it never bypasses a permission prompt.
It never parses agent files or names a model: the role list is its only
knowledge, so frontmatter remains the single authority.

**It fails open.** On malformed input or a missing interpreter it writes a
diagnostic to stderr and exits 1, which Claude Code reports as a non-blocking
error. It never exits 2. A broken hook degrades routing to the policy layer
instead of blocking every delegation.

Implementation is bash with an inline `python3` JSON step, matching the
toolkit's existing test prerequisites.

### `eval/check-alignment.sh`

It compares the bundle with the installed configuration and follows the same
contract as the OpenCode check: no arguments needed, no model calls, and it
never changes anything.

- **Installed root:** `$CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`.
- **Exit codes:** `0` aligned, or only `STALE`; `1` any `DRIFT`; `2` usage
  error or nothing installed.
- **`--json PATH`** writes a machine-readable report.

| Severity | Covers | Fails |
|---|---|---|
| `DRIFT` | settings `model`, `effortLevel`, `env.ANTHROPIC_DEFAULT_HAIKU_MODEL`, presence of the hook registration; each bundled agent's `model`, `effort`, `tools`, `disallowedTools`, `maxTurns`, `permissionMode`; byte content of the hook script | yes |
| `STALE` | agent prompt bodies; `rules/model-routing.md` content | no |

Anything else in the user's configuration is never reported: other settings,
other hooks, other agents, other rules. It never repairs, because drift is
sometimes deliberate.

### `eval/run-tests.sh`

It runs `eval/tests/*-test.sh` with the same summary format and exit semantics
as the OpenCode runner, and makes no model calls.

| Test | Asserts |
|---|---|
| `profile-test.sh` | The model map above exactly, per agent and in the fragment. The Expert and Reviewer permission invariants. No agent named `breakglass`. Changing the profile requires changing this test on purpose. |
| `hook-test.sh` | Reviewer with `model` gets an `updatedInput` without `model`. `general-purpose` with `model` gets no output. A tool other than `Agent` gets no output. Malformed JSON exits 1 with stderr and never 2. No output ever contains `permissionDecision`. |
| `alignment-test.sh` | Against a temporary `CLAUDE_CONFIG_DIR`: an aligned install exits 0; a changed agent `model` exits 1 with `DRIFT`; a changed prompt body exits 0 with `STALE`; an empty directory exits 2. User-owned extras are not reported. |
| `docs-test.sh` | The README model table matches the frontmatter and the fragment. |

## Verification before claiming the profile usable

The official documentation does not confirm everything this design relies on.
Each item below is checked live once and recorded in
`docs/evidence/2026-10-06-capability.md`, together with its fallback:

| Unconfirmed | Check | Fallback if false |
|---|---|---|
| Frontmatter `effort` takes effect | Dispatch a subagent with `effort` set and inspect the session transcript or debug output | Drop `effort` from the frontmatter and document that subagent effort follows the session |
| `--agent planner` applies the agent's model to the main thread | Start `claude --agent planner -p` and confirm which model answered | Document `claude --agent planner --model claude-opus-5-5 --effort xhigh` as the launch command |
| `~/.claude/rules/*.md` loads at user level | Start a session and confirm the rule is in context (`/memory` or `/context`) | Import with `@~/.claude/model-routing.md` from `~/.claude/CLAUDE.md` |
| `tools` accepts `Bash(git diff:*)`-style patterns | Ask the reviewer to run a disallowed git command | Give Reviewer and Explore no `Bash`; the caller supplies the diff in the prompt |
| A `PreToolUse` hook can rewrite `Agent` input without `permissionDecision` | Dispatch `reviewer` with an explicit `model` and confirm the frontmatter model ran | Fall back to the policy-only layer and record the hook as `NOT_EFFECTIVE` |

Each `(model, effort)` pair also gets one trivial successful call with
`claude -p --model <id> --effort <level> --output-format json`. This follows
the OpenCode evidence hierarchy: documentation gives candidates, a successful
call proves usable capability, and a role fixture proves routing fitness. Role
fixtures are layer C and out of scope, so the profile is recorded as
*capability-verified*, not *role-verified*.

## Known deviations from the OpenCode bundle

1. **No family diversity.** Reviewer (Opus) differs from Build and General
   (Sonnet) by model, not by family.
2. **No provider separation.** Cost separation replaces it: Fable only on
   Expert.
3. **No Breakglass.** Its reason for existing does not apply.
4. **Compaction and title are not routable per role.** Claude Code has no
   separate compaction setting; background tasks use the haiku slot, pinned to
   Haiku 4.5.
5. **Plan is a launch choice, not a mode switch.** OpenCode switches primary
   agents inside a session; here planning is a separate `claude --agent planner`
   session that hands its plan to a Build session.

## Installation

Installation is a manual copy guided by the README, as for OpenCode:

```text
agents/*.md              -> ~/.claude/agents/
hooks/pin-agent-model.sh -> ~/.claude/hooks/  (executable)
model-routing.md         -> ~/.claude/rules/model-routing.md
settings.fragment.json   -> merged into ~/.claude/settings.json
```

Afterwards, `check-alignment.sh` reports whether the installed copy still
matches. An activation script with backup-and-merge is follow-up work and not
part of this design.

## Repository changes outside the bundle

The toolkit's `AGENTS.md` changes in three places:

- The layout lists `models/routing/claude-code/`.
- The commands add `bash models/routing/claude-code/eval/run-tests.sh`.
- The required-suites count goes from seven to eight.

The project overview line ("a model-routing bundle for OpenCode") names both
harnesses.

## Out of scope

- Layer C: role fixtures, scoring, and session observation.
- An activation or installer integration.
- Routing for Codex.
- Any change to the OpenCode bundle.
