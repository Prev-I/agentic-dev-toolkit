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
environments/windows/           Windows-side WSL2 VM settings; a template, never installed
instructions/                   AGENTS.md pattern shipped to other projects
  AGENTS.md                     A TEMPLATE for consumers, not this repo's own
  adapters/{claude-code,codex,opencode}/
models/routing/opencode/        Model-routing config bundle for OpenCode
repository-policy/              `.repository-policy.yaml` format, schema and validator
wsl-toolchain-doctor/           Linux-first PATH and toolchain auditor for WSL
docs/multi-agent-workspace-guide.md
docs/wsl-toolchain-doctor.md    Operational documentation for the doctor
tests/install.sh                Test suite for the installer
tests/repository-policy.sh      Test suite for the policy validator
tests/wsl-toolchain-doctor.sh   Test suite for the doctor
```

**`instructions/AGENTS.md` is a deliverable, not this file.** It is the template
consumers copy into their own projects and it deliberately reads `# Project
Name`. Editing it changes what ships. This file, at the repository root, is the
one that governs work here.

## Build and Test

There is no build step and no package manager.

```bash
bash tests/install.sh                   # the installer suite
bash tests/repository-policy.sh         # the policy validator suite
bash tests/wsl-toolchain-doctor.sh      # the WSL toolchain doctor suite
bash models/routing/opencode/eval/run-tests.sh   # the routing eval suite
bash -n environments/linux/install.sh   # syntax check
shellcheck environments/linux/install.sh tests/install.sh \
  tests/repository-policy.sh repository-policy/validate.sh \
  wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh
```

All four suites are expected to be run and reported together; the evidence
documents under `models/routing/opencode/docs/` transcribe them that way.

`tests/install.sh` sources the installer's functions by stripping its final
`main "$@"` line, so **that line must remain last in the file** — the suite
asserts it and fails loudly if it moves.

Never run the installer itself to test a change; it mutates the machine. Use
`--dry-run`, which prints every action without performing it.

## The installer

Targets Debian/Ubuntu. Ubuntu under WSL2 is the reference and tested platform.

Key flags: `--dry-run`, `--upgrade`, `--verify-only`, `--project PATH`,
`--repair-codex`, `--gcm-path PATH`, and `--skip-*` for each component
(`runtimes`, `opencode`, `claude`, `codex`, `openspec`, `superpowers`,
`karpathy`, `quality-tools`, `git-credential`).

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

## Repository policy

`repository-policy/` defines `.repository-policy.yaml`, a small versioned format
for declaring how a repository integrates work, plus a JSON Schema, examples and
`validate.sh`. See `repository-policy/README.md`.

It declares intent and enforces nothing; GitHub rulesets and GitLab protected
branches do the enforcing. Keeping it from growing into a second, weaker copy of
branch protection is a stated design constraint — reviewers, CODEOWNERS, signed
commits, merge queues and required checks stay out.

Two rules are load-bearing and easy to erode. **Branch names carry no
integration semantics**: `main` does not imply pull requests and `master` does
not imply direct commits, which is why `examples/trunk-direct-main.yaml` and its
test exist. And **the validator's accepted values are read out of the schema**,
so widening the format means editing the schema, not the code.

The validator needs a YAML parser and so is the one component here that is not
dependency-free. It resolves an interpreter that has PyYAML and exits 2 when
none does; it must never degrade to a skip.

## Git credentials on WSL

`configure_git_credential_helper` generates `~/.local/bin/git-credential-manager-wsl`,
a wrapper around the Windows Git Credential Manager, and adopts
`credential.helper` only when nothing else owns it. It is a no-op off WSL.
See `README.md` for the full rationale.

Three rules are load-bearing.

**Both halves of the boundary crossing are required.** GCM is a Windows process,
so it reads neither this side's git config (it shells out to *Windows* git) nor
this side's environment (WSL passes nothing in unless `WSLENV` names it).
Exporting `GCM_INTERACTIVE` without appending it to `WSLENV` does nothing at all
and looks like it worked. That is why the setting is generated from one place
rather than documented as a manual step.

**The terminal test is `/dev/tty` openability, not `[[ -t ]]`.** Git hands every
credential helper pipes on stdin and stdout by protocol, so a file-descriptor
test reports every interactive run as headless. A human who pipes git's output
still has a controlling terminal and must keep their prompt.

**Adoption is conditional.** An unset helper, or one naming
`git-credential-manager.exe` directly, is claimed; anything else is reported and
left alone. Where a machine's credentials come from is not the installer's
decision to make silently.

Keep the feature harness-agnostic. Per-harness configuration was rejected on
purpose — the OpenCode config is generated and would erase it, and Claude Code's
covers only Claude Code — so do not "simplify" it into either.

Verification runs the wrapper against a stub delegate and asserts the decision,
rather than checking that a file exists: the failure being prevented is a hang,
and a file that is present but deciding wrongly hangs just as badly.

## The WSL toolchain doctor

`wsl-toolchain-doctor/` audits and remediates a Linux-first development boundary
inside WSL. It is diagnostic, not provisioning: the installer builds the machine,
the doctor reports when the machine has drifted.

Its policy is `interop.enabled=true` with `interop.appendWindowsPath=false` in
`/etc/wsl.conf`, so Windows processes stay invocable while the Windows PATH is no
longer appended to the Linux one. Rancher Desktop is the single exception, and
only for Linux container tooling under `resources/resources/linux/bin` or
`resources/resources/linux/docker-cli-plugins` whose final target is ELF or a
Linux script. Managed language runtimes never receive that exception.

Two design rules are load-bearing. **Mount provenance decides what is
Windows-backed**, read from `/proc/self/mounts`, because the automount root is
configurable and `/mnt/c` must not be hard-coded. And **profile files are parsed
as text, never sourced or evaluated** - `fix --path` rewrites only a small,
explicitly safe grammar of `PATH=` assignments and refuses dynamic ones rather
than guessing.

One consequence of the exit-code protocol is worth knowing before editing:
several internal functions return non-zero deliberately, to carry `10` (restart
WSL) and `11` (new shell) outward. Their call sites wrap the call in an `if`,
which keeps `errexit` suspended. A bare call followed by `$?` would abort the
script under `set -e` instead of capturing the status.

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
  directly. Suite entry points under `tests/` are the exception at `100644`,
  because they are always run as `bash tests/<name>.sh`.
- Documentation, comments and commit messages in English. Conventional commits.
- No secrets, tokens or credentials in any committed file.

## Scope

Out of scope: application code, workflow or specification schemas, and anything
that assumes a particular project's structure. Assets here must stay usable by
any project that adopts them.

"Workflow schema" there means a schema for how work is planned and executed —
proposals, specifications, tasks, review gates. That remains out of scope and
belongs to SpecRivet. It does not cover `repository-policy/`, which declares how
a repository integrates commits: a property of the repository itself, portable
across projects and hosting vendors, and prescribing no development process. The
distinction is narrow enough to be worth stating, because the two readings of
the word land on opposite sides of this boundary.
