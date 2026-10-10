# The Hook Resolves Python Through mise

## Decision

`hooks/pin-agent-model.sh` no longer runs whatever `python3` the session's
directory and `PATH` resolve to. Each call now:

1. leaves the session's directory for `$HOME`, or for `/` when `HOME` is unset,
   relative or not a directory;
2. when `HOME` is usable and `mise` is on `PATH`, asks
   `mise -C "$HOME" which python3`, with automatic installs off, nothing on its
   stdin and, where `timeout` exists, a five-second limit, with a kill one
   second later if mise ignores the termination signal;
3. uses that path only if it is a single absolute path to an executable file,
   and otherwise falls back to `python3` on `PATH`, now resolved from `$HOME`;
4. runs the interpreter as `-I -S -c`, again with automatic installs off.

The script, the pinned roles, the never-`permissionDecision` rule and the
remap of exit 2 to 1 are unchanged. The body now runs as a function in an `||`
list, so no step before Python can exit with a status the remap does not see.

mise stays the base for the managed runtime, as the human required: the
interpreter is the one the user's own mise configuration names for `$HOME`.

## Rationale

- **A shim follows the directory it runs in.** "Each time it runs, it reads
  the config for the current directory, picks the version, sets that project's
  `[env]` variables, and runs the real executable. When a shim cannot find the
  configured version, it installs it, as long as `not_found_auto_install` is
  on." [Shims] Hooks run "in the current directory with Claude Code's
  environment" [Hooks], and the Remote Control unit puts mise's shims on
  `PATH`.
- **Tool versions need no trust.** "A file with no template syntax that
  contains only `min_version`, `[tools]` entries with plain version strings (or
  arrays of them), and `[tasks]` in which no task lists `secrets` does not need
  trust unless paranoid mode is on." [Trust] A cloned repository can therefore
  choose the hook's interpreter without anyone approving it.
- **Observed.** Evidence H2, under the Remote Control unit's `PATH`: in a
  directory whose untrusted `mise.toml` pins a Python that is not installed,
  the hook attempted to install it on the call and exited 1, unpinned. In a
  directory whose untrusted `mise.toml` sets `python = "path:./fakepy"`, the
  hook ran the repository's own `fakepy/bin/python3`, which exited 0 with no
  output, so the call went through unpinned and without any error. With this
  change neither directory had any effect under the Remote Control `PATH`,
  under this workstation's shell `PATH`, or under the `PATH` that
  `mise activate` builds inside the `path:` directory, as long as the global
  config names an installed Python and mise's own directory comes before the
  tool's on that `PATH`, as it did here.
- **`-C` resolves as if from `$HOME`.** "`-C --cd <DIR>` — Run as if mise were
  started in DIR" [CLI], and `mise which` "Prints the real path of the
  executable mise would run for BIN_NAME in the current directory, bypassing
  shims." [Which] Calling the real binary also keeps the global config's
  `[env]` out of the hook's process.
- **Installs stay off.** "When `false`, mise never installs automatically:
  this also turns off `exec_auto_install`, `not_found_auto_install` and
  `task.run_auto_install`." [Settings] `MISE_NOT_FOUND_AUTO_INSTALL=false`,
  which the settings page lists as that setting's own variable, is set beside
  it as well. Both apply to the hook's own commands only and are never
  exported. A "read-only" label does not settle it alone: "Effect labels
  describe the command's intended operation; configuration evaluation, caches,
  and required tool installation can still have side effects. They are not
  sandbox guarantees." [CLI]
- **`-S`.** "Disable the import of the module `site` and the site-dependent
  manipulations of `sys.path` that it entails." [Python -S] The script needs
  only `json` and `sys`.
- **Advised by `expert`** (Fable 5.1), escalated under condition 2, which
  ranked this option first and supplied the fallback chain and the `set -e`
  correction it relies on.

## Options not taken

- **`/usr/bin/python3` first.** Excluded by the human: mise is the base for
  every managed runtime.
