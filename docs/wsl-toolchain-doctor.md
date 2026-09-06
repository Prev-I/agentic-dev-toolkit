# WSL Toolchain Doctor

`wsl-toolchain-doctor.sh` enforces a Linux-first development boundary inside WSL, audits PATH hygiene, validates `mise`-managed tool bindings, and can conservatively remediate persistent PATH sources.

Current tool version: `0.3.0`.

## Policy

The expected WSL configuration is:

```ini
[interop]
enabled=true
appendWindowsPath=false
```

Windows processes can still be invoked explicitly, while the Windows PATH is not automatically appended to the Linux PATH.

The effective development PATH must otherwise be Linux-backed. A Windows-backed DrvFs entry is a failure except for Rancher Desktop's narrow `resources/resources/linux/bin` exception. Even there, only known container tooling may use the exception and the final target must be ELF or a Linux script.

## Tool ownership: mise is authoritative

The doctor does **not** require a static global installation of Java, .NET, Python, Maven, or uv.

If `mise` is available, it becomes the toolchain source of truth for the current directory context:

```text
mise ls --current --no-header
        -> which watched tools are configured here

mise which <primary-binary>
        -> executable selected by mise

current PATH
        -> executable this shell would resolve directly
```

The watched mise tool mapping is intentionally small:

| mise tool | Primary binding checked |
| --- | --- |
| `java` | `java` |
| `maven` | `mvn` |
| `python` | `python` |
| `uv` | `uv` |
| `dotnet` | `dotnet` |

The larger command list remains a **collision watchlist**, not a required-tool matrix:

- .NET: `dotnet` plus Windows variant;
- Java/JDK: `java`, `javac`, `jar` plus Windows variants;
- Maven: `mvn`, `mvnDebug`, `.cmd` and `.bat` variants;
- Python: `python`, `python3`, `pip`, `pip3` plus Windows variants;
- uv: `uv`, `uvx` plus Windows variants;
- containers: `docker`, `docker-compose`, `nerdctl`, `kubectl`, `helm` plus Windows variants.

Consequences:

- a tool not configured by mise is not reported as missing;
- a tool configured by mise but not exposed in the current PATH is informational when `mise which` resolves it; this is valid for non-activated shells using `mise exec`;
- if mise itself is Windows-backed, the audit fails and its answers are not trusted;
- if `mise which` selects a Windows-backed target, the audit fails;
- if the current PATH resolves a watched primary binary to a Windows-backed target before the mise target, the audit fails;
- if mise activation is detected and a different Linux binary shadows the mise target, the audit fails;
- if activation is not detected and a different Linux binary is present, the mismatch is informational and explicitly recommends `mise exec` or activation.

The implementation does not need `jq`; it uses the stable first column of `mise ls --current --no-header` and the path returned by `mise which`.

## Layout in this repository

```text
agentic-dev-toolkit/
|-- wsl-toolchain-doctor/
|   |-- README.md
|   `-- wsl-toolchain-doctor.sh
|-- tests/
|   `-- wsl-toolchain-doctor.sh
`-- docs/
    |-- wsl-toolchain-doctor.md
    `-- superpowers/
        |-- plans/2026-09-05-wsl-toolchain-doctor.md
        `-- specs/2026-09-05-wsl-toolchain-doctor-design.md
```

The tool is tracked executable (`100755`); the suite entry point under `tests/`
is `100644` and is always run as `bash tests/wsl-toolchain-doctor.sh`.

The production script requires Bash and normal Linux base utilities such as `grep`, `head`, `od`, `readlink`, `stat`, `install`, `cp`, `mv`, and `mktemp`. It does not require Python, Java, .NET, Node.js, Go, or `jq`.

## Usage

### Audit

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit --json
```

The audit checks:

1. execution inside WSL;
2. the current `WSLInterop` binfmt handler;
3. effective `[interop]` policy;
4. PATH raw syntax before POSIX colon segmentation;
5. every PATH entry and its backing mount;
6. textual and canonical duplicate entries;
7. nonexistent entries and entries that are files instead of directories;
8. relative and current-directory entries;
9. leaked Windows `C:\...` syntax and `;` separators;
10. literal quotes, unexpanded variable tokens, CR/LF/TAB, and suspicious excessive escaping;
11. all matching candidates in the collision watchlist, including shadowed candidates;
12. symlink final targets, PE/ELF/script magic, and shebang interpreters;
13. suspicious managed-tool wrappers containing explicit Windows executable references;
14. mise ownership and binding for tools configured in the current mise context;
15. startup/environment files that can reintroduce generic Windows paths.

