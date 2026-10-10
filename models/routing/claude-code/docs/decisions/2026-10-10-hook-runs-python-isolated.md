# The Hook Runs Python Isolated

## Decision

`hooks/pin-agent-model.sh` runs its embedded Python as `python3 -I -c`
instead of `python3 -c`, and reports an interpreter's own exit 2 as 1. What
the hook strips, and for which roles, is unchanged.

## Rationale

- **The hook runs inside whatever directory the session is in.** "Handlers
  run in the current directory with Claude Code's environment." [Hooks] For a
  Build session that is the repository being worked on, and the environment is
  whatever that shell exported, direnv included.
- **`python3 -c` imports from that directory.** With `-c`, "the current
  directory will be added to the start of `sys.path` (allowing modules in that
  directory to be imported as top level modules)." [Python -c] Each hook call
  is a new process whose first statement is `import json`, before any role
  check, so a `json.py` in the session's directory runs on every Agent call,
  `general-purpose` included. `PYTHONPATH` set by the session's environment
  does the same.
- **It runs as the user.** "Command hooks execute shell commands with your
  full user permissions." [Hooks security] A routing hook installed for every
  project would turn any cloned repository into code that runs on the next
  subagent dispatch, without any prompt of its own. Such code also owns the
  hook's stdout, so it could rewrite the dispatch it was meant to pin.
- **Observed.** Evidence H1: with the earlier hook, a planted `json.py` ran
  from the working directory and from `PYTHONPATH`; with `-I`, neither loaded
  and the hook returned its normal output.
- **`-I` closes both paths and nothing the hook needs.** "Run Python in
  isolated mode. This also implies `-E`, `-P` and `-s` options. In isolated
  mode `sys.path` contains neither the script's directory nor the user's
  site-packages directory. All `PYTHON*` environment variables are ignored,
  too." It was "Added in version 3.4". [Python -I] The hook imports only
  `json` and `sys` from the standard library. `-P` alone was not chosen: it
  exists only from Python 3.11 [Python -P], and it leaves `PYTHONPATH` alone,
  which `-E` covers: "Ignore all `PYTHON*` environment variables, e.g.
  `PYTHONPATH` and `PYTHONHOME`, that might be set." [Python -E] `-I` implies
  both.
- **Exit 2 stays impossible.** When a hook exits 2, "on events that can
  block, Claude Code stops the action"; when it exits "with any other code",
  "the action goes ahead". [Hooks exit codes] A
  `python3` that rejects `-I`, which a Python before 3.4 would, exits 2 on its
  own. The hook therefore no longer `exec`s Python: it reports an exit 2 as 1,
  so the fail-open guarantee does not depend on the interpreter.

## Consequences

- An installed profile needs the hook re-copied; until then the alignment
  check reports its content as `DRIFT`.
- `hook-test.sh` plants a `json.py` in the working directory and on
  `PYTHONPATH` and fails if either is imported, and runs the hook against a
  `python3` that exits 2.
- Not changed here: the hook still resolves `python3` from `PATH`, and the
  alignment check still compares the installed hook's bytes rather than
  running it. Both were raised in the same review and are separate decisions.
  The first is wider than a repository `bin/` on `PATH`: version-manager
  shims, mise's on this workstation, pick the interpreter from files in the
  current directory such as `.tool-versions` or `.python-version`.

## Evidence boundary

Evidence H1 in
[`../evidence/2026-10-10-hook-python-isolation.md`](../evidence/2026-10-10-hook-python-isolation.md),
on Python 3.12.14. The issue was found by an `expert` consultation during the
2026-10-10 smoke tests. Documentation as read on 2026-10-10:

- [Hooks]
- [Hooks exit codes]
- [Hooks security]
- [Python -c]
- [Python -E]
- [Python -I]
- [Python -P]

[Hooks]: https://code.claude.com/docs/en/hooks#hook-handler-fields
[Hooks exit codes]: https://code.claude.com/docs/en/hooks#exit-code-output
[Hooks security]: https://code.claude.com/docs/en/hooks#security-considerations
[Python -c]: https://docs.python.org/3/using/cmdline.html#cmdoption-c
[Python -E]: https://docs.python.org/3/using/cmdline.html#cmdoption-E
[Python -I]: https://docs.python.org/3/using/cmdline.html#cmdoption-I
[Python -P]: https://docs.python.org/3/using/cmdline.html#cmdoption-P

Later corrections are appended as dated addenda, never edited in place.
