# Headroom Runtime

Version `0.1.0` installs, audits, and removes the opt-in Headroom `0.37.0`
runtime. It runs Headroom as an independent loopback-only user service; it does
not optimize any OpenCode traffic.

## Files

| Path | Purpose |
|---|---|
| `headroom-runtime.sh` | Strict-mode install, audit, and removal CLI |
| `../tests/headroom-runtime.sh` | Isolated fixture suite |
| `../docs/headroom-runtime.md` | Operational runbook |
| `docs/evidence/2026-09-12-runtime-trial.md` | Trial status evidence |
| `docs/decisions/2026-09-12-opencode-plugin-hold.md` | OpenCode plugin decision |

## Quick Start

```bash
./headroom-runtime/headroom-runtime.sh install --dry-run
./headroom-runtime/headroom-runtime.sh install
./headroom-runtime/headroom-runtime.sh audit
./headroom-runtime/headroom-runtime.sh audit --json
./headroom-runtime/headroom-runtime.sh remove
./headroom-runtime/headroom-runtime.sh remove --uninstall-tool
```

The installer uses `--scope provider --providers manual` without `--target`.
That deliberate no-target route creates only the standalone service: it avoids
shell-startup and provider configuration changes.

| Status | Exit | Meaning |
|---|---:|---|
| `PASS` | 0 | Required runtime and isolation checks passed. |
| `WARN` | 0 | Required checks passed with non-blocking findings. |
| `FAIL` | 1 | A recognized runtime or policy violation exists. |
| `ERROR` | 2 | State could not be determined reliably. |

Headroom owns generated runtime artifacts, including the user unit and the
deployment profile. Do not commit, hand-edit, or treat those generated files as
toolkit source. See the [runbook](../docs/headroom-runtime.md) for recovery,
rollback, and pinned upgrades.
