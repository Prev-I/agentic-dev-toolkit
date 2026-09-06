# WSL Toolchain Doctor

Enforces a Linux-first development boundary inside WSL: it audits PATH hygiene,
validates `mise`-managed tool bindings, and can conservatively remediate the
WSL configuration and persistent PATH sources.

Version **0.3.0**, JSON schema version `1`. Bash only — no Python, Java, .NET,
Node.js, Go or `jq`.

## Files

| Path | Purpose |
| --- | --- |
| `wsl-toolchain-doctor/wsl-toolchain-doctor.sh` | The tool |
| `tests/wsl-toolchain-doctor.sh` | Dependency-free regression suite |
| `docs/wsl-toolchain-doctor.md` | Operational documentation |
| `docs/superpowers/specs/2026-09-05-wsl-toolchain-doctor-design.md` | Design and invariants |
| `docs/superpowers/plans/2026-09-05-wsl-toolchain-doctor.md` | Implementation and verification plan |

## Quick start inside WSL

```bash
bash tests/wsl-toolchain-doctor.sh

./wsl-toolchain-doctor/wsl-toolchain-doctor.sh --version
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit --json
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh explain java

./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path --dry-run
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --path --drop-missing
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh fix --all
```

`--dry-run` is the safe way to see what `fix --path` would rewrite. `fix`
without `--path` touches only `/etc/wsl.conf`.

## Core policy

- WSL interop stays enabled; automatic Windows PATH import is disabled.
- Generic Windows-backed PATH entries fail.
- Rancher Desktop gets only a narrow Linux container-tool exception, limited to
  `resources/resources/linux/bin` and `resources/resources/linux/docker-cli-plugins`.
  Managed language runtimes never receive it, and PE/MZ always fails.
- `mise` is the source of truth for configured language/tool versions.
- Java, .NET, Python, Maven and uv names are a collision watchlist, not a static
  required-tool matrix — a tool mise does not configure is not reported missing.
- PATH hygiene covers malformed syntax, duplicates, missing and non-directory
  entries, relative and current-directory entries, literal variables and quotes,
  control characters, and Windows provenance.
- `fix --path` rewrites only a deliberately small safe subset of persistent
  `PATH=...` assignments; dynamic expressions are refused, not guessed.
- Profile files are parsed as text. Production code never sources or evals them.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | No `FAIL`; warnings may remain |
| `1` | Policy violations remain |
| `2` | Unsupported environment, invalid arguments, ambiguous configuration, or remediation error |
| `10` | `wsl.conf` changed; restart WSL and rerun `audit` |
| `11` | Persistent PATH source changed; start a new login shell and rerun `audit` |

For agent and harness integration, prefer `--json`.
