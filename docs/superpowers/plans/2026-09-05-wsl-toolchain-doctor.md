# WSL Toolchain Doctor v0.3.0 Implementation Plan

> **Status:** implemented and regression-tested. This file supersedes the original baseline plan so future maintenance starts from the actual v0.3.0 behavior.

**Goal:** Maintain a Bash-only WSL toolchain doctor that enforces Linux-first PATH/tool binding, safely remediates deterministic persistent PATH sources, and validates mise-owned toolchains without imposing a second version inventory.

**Architecture:** One Bash entrypoint owns WSL policy, PATH provenance/hygiene, candidate classification, mise-aware ownership checks, and conservative remediation. A dependency-free Bash suite drives the public CLI end-to-end with synthetic fixtures and is the executable contract for future changes.

**Tech Stack:** Bash 4.4+, procfs mount data, coreutils-compatible utilities; no Python/.NET/Java/Node/jq runtime dependency in production.

**Spec:** `docs/superpowers/specs/2026-09-05-wsl-toolchain-doctor-design.md`

## Global constraints

- Production script version is `0.3.0`; JSON schema remains `1`.
- WSL interop stays enabled and automatic Windows PATH append stays disabled.
- `/mnt/c` is never hard-coded as the Windows provenance rule.
- Rancher Desktop exception is limited to Linux container tooling.
- `mise` is authoritative for configured watched tools and versions.
- Collision watchlist names are not a required-tool matrix.
- Profile code is never sourced/evaluated.
- PATH auto-fix is limited to the safe grammar in the spec.
- Profile remediation never uses sudo; `wsl.conf` remediation may use sudo when necessary.
- Every persistent write is backed up and uses an atomic replacement where practical.

## Verification matrix

### 1. WSL and interop

- Clean `[interop]` policy passes.
- Missing/default `appendWindowsPath=true` fails.
- Duplicate sections/keys are errors and are never guessed away.
- Non-WSL execution returns `2`.
- `fix` preserves unrelated config, creates backup, and returns `10` when changed.

### 2. PATH provenance and hygiene

- Generic Windows-backed paths fail even with non-default automount roots.
- Rancher Linux-bin path is the sole Windows-backed exception.
- Raw Windows drive syntax and semicolon separators fail before POSIX splitting.
- Literal quotes/variables and control characters fail.
- Repeated backslash escaping warns.
- Current-directory and non-directory entries fail.
- Relative/missing entries warn.
- Textual and canonical duplicates warn and preserve first occurrence semantics.

### 3. Candidate classification

- Enumerate every candidate in PATH, including shadowed entries.
- Follow symlink final targets.
- Detect PE/MZ, ELF, scripts, Windows shebangs, and suspicious wrappers.
- Managed tools cannot use Rancher exception.
- Rancher container tools must be Linux ELF/scripts.

### 4. mise ownership

- Missing mise is informational only.
- Windows-backed/PE mise fails and is not trusted.
- `mise ls --current --no-header` selects only configured watched tools.
- `mise which` must resolve configured primaries.
- Same current/mise target reports `MISE_BINDING_OK`.
- Missing current PATH binding is informational.
- Windows shadowing fails.
- Different Linux binding without activation is informational.
- Different Linux binding with activation fails.

### 5. Persistent PATH remediation

- `fix --path --dry-run` reports safe proposed changes and does not write.
- `fix --path` removes safe duplicates/generic Windows segments, backs up, and returns `11`.
- Missing static entries are preserved by default.
- `--drop-missing` removes eligible missing static entries.
- Dynamic/ambiguous assignments remain unchanged and report `PATH_AUTO_FIX_UNSAFE`.
- `fix --all` combines layers; exit `10` takes precedence over `11`.

### 6. Reporting and packaging

- Human and JSON modes use the same findings.
- JSON escapes subjects/messages and reports toolVersion `0.3.0`.
- `--version` prints exactly `0.3.0`.
- `bash -n` passes for production and test scripts.
- Full regression suite passes.
- Final tarball is extracted into a clean directory and re-verified.
- Directory and tarball file hashes must match for every packaged file.
- No stale product-version references may remain; JSON schema version `1` is unrelated to the product version.
