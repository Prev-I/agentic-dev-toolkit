# Azure Artifacts Through Mise

This is an opt-in organization-specific Gewiss adapter, not part of the portable,
company-neutral core toolkit. It configures host-side Azure Artifacts authentication for the
Gewiss Azure DevOps organization `gewiss-resel`; do not adopt it outside that organization without
replacing and qualifying every hard-coded contract below.

## Contracts

- The PAT belongs to `gewiss-resel` and has `Packaging Read` scope.
- Maven uses server ID `Foundation` and the feed
  `https://pkgs.dev.azure.com/gewiss-resel/Foundation/_packaging/Foundation/maven/v1`.
- NuGet source names `Foundation` and `JoinOn` are case-sensitive. mise supplies their credentials
  through `NuGetPackageSourceCredentials_Foundation` and
  `NuGetPackageSourceCredentials_JoinOn`.
- Maven receives `${env.AZDO_MAVEN_PAT}` in the active `~/.m2/settings.xml`; active NuGet and
  Maven configuration files contain references only, never a PAT. The temporary rollback path can
  still expose the superseded PAT: a regular-file backup copies it with mode `0600`, while a
  symlink preserves access to its original target.

## Host Operation

Run `./azure-artifacts/configure.sh` from the repository root to configure the host, then run
`./azure-artifacts/configure.sh --verify-only`. The secret is stored only at
`~/.config/mise/secrets/azure-artifacts.env`; mise loads it through
`~/.config/mise/conf.d/azure-artifacts.toml`. Do not run `mise env`, `env`, or verbose diagnostic
dumps in support transcripts because they can expose values. Real PATs never belong in Git.
Normal setup and rotation use the hidden `/dev/tty` prompt. `--pat-stdin` is for migration or
controlled automation only.

## Windows-Native Maven

Windows-native Maven is supported through a separate wrapper. Run the Windows configurator from
PowerShell after configuring WSL:

```powershell
.\azure-artifacts\configure-windows.ps1
& "$env:USERPROFILE\.local\bin\mvn-azure.ps1" -version
```

The configurator uses a hidden prompt, stores the PAT as the Generic Credential
`agentic-dev-toolkit/AzureArtifacts` in Windows Credential Manager, installs the wrapper and its
credential module under `%USERPROFILE%\.local\bin`, and replaces the `Foundation` password in
Windows `%USERPROFILE%\.m2\settings.xml` with `${env.AZDO_MAVEN_PAT}`. It validates before prompting,
refuses `DOCTYPE` and ambiguous `Foundation` entries, and atomically replaces settings. A same-volume
rollback file exists only during that transaction and is deleted after Credential Manager accepts
the PAT; retaining a plaintext Windows backup would recreate the exposure this adapter removes.
`-PatStdin` is reserved for controlled migration and automated tests; normal setup and rotation must
use the hidden prompt.

Invoke Windows Maven through `mvn-azure.ps1`, not `mvn.cmd` directly. The wrapper retrieves the
credential, creates a dedicated child PowerShell process whose environment contains
`AZDO_MAVEN_PAT`, and runs Maven there. Output and exit status flow through normally. The invoking
PowerShell process and persistent Windows user environment never receive the PAT.

To remove Windows support, first replace or remove the `Foundation` environment reference in
Windows Maven settings. Then delete the Generic Credential and the three installed files:

```powershell
Import-Module "$env:USERPROFILE\.local\bin\AzureArtifactsCredential.psm1"
$target = (Get-Content "$env:USERPROFILE\.local\bin\azure-artifacts-target.txt" -Raw).Trim()
Remove-AzureArtifactsCredential -Target $target
Remove-Item "$env:USERPROFILE\.local\bin\mvn-azure.ps1"
Remove-Item "$env:USERPROFILE\.local\bin\AzureArtifactsCredential.psm1"
Remove-Item "$env:USERPROFILE\.local\bin\azure-artifacts-target.txt"
```

The Windows credential is a second protected copy of the same PAT, required only for native
Windows Maven. WSL Maven and NuGet continue to use the mise-managed secret and never read Windows
Credential Manager.

To rotate, rerun the configurator with a new Packaging Read PAT, verify it, and complete the
cold-cache work test. Revoke the old PAT only after the new PAT passes verification and the work
test, and rollback no longer needs the old credential.

When initial migration reused an exposed current PAT, keep the rollback window as short as
practical. Until a replacement PAT passes verification and cold-cache smoke tests, either complete
that rotation promptly or roll back or stop using the exposed credential. After the replacement is
proven, revoke the superseded PAT, remove or sanitize the plaintext Windows Maven settings target,
and delete the rollback copy or symlink.

To roll back, first disable the exact mise fragment and move or remove generated settings. The
secret file remains dormant and unloaded once the fragment is disabled; remove it after rollback if
it is no longer needed.

If `~/.m2/settings.xml.pre-mise-azure-artifacts` exists, restore the recorded settings object with
`mv`; this preserves the rollback path itself if it is a symlink:

```bash
mv ~/.m2/settings.xml ~/.m2/settings.xml.mise-azure-artifacts-disabled
mv ~/.config/mise/conf.d/azure-artifacts.toml ~/.config/mise/conf.d/azure-artifacts.toml.disabled
mv ~/.m2/settings.xml.pre-mise-azure-artifacts ~/.m2/settings.xml
```

Treat that rollback object as credential-bearing until inspected and retired. The configurator
also enforces mode `0700` on `~/.m2`; rollback does not restore a former directory mode.

If `~/.m2/settings.xml.pre-mise-azure-artifacts` does not exist, this was a fresh host: move or
remove the generated settings and exact TOML fragment, then leave `~/.m2/settings.xml` absent.
Start a fresh process and repeat one cold Maven restore and one cold NuGet restore. Do not run
`--verify-only` after disabling authentication because it should fail.

CI and devcontainers are outside the host migration and retain independent authentication until
separately qualified. Maven migration preserves semantic XML, comments, and processing
instructions, but does not provide byte-preserved formatting, and refuses `DOCTYPE` input.

Sanitized host validation evidence is recorded in
[`docs/evidence/2026-09-14-host-rotation.md`](docs/evidence/2026-09-14-host-rotation.md).
