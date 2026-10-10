# Hook Interpreter Evidence — 2026-10-10

Recorded with
[The Hook Resolves Python Through mise](../decisions/2026-10-10-hook-resolves-python-through-mise.md).
mise 2026.9.7, global Python 3.12.14 from mise, Ubuntu on WSL2. No Claude
Code session was involved: the hook was run directly with a PreToolUse event
on stdin, a `scout` dispatch carrying `model: "sonnet"`, which it must
rewrite.

## H2 — the session's directory against the hook's interpreter

Three scratch directories, each opened as the working directory:

| Directory | Content | `mise trust --show` |
|---|---|---|
| neutral | nothing | — |
| version not installed | `mise.toml`: `[tools] python = "3.9.99"` | `untrusted` |
| `path:` version | `mise.toml`: `[tools] python = "path:./fakepy"`; `fakepy/bin/python3` is a shell script that writes a marker file and exits 0 | `untrusted` |

"Remote Control `PATH`" is the unit's
`~/.local/bin:~/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin`, run
with `env -i HOME=… PATH=…`, so `python3` is mise's shim. "Shell `PATH`" is
the `PATH` of the shell these runs were made from, built by `mise activate`
for another directory, where `python3` is
`~/.local/share/mise/installs/python/3.12/bin/python3`; changing directory
did not rebuild it. "Activated in the repository" is the `PATH` that
`mise env -s bash` printed inside the `path:` directory, the one an
interactive shell would have there: `~/.local/bin`, then `fakepy/bin`, then
the rest, `/usr/bin` included.

| Hook | `PATH` | Directory | Exit | Output | Effect |
|---|---|---|---|---|---|
| as on `main` | Remote Control | neutral | 0 | `updatedInput` | — |
| as on `main` | Remote Control | version not installed | 1 | none | python-build ran for 3.9.99 and failed; call unpinned |
| as on `main` | Remote Control | `path:` version | 0 | none | **the repository's `fakepy/bin/python3` ran**; call unpinned, no error |
| this change | Remote Control | each of the three | 0 | `updatedInput` | no install attempt, marker not written |
| this change | shell | each of the three | 0 | `updatedInput` | marker not written |
| as on `main` | activated in the repository | `path:` version | 0 | none | **the repository's `fakepy/bin/python3` ran** |
| this change | activated in the repository | `path:` version | 0 | `updatedInput` | marker not written |
| this change, with a `bash` added to `fakepy/bin` | activated in the repository | `path:` version | 0 | `updatedInput` | **the repository's `bash` ran**, through `#!/usr/bin/env bash` |
| this change | `/usr/bin:/bin`, no mise | `path:` version | 0 | `updatedInput` | — |
| this change | `/usr/bin:/bin`, no `HOME` | `path:` version | 0 | `updatedInput` | — |

The failed 3.9.99 installs left an empty `~/.cache/mise/python/3.9.99`, which
was removed after each run, and the `bash` added to `fakepy/bin` was
removed after its run. The new hook took 26 ms for one call with the shell
`PATH`.

## Supporting observations

- `mise -C "$HOME" which python3`, run from the version-not-installed and the
  `path:` directories under the Remote Control `PATH`: printed
  `~/.local/share/mise/installs/python/3.12/bin/python3`, exit 0, in 10 to
  30 ms; no marker, nothing new in mise's cache. Without `-C` from the
  version-not-installed directory: exit 1.
- The shim's own exit in the version-not-installed directory was 1, so before
  this change the hook's exit-2 remap was not what kept delegation open there.
  With `MISE_AUTO_INSTALL=false` the same shim did not try to install and ran
  `/usr/bin/python3` instead. The shims page: "Otherwise it runs the next
  executable with the same name on `PATH`. … for a command the OS also ships,
  such as `python3` on Debian or Ubuntu, the shim can silently run an
  unrelated system binary."
  ([Shims](https://mise.jdx.dev/dev-tools/shims.html#mise-activate-shims))
- With a global config naming Python `3.11.99`, which is not installed,
  `mise which` exited 1 with installs off, online and with `MISE_OFFLINE=1`; no
  install was attempted. Naming `latest`, it printed the installed
  `installs/python/latest/bin/python3`.
- `mise env` in the `path:` directory put `fakepy/bin` on `PATH`, after
  `~/.local/bin` and before `/usr/bin`. Under `mise activate`, every command
  typed in that directory would see it.
- `mise settings get` on this workstation: `auto_install = true`,
  `not_found_auto_install = true`, `exec_auto_install = true`,
  `offline = false`, `not_found_system_fallback = true`.
- `~/.local/bin/python3` does not exist, so nothing ahead of the shims on the
  Remote Control `PATH` shadows them.

Not covered: the runs used `env -i`, not `direnv exec <project>` as the unit
does, so variables an `.envrc` adds were absent. Those come from a file the
user has allowed.
