# agentic-dev-toolkit

Instructions for all AI coding agents (Claude Code, Codex, OpenCode) working in
this repository.

## Project Overview

Portable assets for setting up an agentic development environment: a
Debian/Ubuntu workstation installer, a shared `AGENTS.md` instruction pattern
with per-harness adapters, and a model-routing bundle for OpenCode.

It is **not** an application, and **not** a workflow or specification product. It
installs and configures tools; it does not define how work is planned or
executed.

## Repository Layout

```
environments/linux/install.sh   The workstation installer — the main deliverable
instructions/                   AGENTS.md pattern shipped to other projects
  AGENTS.md                     A TEMPLATE for consumers, not this repo's own
  adapters/{claude-code,codex,opencode}/
models/routing/opencode/        Model-routing config bundle for OpenCode
docs/multi-agent-workspace-guide.md
tests/install.sh                Test suite for the installer
```

**`instructions/AGENTS.md` is a deliverable, not this file.** It is the template
consumers copy into their own projects and it deliberately reads `# Project
Name`. Editing it changes what ships. This file, at the repository root, is the
one that governs work here.

## Build and Test

There is no build step and no package manager.

```bash
bash tests/install.sh          # the full test suite
bash -n environments/linux/install.sh   # syntax check
shellcheck environments/linux/install.sh tests/install.sh
```

`tests/install.sh` sources the installer's functions by stripping its final
`main "$@"` line, so **that line must remain last in the file** — the suite
asserts it and fails loudly if it moves.

Never run the installer itself to test a change; it mutates the machine. Use
`--dry-run`, which prints every action without performing it.

## The installer

Targets Debian/Ubuntu. Ubuntu under WSL2 is the reference and tested platform.

Key flags: `--dry-run`, `--upgrade`, `--verify-only`, `--project PATH`,
`--repair-codex`, and `--skip-*` for each component
(`runtimes`, `opencode`, `claude`, `codex`, `openspec`, `superpowers`,
`karpathy`, `quality-tools`).

Pinned defaults, each overridable by a CLI flag or an `ADT_*` environment
variable of the same name:

| Component | Default |
|---|---|
| Java | `temurin-17` (default), `temurin-21` |
| .NET | `10`, `8` |
| Python | `3.12` |
| Node.js | `24` |
| Bun | `1` |
| Maven | `3.9.16` |
| dotnet-ef (EF Core CLI, `dotnet:` backend) | `latest` |
| uv, shellcheck, gitleaks, PyYAML | `latest` |
| OpenSpec | `1.9.0` |
| Superpowers | `v6.3.0` |
| Karpathy guidelines skill | `multica-ai/andrej-karpathy-skills` at a pinned commit |

`install_karpathy_skill` downloads one `SKILL.md` and verifies it against a
SHA-256 digest before writing. Two destinations cover three harnesses:
`~/.claude/skills/` serves Claude Code *and* OpenCode, `$CODEX_HOME/skills/`
serves Codex. **The missing `~/.config/opencode/skills/` copy is deliberate** —
OpenCode reads the Claude Code directory.

The pin is authoritative: on the default ref the built-in digest always applies
and a contradicting `--karpathy-sha256` is refused; any other `--karpathy-ref`
requires its own `--karpathy-sha256`. **No input installs this file unverified** —
it is standing instruction to every agent on the machine. Bump the ref and the
digest together.

## Conventions

- **Bash only.** `set -Eeuo pipefail` and `IFS=$'\n\t'` at the top of every
  script.
- **Every mutating action goes through `run` or `run_sudo`**, which echo the
  command and skip execution under `--dry-run`. Calling a mutating command
  directly silently breaks dry-run mode.
- **Language runtimes and developer tools come from mise**, not APT. APT is for
  system prerequisites only. Packaged shellcheck and gitleaks trail upstream by
  years, and a linter missing the check you rely on is worse than no linter.
- **Never begin a comment line with the name of a linter followed by a space.**
  `# shellcheck ` at the start of a line is parsed as a directive, fails, and
  silently stops analysis of the enclosing function.
- **`*.sh` is pinned to `eol=lf`** in `.gitattributes`. A CRLF shebang makes bash
  refuse the script outright.
- Shell scripts are tracked executable (`100755`); the tests invoke several
  directly.
- Documentation, comments and commit messages in English. Conventional commits.
- No secrets, tokens or credentials in any committed file.

## Scope

Out of scope: application code, workflow or specification schemas, and anything
that assumes a particular project's structure. Assets here must stay usable by
any project that adopts them.
