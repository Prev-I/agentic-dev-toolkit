# Alignment Check Hook-Run Evidence — 2026-10-10

Recorded with
[The Alignment Check Runs the Hook](../decisions/2026-10-10-alignment-check-runs-the-hook.md).
mise 2026.9.7, Python 3.12.14.

## H3 — an installed hook that cannot pin

A scratch `CLAUDE_CONFIG_DIR` held the bundle as the README installs it:
agents, policy, and the hook copied with `cp -p`, so byte-identical and
executable. Its `settings.json` was the fragment with the hook command
pointing at that directory's hook, so the registration matched. Nothing
under `~/.claude` was used.

For the failing case a stub `mise`, first on `PATH`, printed the path of a
script that writes `broken interpreter` to stderr and exits 1. The hook
accepted that path, as it would a real interpreter's. The earlier check was
the module as it stands at the parent commit, run on the same bundle.

| mise | Check | Output | Exit |
|---|---|---|---|
| real | this change | `STATUS: ALIGNED`, in 85 ms with both runs | 0 |
| stub, broken interpreter | before this change | `STATUS: ALIGNED` | 0 |
| stub, broken interpreter | this change | `DRIFT  hooks/pin-agent-model.sh  run: exit 1: broken interpreter`, `STATUS: DRIFT` | 1 |

In a session that third row's hook would have exited 1 on every dispatch,
each one going ahead unpinned with a hook error notice.

`alignment-test.sh` repeats the failing case with its own stub, and fails
against the earlier check with `expected '1', got '0'`.