Startup files are parsed as text. They are never sourced or evaluated.

### Explain one command

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh explain java
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh explain dotnet
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh explain docker
```

`explain` enumerates every candidate for that exact command name in the scanned PATH and reports each final target and format.

It intentionally does not interpret mise configuration. Use `audit` for mise-aware ownership checks.

## PATH hygiene findings

Important effective-PATH codes include:

- `PATH_EMPTY_ENTRY` - warning;
- `PATH_DUPLICATE` - textual duplicate warning;
- `PATH_DUPLICATE_CANONICAL` - distinct spellings resolving to the same existing directory;
- `PATH_ENTRY_MISSING` - warning by default;
- `PATH_ENTRY_NOT_DIRECTORY` - failure;
- `PATH_CURRENT_DIRECTORY` - failure;
- `PATH_RELATIVE_ENTRY` - warning;
- `PATH_WINDOWS_DRVFS` - failure;
- `PATH_WINDOWS_SYNTAX` - Windows drive syntax such as `C:\...`;
- `PATH_WINDOWS_SEPARATOR` - `;` in a WSL PATH;
- `PATH_LITERAL_QUOTE` - quote character leaked into the effective PATH;
- `PATH_LITERAL_VARIABLE` - unexpanded `$HOME`, `${HOME}`, `%USERPROFILE%`, or `%SystemRoot%`;
- `PATH_CONTROL_CHAR` - CR/LF/TAB;
- `PATH_EXCESSIVE_ESCAPE` - suspicious backslash escaping.

The raw-syntax pass runs before colon segmentation, so malformed Windows input is not silently reduced to misleading Linux-looking fragments.

## mise findings

Important codes include:

- `MISE_NOT_AVAILABLE` - informational; no static required-tool matrix is substituted;
- `MISE_LINUX` - mise itself is Linux-backed;
- `MISE_WINDOWS_BACKED` - failure; mise cannot be trusted as source of truth;
- `MISE_QUERY_FAILED` - mise context could not be queried;
- `MISE_TOOL_CONFIGURED` - watched tool present in the current mise context;
- `MISE_TOOL_UNRESOLVED` - configured tool has no resolvable primary executable;
- `MISE_TOOL_LINUX` - mise selected a Linux-backed target;
- `MISE_TOOL_WINDOWS_BACKED` - mise selected a Windows-backed target;
- `MISE_BINDING_OK` - current PATH and mise resolve the same executable;
- `MISE_TOOL_NOT_EXPOSED` - mise resolves the tool but this shell does not expose it;
- `MISE_TOOL_NOT_ACTIVATED` - a different Linux executable is visible and shell activation is not detected;
- `MISE_TOOL_SHADOWED` - active mise context is shadowed by a different Linux executable;
- `MISE_TOOL_SHADOWED_WINDOWS` - current PATH shadows the mise selection with Windows-backed tooling.

## Remediation

### WSL configuration only

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix
```

Only `/etc/wsl.conf` may be modified. An existing file is backed up, unrelated sections/comments are preserved, duplicate ambiguous `[interop]` sections/keys are refused, and the replacement is staged then renamed into place.

If it changes, run from Windows:

```powershell
wsl.exe --shutdown
```

then reopen the distro and rerun `audit`.

### Persistent PATH only

Preview:

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path --dry-run
```

Apply safe fixes:

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path
```

