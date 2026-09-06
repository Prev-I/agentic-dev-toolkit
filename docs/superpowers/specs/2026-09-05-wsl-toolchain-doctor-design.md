# WSL Toolchain Doctor Design - v0.3.0

## Context

Development happens inside WSL. Windows interoperability must remain available for explicit Windows process launches, while automatic Windows PATH import must be disabled so Linux development tooling cannot accidentally bind to Windows executables. Rancher Desktop WSL integration is the narrow exception: Linux container-tool binaries distributed by Rancher Desktop may reside on a Windows-backed mount.

Language and build tool versions are managed by `mise`. The doctor must therefore validate origin and binding, not impose a second static toolchain inventory.

## Drivers

- Deterministic Linux-first command resolution inside WSL.
- Bash-only bootstrap with no Python/.NET/Java/Node/jq dependency.
- Preserve `interop.enabled=true` and enforce `interop.appendWindowsPath=false`.
- Detect malformed, duplicate, missing, relative, non-directory, and Windows-backed PATH entries.
- Detect shadowing, symlink escapes, PE executables, Windows shebangs, and suspicious wrappers.
- Treat `mise` as source of truth for configured runtime/tool versions.
- Permit Rancher Desktop only for Linux container tooling under its Linux resource tree.
- Conservative, reversible remediation with dry-run and backups.
- Human and JSON output from one finding model.

## Invariants

1. The production entrypoint runs under Bash inside WSL.
2. Effective WSL policy is `[interop] enabled=true` and `appendWindowsPath=false`.
3. Generic Windows-backed DrvFs/9p PATH directories fail policy.
4. `Rancher Desktop/resources/resources/linux/bin` is the only Windows-backed PATH exception, and only Linux container tooling may use it.
5. Managed language/tool commands must never resolve to PE/Windows targets or to Rancher Desktop paths.
6. Container commands may use the Rancher exception only when the final file is ELF or a Linux script.
7. Symlinks are classified by final target.
8. The effective PATH is audited for raw Windows syntax, separators, literal quotes/variables, control characters, repeated escaping, empty entries, textual/canonical duplicates, relative/current-directory entries, missing entries, and non-directories.
9. `mise` decides which watched tools are configured. The doctor never turns the collision watchlist into a required-tool matrix.
10. A Linux-backed `mise` executable is required before trusting `mise ls`/`mise which` results.
11. A configured mise tool may be absent from a non-activated shell PATH without failing when `mise which` resolves it.
12. Windows shadowing of a mise-selected tool always fails. Different Linux shadowing fails only when mise activation is detected; otherwise it is informational.
13. Startup/profile files are parsed as text only. The doctor never uses `eval` or `source` to interpret them.
14. `fix` without a scope modifies only `wsl.conf`.
15. `fix --path` rewrites only a deliberately narrow static `PATH=...` grammar; dynamic/ambiguous expressions are refused with `PATH_AUTO_FIX_UNSAFE`.
16. Persistent PATH remediation never escalates privileges. Every changed profile receives a sibling backup and an atomic same-directory replacement.
17. `--drop-missing` applies only to safe persistent PATH assignments and is opt-in.
18. `fix --all` combines WSL and PATH remediation. Restart-required exit `10` takes precedence over new-shell exit `11`.
19. A changed `wsl.conf` never implies the current shell PATH has changed; a changed profile never implies the current process PATH has changed.
20. JSON schema version remains `1` for v0.3.0.

## Interface

```text
wsl-toolchain-doctor.sh audit [--json]
wsl-toolchain-doctor.sh fix [--path|--all] [--dry-run] [--drop-missing] [--json]
wsl-toolchain-doctor.sh explain <command> [--json]
wsl-toolchain-doctor.sh --version
```

Exit codes:

- `0`: completed with no FAIL findings; warnings may remain.
- `1`: policy violations remain.
- `2`: unsupported environment, invalid arguments, ambiguous configuration, or remediation error.
- `10`: `wsl.conf` changed and WSL restart is required.
- `11`: persistent PATH source changed and a new login shell is required.

## Collision watchlist

Managed names are inspected for Windows collisions but are not required to exist globally:

