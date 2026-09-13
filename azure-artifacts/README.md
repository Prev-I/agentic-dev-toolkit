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
- Maven receives `${env.AZDO_MAVEN_PAT}` in `~/.m2/settings.xml`; NuGet and Maven configuration
  files contain references only, never a PAT.

## Host Operation

Run `./azure-artifacts/configure.sh` from the repository root to configure the host, then run
`./azure-artifacts/configure.sh --verify-only`. The secret is stored only at
`~/.config/mise/secrets/azure-artifacts.env`; mise loads it through
`~/.config/mise/conf.d/azure-artifacts.toml`. Do not run `mise env`, `env`, or verbose diagnostic
dumps in support transcripts because they can expose values. Real PATs never belong in Git.
Normal setup and rotation use the hidden `/dev/tty` prompt. `--pat-stdin` is for migration or
controlled automation only.

To rotate, rerun the configurator with a new Packaging Read PAT, verify it, and complete the
cold-cache work test. Revoke the old PAT only after the new PAT passes verification and the work
test, and rollback no longer needs the old credential.

When initial migration reused the exposed current PAT, its rollback exposure has a hard deadline:
By 2026-09-14, either complete replacement-PAT rotation, smoke testing, and revocation, or roll back or stop using the exposed credential.
This is an operational deadline, not automatic enforcement.

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

If `~/.m2/settings.xml.pre-mise-azure-artifacts` does not exist, this was a fresh host: move or
remove the generated settings and exact TOML fragment, then leave `~/.m2/settings.xml` absent.
Start a fresh process and repeat one cold Maven restore and one cold NuGet restore. Do not run
`--verify-only` after disabling authentication because it should fail.

CI and devcontainers are outside the host migration and retain independent authentication until
separately qualified. Maven migration preserves semantic XML, comments, and processing
instructions, but does not provide byte-preserved formatting, and refuses `DOCTYPE` input.
