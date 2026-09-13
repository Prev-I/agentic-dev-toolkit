# WSL Toolchain Doctor

Enforces a Linux-first development boundary inside WSL: it audits PATH hygiene,
validates `mise`-managed tool bindings, and can conservatively remediate the
WSL configuration and persistent PATH sources.

Version **0.5.0**, JSON schema version `1`. Bash only — no Python, Java, .NET,
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
./wsl-toolchain-doctor/wsl-toolchain-doctor.sh audit --probe
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
- A small allowlist of Windows-backed directories that hold Linux-executable
  launchers is accepted: Rancher Desktop's `resources/resources/linux/bin` and
  `resources/resources/linux/docker-cli-plugins`, and VS Code's `bin`. Extend it
  for one machine with `WTD_PATH_ALLOW` (colon-separated, matched as
  case-insensitive path substrings).
- **Allowlisting a directory does not allowlist a Windows binary inside it.**
  Tool classification is independent: a PE/MZ target still fails, so does a
  Windows shebang interpreter, and managed language runtimes never receive the
  exception regardless of where they resolve from.
- `mise` is the source of truth for configured language/tool versions.
- Java, .NET, Python, Maven and uv names are a collision watchlist, not a static
  required-tool matrix — a tool mise does not configure is not reported missing.
- PATH hygiene covers malformed syntax, duplicates, missing and non-directory
  entries, relative and current-directory entries, literal variables and quotes,
  control characters, and Windows provenance.
- `fix --path` rewrites only a deliberately small safe subset of persistent
  `PATH=...` assignments; dynamic expressions are refused, not guessed.
- Profile files are parsed as text. Production code never sources or evals them.

## Software catalog and install receipt

`--probe` opts `audit` into three comparisons against `install.sh`'s software
catalog and the install receipt it writes after a verified install:

- **A** — requested-configuration drift: receipt `requested.*` versus the
  toolkit-managed `mise` configuration. Runs on every `audit`.
- **B** — installed-machine drift: receipt `installed.*` versus a fresh probe
  of the machine. Opt-in, `--probe` only.
- **C** — catalog staleness: the current catalog versus receipt `requested.*`.
  Runs on every `audit` with a catalog available.

None of these findings is ever `FAIL` — a machine behind on a version is not a
policy violation the way a Windows PE on `PATH` is. The `TOOLKIT_*` codes:

- `TOOLKIT_NOT_PROVISIONED` — info; no install receipt found;
- `TOOLKIT_RECEIPT_UNREADABLE` — info; the receipt fails `adt-kv` validation;
- `TOOLKIT_RECEIPT_UNKNOWN_KEY` — info; the receipt names a component the
  catalog no longer pins, so that component is excluded from staleness
  checking. The pin was retired, or the receipt was hand-edited — the
  doctor cannot tell which. The receipt stays readable and every
  still-pinned component is still compared;
- `TOOLKIT_CATALOG_UNAVAILABLE` — info; the catalog is absent or unreadable;
- `TOOLKIT_CONFIG_UNAVAILABLE` — info; the toolkit-managed `mise` configuration
  is absent or unreadable;
- `TOOLKIT_CONFIG_OK` — info; comparison A, one or more components match;
- `TOOLKIT_CONFIG_DRIFT` — warn; comparison A, requested value differs from
  the `mise` configuration;
- `TOOLKIT_CONFIG_MISSING` — warn; comparison A, requested key absent from the
  `mise` configuration;
- `TOOLKIT_INSTALLED_NOT_PROBED` — info; `audit` ran without `--probe`;
- `TOOLKIT_PROBE_UNAVAILABLE` — info; a probe dependency (`timeout`, `mise`,
  `openspec`) is missing, or a probe's output could not be parsed;
- `TOOLKIT_PROBE_TIMEOUT` — info; a bounded probe hit its timeout;
- `TOOLKIT_INSTALLED_OK` — info; comparison B, one or more components match a
  fresh probe;
- `TOOLKIT_DRIFT_INSTALLED` — warn; comparison B, the machine now reports a
  different version than the receipt recorded as installed;
- `TOOLKIT_PINS_CURRENT` — info; comparison C, one or more components match
  the current catalog;
- `TOOLKIT_STALE_PIN` — warn; comparison C, the catalog has moved ahead of
  what was requested;
- `TOOLKIT_NOT_COMPARABLE` — info; a component skipped, overridden, or pinned
  to `latest` on either side, named rather than silently dropped.

See `docs/wsl-toolchain-doctor.md` for the full comparison semantics and
`docs/superpowers/specs/2026-09-09-software-catalog-design.md` for the design.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | No `FAIL`; warnings may remain |
| `1` | Policy violations remain |
| `2` | Unsupported environment, invalid arguments, ambiguous configuration, or remediation error |
| `10` | `wsl.conf` changed; restart WSL and rerun `audit` |
| `11` | Persistent PATH source changed; start a new login shell and rerun `audit` |

For agent and harness integration, prefer `--json`.
