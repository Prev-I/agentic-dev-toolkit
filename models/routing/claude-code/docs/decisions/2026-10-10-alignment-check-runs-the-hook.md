# The Alignment Check Runs the Hook

## Decision

`check-alignment.sh` now runs the installed `pin-agent-model.sh` when, and
only when, its bytes match the bundle's and it is executable. It runs it
twice, each time on a synthetic Agent dispatch on stdin, from a fresh empty
temporary directory, with the check's own environment minus the
`PYTHONPATH` and `PYTHONDONTWRITEBYTECODE` its wrapper adds, and with a
15-second limit. The hook leads its own process group, which is killed at the
limit or if the check itself is interrupted; the mise query the hook starts
under `timeout` runs in a group of its own and is bounded by `timeout`
instead:

| Dispatch | Expected |
|---|---|
| `reviewer` with `model`, `effort` and extra members of several JSON types | exit 0, and stdout exactly `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": <the input without model and effort>}}` |
| `general-purpose` with `model` | exit 0, empty stdout |

Anything else is `DRIFT` on `hooks/pin-agent-model.sh`, with a detail that
starts `run:` and names the exit and first line of stderr, the unexpected
output, a failure to start, or the timeout. Output is compared as JSON with
its types, so `true` and `1` differ. stderr on exit 0 is ignored: "Claude
never sees stderr from a hook that exits 0." [Hooks exit code 0] Exit codes and the JSON report's shape are unchanged.
The installed file is executed directly, never the `command` string from
`settings.json`.

## Rationale

- **The hook fails open, so its failures are silent.** When it exits with
  "any other code" than 0 or 2, "the action goes ahead" [Hooks exit codes]:
  the dispatch runs unpinned and the transcript shows a hook error notice.
  The byte comparison cannot see a hook that is installed correctly but cannot
  run, and the check was the only place that could say so.
- **Observed.** Evidence H3: with the bundle installed byte for byte and mise
  naming an interpreter that fails, the earlier check reported `ALIGNED`, exit
  0; this one reports `DRIFT  hooks/pin-agent-model.sh  run: exit 1: broken
  interpreter`, exit 1. Against the real mise it reports `ALIGNED` in 85 ms.
- **The run is representative now.** After
  [The Hook Resolves Python Through mise](2026-10-10-hook-resolves-python-through-mise.md)
  the hook asks mise for its interpreter from `$HOME`, not from the session's
  directory, so whenever mise resolves one, a single run from a temporary
  directory exercises the interpreter every session uses. Before that change a
  run from any one directory would have proved little.
- **Behaviour, not presence.** The repository's own `AGENTS.md` runs the git
  credential wrapper "against a stub delegate and asserts the decision, rather
  than checking that a file exists", and verifies the az shim the same way.
  The hook is the same kind of component.
- **Running it costs one dispatch's side effects.** Only bytes that match the
  bundle are run, the same bytes the test suite runs; automatic installs are
  off inside the hook. The check writes nothing itself outside its temporary
  directory. The hook's `mise which` evaluates mise's configuration, which
  mise says "can still have side effects"; evidence H2 saw nothing new in
  mise's cache from it.
- **Advised by `expert`**, in the same escalation as the interpreter change,
  including the two dispatches, the byte-match gate and the process-group
  kill.

## Consequences

- The check is no longer read-only in the strict sense: it executes a file
  under `~/.claude`. The README, the wrapper's header and the module
  docstring say so.
- A hook that writes to stderr but exits 0 with the expected output is
  `ALIGNED`.
- It runs in the shell that starts it. A Claude Code session launched with a
  different environment, such as the Remote Control unit's `PATH`, is not
  exercised; with mise present both resolve the interpreter from `$HOME`. An
  opt-in run under another `PATH` was considered and left out.
- A failing run only appears when the content already matches. A hook that
  differs is reported as `content differs` and is not run.
- `alignment-test.sh` puts a stub `mise` and a stub `python3` first on
  `PATH` for every run, so the suite never reaches the real mise, and covers
  an interpreter that fails, one that answers without pinning, a modified hook
  that must not run, a hook that cannot start, the timeout through a direct
  call with a one-second limit, and the typed comparison.

## Evidence boundary

Evidence H3 in
[`../evidence/2026-10-10-alignment-hook-run.md`](../evidence/2026-10-10-alignment-hook-run.md),
on mise 2026.9.7. Documentation as read on 2026-10-10:

- [CLI]
- [Hooks exit code 0]
- [Hooks exit codes]

[CLI]: https://mise.jdx.dev/cli/#global-flags
[Hooks exit code 0]: https://code.claude.com/docs/en/hooks#exit-code-0
[Hooks exit codes]: https://code.claude.com/docs/en/hooks#exit-code-output

Later corrections are appended as dated addenda, never edited in place.
