# Azure Artifacts Host Rotation Evidence

## Status

| Area | Status |
|---|---|
| WSL mise configuration | `PASS` |
| WSL Maven cold-cache build | `PASS` |
| WSL NuGet cold-cache restore | `PASS` |
| Windows-native Maven | `PASS` |
| Superseded PAT | `REVOKED` |
| Credential-bearing rollback material | `REMOVED` |
| CI and devcontainers | `DEFERRED` |
| Full multi-repository qualification matrix | `DEFERRED` |

On 2026-09-13, the replacement Packaging Read PAT passed structural verification through
`azure-artifacts/configure.sh --verify-only`. No credential values were printed or retained in the
evidence.

## Runtime Evidence

- WSL Maven used an empty temporary repository to run `clean test` for `foundation-api-rest`.
  Private `io.gewiss` dependencies resolved and all four tests passed.
- WSL NuGet used empty package and HTTP caches to restore the complete `joinon-datalog` solution.
  The restore completed without `NU1301`, HTTP 401, or HTTP 403.
- Windows-native Maven used a Windows-local empty repository and the committed wrapper design to
  resolve `io.gewiss:foundation.commons.core:0.0.9-SNAPSHOT` from the `Foundation` feed. Maven
  reported `BUILD SUCCESS`.
- A Maven `dependency:go-offline` probe failed independently on a legacy HTTP JAXB repository
  blocked by modern Maven. The normal WSL `clean test` gate succeeded from a separate empty cache.
- Running the complete Java project from Windows against the WSL UNC checkout resolved private
  dependencies but later failed because JaCoCo could not lock its output file on the UNC filesystem.
  The Windows-local dependency probe removed that unrelated filesystem boundary from the
  authentication test.

## Credential State

- WSL keeps the active PAT only in the mode-`0600` mise secret file.
- Active WSL and Windows Maven settings use `${env.AZDO_MAVEN_PAT}` and contain no literal PAT.
- Windows Credential Manager holds the native-Maven copy under the Generic Credential target
  `agentic-dev-toolkit/AzureArtifacts`.
- The Windows wrapper launches a dedicated child PowerShell process containing `AZDO_MAVEN_PAT`;
  Maven inherits it there, while the invoking PowerShell process and persistent user environment
  remain unchanged.
- The obsolete workspace NuGet provider variable is absent.
- The credential-bearing Maven rollback symlink and temporary `env.local` backup were removed.
- On 2026-09-14, the operator attested that the superseded PAT was revoked after all
  replacement-token gates passed.
- Gitleaks found no leaks after credential-bearing temporary evidence was removed.

## Remaining Scope

This evidence proves one representative Maven and one representative NuGet cold-cache path plus
Windows-native Maven. It does not claim completion of the broader four-Maven/four-NuGet and
three-harness matrix in the original implementation plan. CI and devcontainer credential migration
also remains deferred and continues to use its independently managed authentication.