- **Only `cd "$HOME"` before `python3`.** Portable and without a mise call,
  and enough for a shim-only `PATH`. Under a `PATH` that `mise activate` built
  inside the repository it still runs that repository's `python3` (evidence
  H2), where asking mise from `$HOME` does not, and it can give interactive and
  Remote Control sessions different interpreters.
- **`mise -C "$HOME" exec`.** Same resolution with more overhead. "Commands
  that run project code (`mise run`, … `mise install`, `mise exec`, …) trust
  their active config automatically" [Trust], and "Missing tools are installed
  first unless the `exec_auto_install` or `auto_install` setting is off."
  [Exec]
- **An absolute path baked in at install time.** Breaks when mise prunes or
  upgrades the interpreter, and needs install-time logic and its own check.

## Consequences

- An installed profile needs the hook re-copied; until then the alignment
  check reports its content as `DRIFT`.
- A dispatch costs one `mise which` more, about 10 to 30 ms on this
  workstation. That query is cut off after five seconds where `timeout`
  exists, and killed a second later if it ignores the signal; a fallback
  `python3` that is itself a shim is not bounded, and relies on Claude Code's
  own hook timeout.
- Without a global mise Python, or without mise, the hook runs `python3` from
  `PATH` as resolved from `$HOME`. It still pins, but no longer through mise.
- `hook-test.sh` runs every case against a stub `mise` and stub interpreters,
  and covers: mise's interpreter used and `PATH`'s ignored, the exact `-C`
  arguments, installs off for mise and for the interpreter, empty stdin, the
  interpreter's working directory and `-I -S -c`, eight kinds of unusable mise
  answer, mise absent, an unset, relative or non-directory `HOME` and one with
  spaces, a hanging mise, a planted `json.py` in `$HOME`, and exit 2 from
  either interpreter.
- This replaces the "the hook still resolves `python3` from `PATH`" item that
  [The Hook Runs Python Isolated](2026-10-10-hook-runs-python-isolated.md)
  left open.

## What stays out of scope

- **Environment-level influence.** `PATH` and `MISE_*` variables come from the
  launching shell, an allowed `.envrc` or a settings `env` block. Each of those
  is a trust act by the user, and a trusted project can already run code
  through its own hooks.
- **A `PATH` activated inside an untrusted repository.** Evidence H2 shows
  `mise activate` putting the `path:` tool's `fakepy/bin` on `PATH` in that
  directory, ahead of `/usr/bin`. A Claude Code session started from that
  shell inherits it, and so does every command its Bash tool runs. The hook,
  like those commands, still runs whatever `PATH` names for `bash` (through
  `#!/usr/bin/env bash`) and `timeout`, and for `mise` if the tool directory
  comes before mise's own: a `bash` placed in `fakepy/bin` ran (H2). Only the
  interpreter choice is taken out of the repository's hands; the hook cannot
  be safer than the shell that launched the session.

## Evidence boundary

Evidence H2 in
[`../evidence/2026-10-10-hook-interpreter.md`](../evidence/2026-10-10-hook-interpreter.md),
on mise 2026.9.7 and Python 3.12.14. Documentation as read on 2026-10-10:

- [CLI]
- [Exec]
- [Hooks]
- [Python -S]
- [Settings]
- [Shims]
- [Trust]
- [Which]

[CLI]: https://mise.jdx.dev/cli/#global-flags
[Exec]: https://mise.jdx.dev/cli/exec.html
[Python -S]: https://docs.python.org/3/using/cmdline.html#cmdoption-S
[Hooks]: https://code.claude.com/docs/en/hooks#hook-handler-fields
[Settings]: https://mise.jdx.dev/configuration/settings.html#auto_install
[Shims]: https://mise.jdx.dev/dev-tools/shims.html#mise-activate-shims
[Trust]: https://mise.jdx.dev/cli/trust.html
[Which]: https://mise.jdx.dev/cli/which.html

Later corrections are appended as dated addenda, never edited in place.
