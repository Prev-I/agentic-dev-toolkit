# Unified Mise Azure Artifacts Authentication

**Date:** 2026-09-12
**Scope:** Host-side Maven and NuGet authentication for Claude Code, Codex,
OpenCode, terminals, and IDE subprocesses in WSL

## Context

Joinon development consumes private Azure Artifacts packages through two tools:

- Maven reads the `Foundation` feed through server ID `Foundation`.
- NuGet reads the `Foundation` and `JoinOn` feeds through package-source names
  `Foundation` and `JoinOn`.

Mise already supplies Java, Maven, .NET 10, and .NET 8 to non-interactive agent
shells. Authentication is fragmented instead:

- `~/.m2/settings.xml` is a world-accessible WSL symlink to a Windows-mounted file
  containing a plaintext PAT.
- `joinon-foundation/env.local` contains a PAT-backed NuGet provider value and has
  mode `0644`.
- three .NET service configs carry the CI placeholder `__NUGET_TOKEN__`.
- Java devcontainers expect `AZDO_MAVEN_PAT`; .NET devcontainers expect
  `AZDO_NUGET_PAT` and modify their checked-out NuGet config.
- Azure Pipelines uses its own `MavenAuthenticate@0`, `NuGetAuthenticate@1`, and
  `System.AccessToken` mechanisms.

The host failure is reproducible: `mise exec -- dotnet` supplies the correct SDK
and starts the Microsoft Azure Artifacts Credential Provider, but non-interactive
harness restores fail with `NU1301` and HTTP 401 when no credential reaches the
process. A prior Claude session worked only after a temporary PAT-backed NuGet
config was created.

## Goals

- Make mise the single host boundary for both runtime selection and Azure Artifacts
  credential injection.
- Store one PAT in one protected file under the WSL user home.
- Preserve ecosystem-native non-secret mappings in `~/.m2/settings.xml` and the
  repositories' NuGet source declarations.
- Make the same commands work in terminals, Claude Code, Codex, and persistent
  OpenCode:

  ```bash
  mise exec -- mvn ...
  mise exec -- dotnet ...
  ```

- Prove the migration with clean Maven and NuGet caches before removing any old
  credential source.
- Remove duplicates in a separate cleanup phase with an explicit rollback point.

## Non-Goals

- Sending a personal PAT into Azure Pipelines. CI keeps service-side authentication.
- Treating Azure CLI Entra access tokens as NuGet Basic passwords. Azure Artifacts
  accepts them as Bearer tokens but rejects them as Basic credentials.
- Removing tracked repository source declarations before dedicated CI and
  devcontainer qualification.
- Deleting package caches as ordinary cleanup. Temporary empty caches provide the
  required proof without destroying useful local state.
- Migrating Windows-native Maven/NuGet consumers in the first host phase.

## Target Architecture

### Single secret

Create:

```text
~/.config/mise/secrets/azure-artifacts.env
```

with directory mode `0700` and file mode `0600`. It contains exactly one secret
input:

```dotenv
AZDO_ARTIFACTS_PAT=<PAT>
```

The single PAT must belong to organization `gewiss-resel`, carry only Packaging
Read permission, and use the shortest practical expiry.

### Global mise loader

Add a user-global fragment:

```text
~/.config/mise/conf.d/azure-artifacts.toml
```

with:

```toml
redactions = [
  "AZDO_ARTIFACTS_PAT",
  "AZDO_MAVEN_PAT",
  "AZDO_NUGET_PAT",
  "NuGetPackageSourceCredentials_*",
]

[env]
_.file = { path = "{{env.HOME}}/.config/mise/secrets/azure-artifacts.env", redact = true }
AZDO_MAVEN_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"
AZDO_NUGET_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"
NuGetPackageSourceCredentials_JoinOn = "Username=gewiss-resel;Password={{env.AZDO_ARTIFACTS_PAT}};ValidAuthenticationTypes=Basic"
NuGetPackageSourceCredentials_Foundation = "Username=gewiss-resel;Password={{env.AZDO_ARTIFACTS_PAT}};ValidAuthenticationTypes=Basic"
```

Mise derives all four consumers from the one loaded PAT. `AZDO_MAVEN_PAT` and
`AZDO_NUGET_PAT` preserve existing consumer contracts while the two source-specific
NuGet variables use NuGet's highest-precedence documented credential mechanism. The
fragment is global, so `mise exec` supplies the variables regardless of current
repository or whether the parent process is an interactive shell. This directly
covers systemd-managed OpenCode without changing its unit.

Redaction protects mise task output but is not encryption. File permissions remain
the security boundary. Commands must not run `mise env`, `env`, or diagnostic dumps
that print secret values.

### Maven mapping

Replace the active user settings with a regular WSL file at:

```text
~/.m2/settings.xml
```

The `Foundation` server contains no PAT:

```xml
<server>
  <id>Foundation</id>
  <username>gewiss-resel</username>
  <password>${env.AZDO_MAVEN_PAT}</password>
</server>
```

