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
catalog/software-catalog.env    The version pins install.sh loads; ships with it as one bundle
instructions/                   AGENTS.md pattern shipped to other projects
  AGENTS.md                     A TEMPLATE for consumers, not this repo's own
  adapters/{claude-code,codex,opencode}/
models/routing/opencode/        Model-routing config bundle for OpenCode
repository-policy/              `.repository-policy.yaml` format, schema and validator
wsl-toolchain-doctor/           Linux-first PATH and toolchain auditor for WSL
opencode-service/               Readiness probes for OpenCode and its Telegram
                                sidecar, plus an optional plugin restart consumer
headroom-runtime/               Opt-in standalone Headroom install, audit, and removal CLI
docs/multi-agent-workspace-guide.md
docs/wsl-toolchain-doctor.md    Operational documentation for the doctor
docs/opencode-service.md        Running OpenCode as a persistent service, and
                                optionally reaching it over HTTPS from the LAN
docs/headroom-runtime.md        Headroom runtime operations, status, and rollback runbook
tests/install.sh                Test suite for the installer
tests/repository-policy.sh      Test suite for the policy validator
tests/wsl-toolchain-doctor.sh   Test suite for the doctor
tests/opencode-service.sh       Test suite for the service scripts
tests/headroom-runtime.sh       Test suite for the Headroom runtime
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
bash tests/opencode-service.sh          # the service scripts suite
bash tests/headroom-runtime.sh          # the Headroom runtime suite
bash models/routing/opencode/eval/run-tests.sh   # the routing eval suite
bash -n environments/linux/install.sh   # syntax check
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
shellcheck environments/linux/install.sh tests/install.sh \
  tests/repository-policy.sh repository-policy/validate.sh \
  wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh \
  opencode-service/opencode-startup-ready.sh \
  opencode-service/opencode-telegram-ready.sh \
  opencode-service/opencode-gateway-restart.sh tests/opencode-service.sh \
  headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
```

All six suites are expected to be run and reported together; the evidence
documents under `models/routing/opencode/docs/` transcribe them that way.

`tests/install.sh` sources the installer's functions by stripping its final
`main "$@"` line, so **that line must remain last in the file** — the suite
asserts it and fails loudly if it moves. Its `load_installer_functions` helper
exports `ADT_CATALOG_FILE`, pointing at this repository's
`catalog/software-catalog.env`, before sourcing the installer body — the
installer's own default resolves relative to the sourced copy's temporary
location and would die on every test otherwise.

Never run the installer itself to test a change; it mutates the machine. Use
`--dry-run`, which prints every action without performing it.

## The installer

Targets Debian/Ubuntu. Ubuntu under WSL2 is the reference and tested platform.

Key flags: `--dry-run`, `--upgrade`, `--verify-only`, `--project PATH`,
`--repair-codex`, `--gcm-path PATH`, and `--skip-*` for each component
(`runtimes`, `opencode`, `claude`, `codex`, `openspec`, `superpowers`,
`karpathy`, `quality-tools`, `git-credential`).

Pinned defaults live in `catalog/software-catalog.env`, not in this file —
read it for the current values. `install.sh` and that catalog ship together as
one bundle; a copy of the script without its catalog does not run.

| Component | Pinned or `latest` |
|---|---|
| Java | pinned, two versions (`java-17` default, `java-21`) |
| .NET | pinned, two versions (`dotnet-10` default, `dotnet-8`) |
| Python | pinned |
| Node.js | pinned |
| Bun | pinned |
| Maven | pinned |
| dotnet-ef (EF Core CLI, `dotnet:` backend) | `latest` |
| uv, shellcheck, gitleaks, PyYAML | `latest` |
| OpenSpec | pinned |
| Superpowers | pinned |
| Karpathy guidelines skill | `multica-ai/andrej-karpathy-skills` at a pinned commit |

Every pin has an `ADT_*` environment variable of the same name. **Not every
pin has a CLI flag** — `maven` and `dotnet-ef` have none. Where a flag exists,
the effective value's precedence is: the CLI flag, then a set-and-non-empty
`ADT_*` variable, then the catalog's value.

Bump a script's `SCRIPT_VERSION` in the same commit that changes its
behaviour: patch for a fix, minor for a new flag or output field, major for a
removal or a breaking output change.

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

The validator needs a YAML parser and so is one of the components here with
explicit host dependencies. It resolves an interpreter that has PyYAML and exits
2 when none does; it must never degrade to a skip. The standalone Headroom
runtime also explicitly checks Bash, uv, jq, curl, `systemctl --user`, `ss`, and
Headroom as required by its selected command.

## The Headroom Runtime

`headroom-runtime/` is opt-in and remains a standalone `TRIAL` capability. Its
install command uses `--scope provider --providers manual` with no `--target`;
the deliberate no-target path creates only the service and avoids shell or
provider configuration mutations. Headroom owns its generated unit and
deployment artifacts, so they are inspected but never committed, templated, or
hand-edited by this repository.

OpenCode checks are guards against Headroom coupling, not ownership claims: the
component does not impose JSON versus JSONC, edit OpenCode, Gateway, or shell
configuration, or configure routing. The native OpenCode plugin is `HOLD`; MCP
and explicit API integration are `NOT_EVALUATED`, and current OpenCode
optimization is `NONE`. Audit uses `PASS`/`WARN`/`FAIL`/`ERROR` with exits
`0`/`0`/`1`/`2`; removal warns about existing OpenCode integration but never
repairs it.

Any behavior or output change to `headroom-runtime.sh` bumps its semantic version
in the same commit: patch for a fix, minor for an additive interface, and major
for a breaking change. The `headroom-ai[proxy]==0.37.0` pin constrains the
top-level package but does not lock or hash-verify transitive dependencies; uv
resolves them from its configured index at installation time.

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
longer appended to the Linux one. The exception is a narrow allowlist of
Windows-backed launcher directories whose contents are Linux ELF or Linux
scripts: Rancher Desktop's container tooling under `resources/resources/linux/bin`
and `resources/resources/linux/docker-cli-plugins`, and VS Code's `bin` for the
`code` launcher. The allowlist governs the PATH *entry* only - tool
classification runs independently, so a PE target still fails, only known
container tooling may resolve from the Rancher directories, and managed language
runtimes never receive any exception. Putting those directories back on `PATH`
is the machine's job, not the doctor's: it reports an entry as allowlisted and
`fix --path` preserves one, but neither creates it. The profile side is one
guarded block per directory, kept *outside* the installer-managed block, because
the installer rewrites its own block wholesale and does not own these paths.

Two design rules are load-bearing. **Mount provenance decides what is
Windows-backed**, read from `/proc/self/mounts`, because the automount root is
configurable and `/mnt/c` must not be hard-coded. And **profile files are parsed
as text, never sourced or evaluated** - `fix --path` rewrites only a small,
explicitly safe grammar of `PATH=` assignments and refuses dynamic ones rather
than guessing.

`CONTAINER_TOOL_UNREACHABLE` is the one check that fires on a tool being
*absent*, and **its evidence gate is load-bearing**. Every other toolchain check
inspects names it finds on PATH, so a CLI missing entirely produces no finding
at all - which is how a machine can have a running daemon, a mounted socket and
a clean audit while `docker` is not a command in any shell. The check reports
that, but only once a socket or `DOCKER_HOST` proves a runtime is actually
reachable. Do not make it unconditional: a machine that runs no containers is
not drifting, and telling it to install a runtime is provisioning, which this
tool does not do. It is a `WARN` for the same reason - a `FAIL` would give a
deliberately container-free machine exit 1.

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