Optionally remove explicit static entries whose resolved target does not exist:

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path --drop-missing
```

Missing source entries are preserved by default because they may represent optional tools installed later.

The rewrite grammar is deliberately narrow. A typical safe assignment is:

```bash
export PATH="$HOME/.local/bin:$HOME/.local/bin:/mnt/c/Tools:$PATH"
```

For a safe assignment the fixer can:

- remove empty segments;
- remove textual duplicates, preserving the first occurrence;
- remove canonical duplicates among existing directories;
- remove generic Windows-backed DrvFs segments;
- preserve the Rancher Desktop Linux-bin exception;
- remove entries that exist but are not directories;
- preserve missing entries by default, or drop them with `--drop-missing`;
- preserve `$PATH`, `${PATH}`, `$HOME`, `${HOME}`, and `~/...` expressions without evaluating shell code.

Each modified profile receives a sibling backup:

```text
.profile.bak.YYYYMMDD-HHMMSS.PID
```

The preliminary rewrite is rendered in `/tmp`. A same-directory candidate is created only when a real modification is needed, then renamed over the original. This avoids requiring write access to `/etc` merely to inspect system profiles.

The PATH fixer does **not** escalate privileges for shell/profile files. A file that needs modification but is not writable is reported as `PATH_PROFILE_NOT_WRITABLE`.

### Dynamic or ambiguous assignments

The fixer refuses expressions such as:

```bash
export PATH="$(some-command):$PATH"
export PATH="${SDKMAN_CANDIDATES_DIR}/java/current/bin:$PATH"
export PATH="/some/path:$PATH" # trailing comment
```

They produce `PATH_AUTO_FIX_UNSAFE` when `fix --path` is requested and remain byte-for-byte unchanged.

A normal mise activation line is not a PATH assignment and is left untouched:

```bash
eval "$(mise activate bash)"
```

The doctor never uses `eval` or `source` to interpret profile code.

### WSL + PATH

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --all
```

This combines WSL remediation and safe persistent-PATH remediation. If both layers change, WSL restart code `10` takes precedence over new-shell code `11`. A remaining blocking finding still returns `1`.

### Dry-run

`--dry-run` can also be combined with the default WSL fix or `--all`. It reports proposed persistent changes without writing them.

## Persistent sources scanned

By default the checker considers readable files among:

```text
~/.profile
~/.bash_profile
~/.bash_login
~/.bashrc
~/.zprofile
~/.zshrc
~/.config/environment.d/*.conf
/etc/environment
/etc/profile
/etc/bash.bashrc
/etc/profile.d/*.sh
```

`WTD_PROFILE_FILES` is available as a test/controlled-invocation override.

## Rancher Desktop exception

The exception is intentionally narrow. A pathname merely containing `Rancher Desktop` is not enough. The final target must be under:

```text
Rancher Desktop/resources/resources/linux/bin
```

and only known container tooling may use the exception. PE/MZ always fails.

Managed language/tooling never receives the Rancher exception.

## JSON mode

Examples:

```bash
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit --json
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --json
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path --json
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh explain java --json
```

Schema version remains `1`:

```json
{
  "schemaVersion": 1,
  "toolVersion": "0.3.0",
  "action": "audit",
  "status": "PASS",
  "findings": []
}
```

Possible status values include `PASS`, `WARN`, `FAIL`, `ERROR`, `RESTART_REQUIRED`, and `NEW_SHELL_REQUIRED`.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Completed with no `FAIL`; warnings may remain. |
| `1` | One or more policy violations remain. |
| `2` | Unsupported environment, invalid arguments, ambiguous configuration, or remediation error. |
| `10` | `wsl.conf` changed; restart WSL and rerun `audit`. |
| `11` | Persistent PATH source changed; start a new login shell and rerun `audit`. |

## Tests

Run:

```bash
bash -n wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh
bash tests/wsl-toolchain-doctor.sh
```

The suite uses synthetic mount/config/tool/profile/mise fixtures and does not mutate the host.

If ShellCheck is available:

```bash
shellcheck wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh
```

## Design constraints

- Do not hard-code `/mnt/c`; mount provenance is authoritative.
- Do not replace all-candidate enumeration with `which`.
- Do not turn the collision watchlist into a static required-tool matrix.
- Do not trust a Windows-backed mise executable.
- Do not treat a non-activated shell as equivalent to an activated mise shell.
- Do not broaden the PATH rewrite grammar casually; refusal is safer than rewriting valid dynamic shell code incorrectly.
- Do not source or eval profile files during diagnostics/remediation.

## References

- Microsoft WSL advanced settings: <https://learn.microsoft.com/windows/wsl/wsl-config>
- mise CLI: <https://mise.jdx.dev/cli/>
- mise dev tools: <https://mise.jdx.dev/dev-tools/>
- `mise ls`: <https://mise.jdx.dev/cli/ls.html>
- `mise which`: <https://mise.jdx.dev/cli/which.html>
- Rancher Desktop: <https://github.com/rancher-sandbox/rancher-desktop>