The server ID remains exactly `Foundation` because the ten Foundation Java POMs use
that ID for the feed:

```text
https://pkgs.dev.azure.com/gewiss-resel/Foundation/_packaging/Foundation/maven/v1
```

The current symlink to `/mnt/c/Users/previtalicl/.m2/settings.xml` is retained until
the work test passes, then replaced atomically by the WSL-owned non-secret settings
file. The Windows settings file is a separate consumer and is not deleted until a
Windows-native build is tested or declared unsupported.

### NuGet mapping

Keep `~/.nuget/NuGet/NuGet.Config` free of credentials. It may continue declaring
`nuget.org`; repository configs continue declaring their private sources.

NuGet resolves credentials in this order:

1. `NuGetPackageSourceCredentials_<sourceName>` environment variable
2. `packageSourceCredentials` in config files
3. credential provider

The mise-loaded `NuGetPackageSourceCredentials_JoinOn` and
`NuGetPackageSourceCredentials_Foundation` values therefore override the closer
repository placeholders without editing the service repos. Source-name spelling and
case are load-bearing.

The installed Microsoft credential provider remains installed. It is still useful
for other workflows, but host restore no longer depends on an interactive provider
login or provider session-token cache.

### Harness behavior

No harness-specific secret configuration is added:

- Claude Code and Codex invoke absolute mise in non-interactive shells.
- OpenCode's systemd process can invoke the same absolute mise binary; mise reads the
  global user fragment on each command.
- Interactive terminals receive the same variables through mise activation.

Workspace `env.local`, direnv, OpenCode's runtime secret file, and systemd units are
not part of Azure Artifacts authentication after migration.

### CI and devcontainers

CI remains unchanged during host migration:

- Java pipelines retain `MavenAuthenticate@0`.
- .NET pipelines retain `NuGetAuthenticate@1` and existing token substitution until
  a separate pipeline qualification proves one mechanism can be removed.

Devcontainers remain unchanged during host migration because they do not execute
through the host's mise installation:

- Java containers retain settings that reference `${env.AZDO_MAVEN_PAT}`.
- .NET containers retain `AZDO_NUGET_PAT` and their current setup scripts.

No live per-repository `.devcontainer/.env` files were found in the current checkout,
so there is no active duplicate there today. If such files are created later, their
PAT copies are cleanup candidates only after container-level secret forwarding is
designed and tested.

## Migration Phases

### Phase 0: contain exposure

Before creating the replacement:

- change `joinon-foundation/env.local` to mode `0600`;
- do not print or copy current credential values;
- create a new Packaging Read PAT or rotate the existing PAT because the old values
  were stored in files with overly broad permissions and one became visible during
  diagnosis;
- leave old sources intact until the work test passes.

### Phase 1: install mise-owned authentication

Add a machine-level setup script to the agentic developer toolkit rather than this
product workspace. The script:

1. prompts for the PAT without echo;
2. creates the secret directory and file atomically with modes `0700` and `0600`;
3. writes the global mise fragment without embedding the PAT;
4. records a current Maven settings symlink's target without copying its contents;
   for a regular settings file only, creates a mode-`0600` quarantine backup; then
   replaces the active path with a regular WSL-owned environment-reference-only
   settings file;
5. validates file syntax and reports variable presence only;
6. never puts the PAT in arguments, stdout, logs, repository files, or generated
   effective-settings output.

The script supports rotation by rerunning it. A former symlink rolls back by restoring
the recorded target; a former regular file uses its quarantine backup. Any quarantine
backup is an intentional temporary duplicate and is deleted only after the work test
and rollback window.

### Phase 2: work test

Run all tests with temporary empty caches while old credential sources still exist,
but explicitly remove them from each test process so only mise can authenticate:

```bash
env -u VSS_NUGET_EXTERNAL_FEED_ENDPOINTS \
    -u ARTIFACTS_CREDENTIALPROVIDER_EXTERNAL_FEED_ENDPOINTS \
    ~/.local/bin/mise exec -- <command>
```

The mise-loaded source-specific variables remain present because they are added after
the parent environment is sanitized.

#### Maven gates

Use a temporary `maven.repo.local` and run at minimum:

- `foundation-api-rest`: `mvn -B -ntp clean test`
- `foundation-device-core`: `mvn -B -ntp clean test`
- `foundation-cloud-lib-java`: `mvn -B -ntp clean test`
- `foundation-cloud-parent-maven`: `mvn -B -ntp clean install`

Success requires private `io.gewiss` dependencies to download without 401/403 and no
PAT value in output.

#### NuGet gates

Use fresh `NUGET_PACKAGES` and `NUGET_HTTP_CACHE_PATH` directories and run restore,

- `joinon-recharge-session`
- `joinon-datalog`
- `joinon-rfid`
- `foundation-cloud-lib-dotnet`

