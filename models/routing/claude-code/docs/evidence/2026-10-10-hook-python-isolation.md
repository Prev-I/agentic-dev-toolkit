# Hook Python Isolation Evidence — 2026-10-10

Recorded with
[The Hook Runs Python Isolated](../decisions/2026-10-10-hook-runs-python-isolated.md).
Python 3.12.14 from mise, the `python3` the hook resolves on this
workstation. No Claude Code session was involved: the hook was run directly,
as Claude Code runs it, with a PreToolUse event on stdin.

## H1 — a planted `json.py` against the hook

A scratch directory held a `json.py` that writes a marker file and exits 7. The
hook was given one event, a `scout` dispatch carrying `model: "sonnet"`, which
it must rewrite:

```json
{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"scout","prompt":"p","model":"sonnet"}}
```

It ran twice per version: once with the scratch directory as the working
directory, once from `/tmp` with `PYTHONPATH` pointing at it. The `-I` rows
were taken on the hook as committed, exit-2 remap included.

| Hook | `json.py` reached through | Exit | Output | Planted module |
|---|---|---|---|---|
| `python3 -c`, as on `main` before this change | working directory | 7 | none | **ran** |
| `python3 -c`, as on `main` before this change | `PYTHONPATH` | 7 | none | **ran** |
| `python3 -I -c`, this change | working directory | 0 | `updatedInput` without `model` | not loaded |
| `python3 -I -c`, this change | `PYTHONPATH` | 0 | `updatedInput` without `model` | not loaded |

Before the change the planted code ran with the user's permissions. Exit 7
is "any other code", for which "the action goes ahead" [Hooks exit codes], so
in a session the dispatch would have gone through unpinned; that part was not
run in a session. A planted module written to stay hidden would import the
real `json` instead of exiting, and would own the hook's stdout.

`hook-test.sh` repeats the two `-I` rows and fails on the two `-c` rows: with
the hook reverted to `main`, it stops at `cwd: hook imported a planted
json.py`. With `-I` but without the exit-2 remap, it stops at its case for an
interpreter that exits 2: `expected '1', got '2'`.

[Hooks exit codes]: https://code.claude.com/docs/en/hooks#exit-code-output
