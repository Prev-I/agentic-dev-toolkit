# Agentic Dev Toolkit

<p align="center">
  <img
    src="docs/images/social-preview.png"
    alt="Agentic Dev Toolkit — Linux, Multi-Harness and Model Routing"
    width="100%"
  />
</p>

Portable workstation setup, shared agent instructions, harness adapters, and model-routing
configurations for AI-assisted software development.

## What this is

A collection of reusable components for teams using AI coding agents:

- **Linux workstation installer** — a single script that provisions a Debian/Ubuntu machine
  with mise-managed language runtimes, three agent CLIs (OpenCode, Claude Code, Codex), OpenSpec,
  Superpowers, and the quality tools (shellcheck, gitleaks, PyYAML) whose absence otherwise fails
  silently. Ubuntu under WSL2 is the reference and tested environment.
- **Shared `AGENTS.md` pattern** — a template and adapter set that lets one canonical instructions
  file serve Claude Code, Codex, and OpenCode simultaneously.
- **OpenCode model-routing bundle** — a starter configuration that assigns models to OpenCode's
  built-in agents and adds two custom subagents (`reviewer` and `expert`) for independent review
  and scarce-model escalation.

## What this is NOT

- Not a workflow engine or framework — it does not prescribe how you run your development process.
- Not company-specific — there are no proprietary references, org names, or internal tooling.
- Not an OpenSpec or SpecRivet distribution — it can install OpenSpec as a tool, but does not ship
  a workflow schema.

## Supported environments

The Linux installer supports **Debian/Ubuntu family** distributions; **Ubuntu under WSL2** is the
reference and tested environment. It uses `apt` for system packages. The `--skip-platform-check`
flag allows running on non-Debian distributions but these are untested.

## Repository structure

```
agentic-dev-toolkit/
  LICENSE                                          # MIT
  README.md                                        # This file
  environments/
    linux/
      install.sh                                   # Debian/Ubuntu workstation provisioner
  instructions/
    AGENTS.md                                      # Template: canonical agent instructions
    adapters/
      claude-code/
        CLAUDE.md                                  # Template: one-line @AGENTS.md redirect
        README.md                                  # Claude Code adapter documentation
      codex/
        README.md                                  # Codex adapter documentation
      opencode/
        README.md                                  # OpenCode adapter documentation
  models/
    routing/
      opencode/
        README.md                                  # Model-routing documentation
        opencode.jsonc                             # Config fragment: model/variant map
        .opencode/
          model-routing.md                         # Semantic routing policy
          agents/
            reviewer.md                            # Independent review subagent
            expert.md                              # Escalation-only expert subagent
  docs/
    multi-agent-workspace-guide.md                 # Full guide: AGENTS.md pattern + MCP parity
```

## Workstation bootstrap

```bash
# Preview what will be installed
./environments/linux/install.sh --dry-run

# Run the full installation
./environments/linux/install.sh

# Reload shell to pick up PATH changes
exec bash -l
```

Key flags:

| Flag | Purpose |
|---|---|
| `--dry-run` | Print planned actions without changing the system |
| `--upgrade` | Upgrade mutable components and runtime patches |
| `--verify-only` | Verify an existing installation without installing |
| `--project PATH` | Initialize or refresh OpenSpec in a Git repository |
| `--skip-runtimes` | Skip mise and language runtime installation |
| `--skip-opencode` | Skip OpenCode installation |
| `--skip-claude` | Skip Claude Code installation |
| `--skip-codex` | Skip Codex CLI installation |
| `--skip-openspec` | Skip OpenSpec installation |
| `--skip-superpowers` | Skip Superpowers configuration |
| `--skip-quality-tools` | Skip shellcheck, gitleaks, and PyYAML |
| `--repair-codex` | Remove conflicting Codex installs and reinstall standalone |

Version overrides are available via `--node-version`, `--python-version`, etc., or through
`ADT_NODE_VERSION`, `ADT_PYTHON_VERSION`, and similar environment variables. See
`./environments/linux/install.sh --help` for the full list.

### Quality tools

Three things ship alongside the runtimes because their absence is silent rather
than loud:

| Tool | Installed via | Why it is here |
|---|---|---|
| `shellcheck` | mise | The Debian/Ubuntu package trails upstream by years. A linter that quietly lacks the check you are relying on is worse than no linter |
| `gitleaks` | mise | Same reason, higher stakes: a secret scanner that predates a rule reports clean |
| PyYAML | `pip` into the mise Python | Test suites commonly skip their schema or config checks when `import yaml` fails. The suite then exits 0 with its strongest check never evaluated |

The PyYAML case is the one worth stating plainly: a runner that degrades to a
skip does not report a problem, it reports success. That cannot be fixed from
inside the repository that suffers from it, because the missing piece is on the
workstation.

Both mise tools default to `latest` and are pinnable with `--shellcheck-version`,
`--gitleaks-version`, and `--pyyaml-version` (or `ADT_SHELLCHECK_VERSION`,
`ADT_GITLEAKS_VERSION`, `ADT_PYYAML_VERSION`). `--skip-runtimes` implies
`--skip-quality-tools`, since mise and the managed interpreter are what install
them. A PyYAML failure warns rather than aborting the run.

## Shared `AGENTS.md` pattern

The core idea: write workspace guidance once in `AGENTS.md`, then give each agent harness access
through its native mechanism.

- **Codex** and **OpenCode** load `AGENTS.md` directly.
- **Claude Code** loads `CLAUDE.md`, which contains a single `@AGENTS.md` import directive.

See [`instructions/AGENTS.md`](instructions/AGENTS.md) for the template and the adapter READMEs
for harness-specific setup:

- [Claude Code adapter](instructions/adapters/claude-code/README.md)
- [Codex adapter](instructions/adapters/codex/README.md)
- [OpenCode adapter](instructions/adapters/opencode/README.md)

The full guide — including MCP server parity across all three harnesses, verification scripts,
and nested-repository patterns — is at
[`docs/multi-agent-workspace-guide.md`](docs/multi-agent-workspace-guide.md).

## OpenCode model-routing

A starter configuration that maps OpenCode's built-in agents to specific models and variants,
adds a read-only `reviewer` on a different model family for adversarial diversity, and gates a
scarce high-end model behind a hidden `expert` agent.

See [`models/routing/opencode/README.md`](models/routing/opencode/README.md) for the model map,
installation instructions, and smoke tests.

## Security

- No secrets, tokens, API keys, or connection strings in any committed file.
- MCP server authentication uses ambient credentials (Azure CLI, environment variables, device
  login flows).
- Audit config files before committing — search for `Bearer`, `password`, `connectionString`,
  `-----BEGIN`, `sk-`, `pat:`.

## License

[MIT](LICENSE)
