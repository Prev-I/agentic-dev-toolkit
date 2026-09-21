# OpenCode direnv launcher implementation plan

**Goal:** Load allowlisted MCP environment variables from immediate workspace
children before executing the persistent OpenCode server.

**Approved design:** Configurable scan root (default `$HOME/code`), no recursive
checkout discovery, real direnv authorization, isolated workspace evaluations,
identical duplicate values accepted and conflicting values rejected without
printing values. Existing MCP definitions remain workspace-local. OAuth stores
remain independent. Reload requires a backend restart.

**Architecture:** A Bash launcher accepts the original server command as argv.
An environment file supplies a root and whitespace-separated allowlist. Each
workspace is evaluated in a subprocess with the allowlisted names removed from
its baseline. Only those names return over a private stdout descriptor; values
are encoded for Bash capture and remain in memory. Merge only after successful
evaluation, then `exec` the unchanged server command. PATH stays systemd-owned.

**Files:**
- `opencode-service/opencode-direnv-exec.sh`: standalone launcher, version 0.1.0.
- `tests/opencode-direnv.sh`: real direnv fixtures and a harmless child process.
- `tests/opencode-service.sh`: include the new component test.
- `docs/opencode-service.md`: installation, configuration, lifecycle, rollback.
- Host-only: installed launcher, non-secret environment file, ExecStart drop-in.

## Steps

- [x] Add real-direnv tests for automatic discovery, depth one, spaces, exact
  values, equal/conflicting duplicates, blocked/erroring `.envrc`, reserved
  variables, missing root, empty allowlist, preserved PATH and command argv.
- [x] Run the tests against the missing launcher and observe failure.
- [x] Implement parsing, in-memory extraction/merge and final exec. Never log
  values, source `.envrc` directly or run `direnv allow` outside test fixtures.
- [x] Run the new test, all seven repository suites, ShellCheck and diff checks.
- [x] Document the generic launcher and additive service drop-in.
- [x] Install the launcher and non-secret host configuration. Preflight with the
  real service environment and a verifier that prints only variable presence.
- [x] Validate the effective unit. Arrange restart from an independent process
  so killing the backend does not kill verification. Confirm health, expected
  variable presence, unchanged PATH/other environment and restart count.

Implemented on `feat/opencode-attach-shortcut`. Commit, push and a GitHub pull
request were subsequently requested after host verification.

## Host verification

After restarting the service, all four selected variables were present. The
mise PATH, base unit and `.bashrc` were unchanged; only systemd invocation
metadata changed among existing environment variables. OpenCode reported
healthy (1.18.31), active/running, zero automatic restarts. GitHub, Azure DevOps,
New Relic, Azure and Kubernetes reported connected. Both PostgreSQL MCPs still
reported failed despite their URL variables being present; connection diagnosis
is a separate follow-up. No credential values were included in the report.