Success requires no `NU1301` or HTTP 401. Existing test failures must be recorded as
baselines and distinguished from authentication failures. The shared library is a
mandatory separate gate because its config uses the legacy
`gewiss-resel.pkgs.visualstudio.com` endpoint and has a mismatched credential section.

#### Harness gates

For Claude Code, Codex, and OpenCode:

- invoke a sanitized `mise exec` child;
- verify expected credential variable names are present without reading values;
- run one cold Maven dependency resolution and one cold NuGet restore from each
  harness type, or prove that the harnesses launch the same mise binary and inherited
  HOME with equivalent process-boundary tests;
- verify the persistent OpenCode service needs no restart or environment drop-in for
  mise's global file to take effect.

#### Negative controls

Use two distinct controls:

1. With an isolated HOME that has no mise secret fragment, mise must fail template
   evaluation. This is a configuration negative only; it does not prove feed
   authentication.
2. With the real mise fragment loaded, override only the last-hop Maven and NuGet
   credentials with the literal test value `invalid`, use fresh caches, and require
   Azure Artifacts HTTP 401/`NU1301`. Run a Foundation-only NuGet probe as well as
   the JoinOn service restore. These are the authentication negatives.

Inventory the user NuGet credential sections, Microsoft Credential Provider session
token location, MSAL cache, and NuGet plugin cache without reading credential values.
Together with the poisoned controls, this proves green tests are not cache hits or an
unrecognized inherited credential.

### Phase 3: remove confirmed host duplicates

Only after all Phase 2 gates pass:

- remove `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` from
  `joinon-foundation/env.local` and `env.example`;
- retain the new non-secret WSL `~/.m2/settings.xml`;
- confirm `~/.nuget/NuGet/NuGet.Config` has no credentials;
- restart fresh Claude, Codex, and OpenCode sessions and repeat one cold Maven and
  NuGet smoke test;
- issue a replacement Packaging Read PAT, rerun the configurator, run
  `--verify-only`, and repeat the post-cleanup cold Maven and NuGet smoke tests;
- revoke the superseded PAT only after the replacement passes those tests;
- remove or sanitize the plaintext Windows Maven settings target, then delete the
  rollback symlink after the bounded rollback window closes.

The initial live migration may be explicitly authorized to reuse the current PAT.
When it does, the PAT in mise and the PAT in the rollback target are the same value:
revoking the "old" PAT before rotating mise would revoke the live credential. The
rollback window is therefore bounded to the interval from initial migration through
successful replacement-PAT smoke testing at the end of Phase 3.

By 2026-09-14, either complete replacement-PAT rotation, smoke testing, and revocation, or roll back or stop using the exposed credential.
This is an operational deadline, not automatic enforcement.

Do not remove Git Credential Manager, Azure CLI/MSAL state, the Azure Artifacts
Credential Provider, package caches, or OpenCode runtime secrets. They serve distinct
consumers.

### Phase 4: repository and container cleanup

Treat tracked repository cleanup as a separate cross-repository change:

- assess removing the three .NET `packageSourceCredentials` placeholder sections;
- prove `NuGetAuthenticate@1` works without the duplicated pipeline substitution;
- replace or remove three duplicated .NET devcontainer token-injection scripts;
- assess consolidating eight Java devcontainer settings copies;
- validate Dev Container rebuilds from empty Maven/NuGet caches;
- test both branch and tag pipelines before removing CI compatibility code.

These changes require each independent repository's branch, PR, and release workflow.
They must not be bundled into the host migration.

## Rollback

Before cleanup, rollback is immediate:

1. disable or remove `~/.config/mise/conf.d/azure-artifacts.toml`;
2. restore the prior Maven settings symlink from the recorded backup;
3. keep the existing `env.local` NuGet value active;
4. start a fresh shell or harness process;
5. repeat one Maven and NuGet restore.

If initial migration reused the current PAT, rollback restores the old configuration
only until replacement-PAT smoke testing succeeds. After the current PAT is revoked,
rollback must use a newly issued PAT rather than restoring the exposed value.

## Security Properties

- One PAT exists in one WSL-owned file with mode `0600`.
- Ecosystem configs and mise TOML contain references only.
- Mise redacts all derived variable names in managed task output.
- The PAT is not stored in Git, systemd, OpenCode configuration, Maven settings,
  NuGet config, or shell startup files.
- CI identities remain independent of the developer PAT.
- Cleanup is evidence-gated and does not delete distinct credential systems.

## Acceptance Criteria

- Global mise config loads all derived Maven/NuGet variable names without printing
  values.
- Maven resolves the Foundation feed from a cold cache in all representative repos.
- NuGet restores Foundation and JoinOn packages from cold caches in all four .NET
  repos.
- Claude Code, Codex, and OpenCode can execute both ecosystems through mise without
  interactive authentication.
- `env.local` no longer contains Azure Artifacts credentials after cleanup.
- Maven settings contains `${env.AZDO_MAVEN_PAT}`, never a PAT value.
- User NuGet config contains no credentials.
- Repository and CI cleanup remains deferred until its own work tests pass.
