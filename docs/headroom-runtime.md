# Headroom Runtime Runbook

## Policy

Headroom `0.37.0` is an opt-in standalone runtime at status `TRIAL`. The
runtime listens only on `127.0.0.1:8787`. It is not installed by the workstation
installer and does not optimize OpenCode traffic. The native OpenCode plugin is
`HOLD`; MCP and explicit API integration are `NOT_EVALUATED`.

## Architecture

The component installs `headroom-ai[proxy]==0.37.0` in a uv tool environment
using Python `3.13`, then delegates persistent-service generation to Headroom.
It uses profile `default`, port `8787`, provider scope, and manual providers.
No target is selected. Headroom and OpenCode have separate user-service
lifecycle and configuration ownership.

## Prerequisites

The standalone CLI checks Bash, Linux, uv, jq, curl, `systemctl --user`, `ss`,
and the Headroom executable when the requested operation requires it. A usable
user systemd manager is required for installation. The top-level pin is exact,
but uv resolves its transitive dependency closure from its configured package
index at installation time; this is pinned but not locked or hash-verified.

## Install

```bash
./headroom-runtime/headroom-runtime.sh install --dry-run
./headroom-runtime/headroom-runtime.sh install
```

The delegated commands are exactly:

```bash
uv tool install --python 3.13 'headroom-ai[proxy]==0.37.0'
headroom install apply --preset persistent-service --runtime python \
  --scope provider --providers manual --profile default --port 8787 \
  --mode cache --no-telemetry --env HEADROOM_BEACON=off \
  --env HEADROOM_UPDATE_CHECK=off
```

There is intentionally no `--target`. Provider/manual scope with no targets is
the validated service-only path and prevents shell or provider configuration
mutations.

## Generated Artifacts

Headroom generates and owns the user unit and deployment profile beneath the
user configuration and Headroom deployment directories. These artifacts are not
toolkit source and must not be committed or manually edited. The CLI inspects
them only to enforce ownership, profile, no-target, telemetry, and isolation
invariants.

## Audit And Findings

```bash
./headroom-runtime/headroom-runtime.sh audit
./headroom-runtime/headroom-runtime.sh audit --json
```

`PASS` and `WARN` exit 0, `FAIL` exits 1, and `ERROR` exits 2. The JSON output
has a stable `schemaVersion`, component version, action, status, and findings
array. Key finding codes include `HEADROOM_NOT_READY`,
`HEADROOM_MANIFEST_INVALID`, and `HEADROOM_LISTENER_OWNER_AMBIGUOUS`; OpenCode
coupling findings use the `HEADROOM_OPENCODE_*` prefix. Non-blocking findings
are `HEADROOM_KOMPRESS_OPTIONAL_DEGRADED`, `HEADROOM_LIFECYCLE_EXIT_241`, and
`HEADROOM_PERMISSIONS_BROAD`.

Audit is non-destructive. It does not query Telegram, edit OpenCode, or dump
process environment values.

## WSL Shutdown/Start Validation

```powershell
wsl.exe --shutdown
```

After the distribution starts again, user systemd with linger enabled recovers
the Headroom service and its loopback readiness endpoint. OpenCode independently
recovers its own service and remains independent of Headroom. A WSL shutdown
necessarily stops Linux processes; the accepted property is automatic recovery
after the distribution starts, not availability during shutdown.

## Known Findings

Optional Kompress can be degraded while required Headroom readiness succeeds.
The component does not add the optional ML dependency set without a separate
benefit and risk evaluation. Upstream may record lifecycle exit `241` during
explicit stop/restart despite successful recovery. Generated operational files
may have broader permissions than the owner-only manifest boundary. These are
warnings, not a basis for changing generated artifacts.

Telegram duplicate polling is independently classified as
`KNOWN_PREEXISTING_GATEWAY_FAILURE`. It persisted while Headroom was stopped and
the Headroom port was absent: `Headroom causal involvement: NONE`.

## Troubleshooting

Use `audit --json` to identify stable finding codes. A stopped or disabled
recognized service is an operator action, not an implicit-install repair. An
unknown listener owner, unreadable input, or malformed manifest is `ERROR` and
must be investigated before automated mutation. Detected OpenCode integration is
a warning during removal only; removal never repairs OpenCode configuration.

## Rollback

```bash
./headroom-runtime/headroom-runtime.sh remove
./headroom-runtime/headroom-runtime.sh remove --uninstall-tool
```

For a corrupt or unreadable manifest, automated profile removal exits 2. Do not
use a force mode. Preserve evidence by archiving the generated profile directory
and generated user unit, inspect ownership, then use upstream and systemd
commands deliberately. Review OpenCode integration separately: this component
does not remove or repair it.

## Upgrade Procedure

1. Inspect the candidate Headroom release.
2. Review OpenCode integration changes while the plugin remains disabled.
3. Review persistent-service installation and generated-unit changes.
4. Review security, telemetry, and update-check behavior.
5. Update the standalone version and package pin together.
6. Explicitly upgrade or reinstall the isolated uv tool.
7. Reapply the persistent deployment only if upstream requires it.
8. Run the component audit and fixture suite.
9. Repeat live runtime validation.
10. Repeat WSL lifecycle validation when service behavior changes.

Plugin qualification remains a separate gate. Any behavior or output change to
the component script bumps its semantic version in the same commit: patch for a
fix, minor for an additive interface, and major for a breaking change.

## Design Constraints

Do not add `headroom-opencode`, `HEADROOM_PROXY_URL`, provider routing, shell
changes, generated artifact templates, targets, automatic providers, or the
optional ML dependency set. Do not use `headroom deploy` or `headroom wrap`.
Every mutation is routed through the CLI's dry-run-aware command wrapper.

## References

- [Component README](../headroom-runtime/README.md)
- [Runtime trial evidence](../headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md)
- [OpenCode plugin hold decision](../headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md)