- .NET: `dotnet`, `dotnet.exe`
- Java/JDK: `java`, `javac`, `jar` and `.exe` variants
- Maven: `mvn`, `mvnDebug`, `.cmd` and `.bat` variants
- Python: `python`, `python3`, `pip`, `pip3` and Windows variants
- uv: `uv`, `uvx` and Windows variants

Container integration names:

- `docker`, `docker-compose`, `nerdctl`, `kubectl`, `helm` and Windows variants

## mise ownership model

When `mise` is available and Linux-backed, the doctor queries:

```text
mise ls --current --no-header
mise which <primary-binary>
```

Watched mapping:

| mise tool | primary binary |
| --- | --- |
| `java` | `java` |
| `maven` | `mvn` |
| `python` | `python` |
| `uv` | `uv` |
| `dotnet` | `dotnet` |

Outcomes:

- tool not configured by mise: no missing-tool failure;
- configured + `mise which` unresolved: FAIL;
- mise target Windows/PE: FAIL;
- current PATH target equals mise target: PASS/INFO;
- no current PATH target: INFO (`mise exec`/non-activated shell is valid);
- current target Windows-backed: FAIL;
- different Linux target with activation detected: FAIL;
- different Linux target without activation: INFO.

## PATH detection model

### Raw syntax pass

Before POSIX colon segmentation, the raw PATH is checked for:

- Windows drive syntax (`C:\...`);
- semicolon separators;
- literal quote characters;
- unexpanded shell/Windows variable tokens;
- CR/LF/TAB;
- suspicious repeated backslashes;
- empty segments.

### Entry pass

Every segmented entry is then checked for textual duplicates, canonical duplicates, current/relative path use, existence, directory type, mount provenance, and the Rancher exception.

Mount provenance comes from the configured procfs mount table and longest-prefix matching; `/mnt/c` is never hard-coded.

## Tool classification

All matching candidates in the scanned PATH are enumerated, not only the first one. Final targets are resolved with `readlink -f` where possible. Magic bytes classify:

- ELF: `7f 45 4c 46`
- PE/MZ: `4d 5a`
- script: `23 21`
- otherwise: `OTHER`

Scripts have their shebang inspected. Managed-tool scripts are also conservatively scanned for explicit `.exe`, `.cmd`, `.bat`, or Windows-drive references; that heuristic is WARN unless another definitive Windows rule fails.

## Persistent PATH remediation

The fixer scans the same profile/source set used by the audit. A line is eligible only when it is a simple `PATH=...` or `export PATH=...` assignment with no command substitution, backticks, trailing comment, shell operators, or unsupported variable expansion.

For eligible assignments it may:

- remove empty segments;
- remove textual duplicates, first occurrence wins;
- remove canonical duplicates among existing directories;
- remove generic Windows-backed segments;
- preserve Rancher Desktop Linux-bin segments;
- remove entries that exist but are not directories;
- preserve missing entries by default;
- remove missing entries only with `--drop-missing`;
- preserve `$PATH`, `${PATH}`, `$HOME`, `${HOME}`, and `~/...` expressions without evaluating them.

Each actual modification creates `<profile>.bak.YYYYMMDD-HHMMSS.PID`. Preview rendering happens in a temporary file; the same-directory candidate is created only for a real write, then atomically renamed.

Dynamic or ambiguous assignments are left byte-for-byte unchanged and reported as `PATH_AUTO_FIX_UNSAFE` during PATH remediation.

## WSL remediation

Zero or one `[interop]` section is supported. Duplicate sections/keys are ambiguous and refused. The fixer preserves unrelated sections/comments, ensures exactly the policy values, backs up an existing file, and atomically replaces it. `sudo` is used only for `wsl.conf` when required.

## Failure model

- Configuration policy and runtime `WSLInterop` handler state are independent.
- Unknown formats/filesystems warn unless a definitive rule fails.
- Dry-run is non-mutating.
- Current-process PATH is never reported as changed by child-process remediation.
- Ambiguous shell/config syntax is refused rather than guessed.

## Testing

The Bash-only regression suite uses synthetic WSL config, mount, PATH, binary, profile, and mise fixtures. v0.3.0 coverage includes the original behavior plus PATH hygiene, safe PATH remediation, dry-run, `--drop-missing`, exit `11`, combined remediation, and mise-aware binding/shadowing.
