# OpenCode V1 Activation Preflight - 2026-09-03

## Outcome

The user-global OpenCode configuration ambiguity is resolved. The canonical
activation target is `~/.config/opencode/opencode.jsonc`, the approved selector
reports `READY`, and Phase R has not started.

## Runtime environment

- OpenCode version: `1.18.27`
- OpenCode config root: `~/.config/opencode/`
- Capture timestamp: `2026-09-03T19:51:58+02:00`
- Baseline command: `opencode debug config` from `/tmp/opencode`
- `OPENCODE_CONFIG`: unset
- `OPENCODE_CONFIG_CONTENT`: unset
- `OPENCODE_CONFIG_DIR`: unset

## Initial state

| File | Present | Size | Mtime | SHA-256 |
|---|---|---:|---|---|
| `~/.config/opencode/opencode.json` | yes | 139 bytes | `2026-08-12T23:48:07+02:00` | `b4d49088460d6eab43c7146d1dbaf6df82d06a86ec80acdf71405e184cf73e26` |
| `~/.config/opencode/opencode.jsonc` | yes | 2060 bytes | `2026-09-03T10:59:16+02:00` | `3a3b7517ccd57ece7f114daf7a50cdbdc103266247f72ae5d142c3578f0e7aaf` |

Relationship classification: `CONFLICTING_KEYS`.

The only conflicting explicit key path was `plugin`. The baseline resolved
configuration proved that the effective plugin value was the JSON value; JSONC
had no plugin entry. JSON supplied no additional raw top-level keys beyond that
plugin entry. The JSONC file supplied the pre-Phase-R routing and permission
configuration. No sensitive values were copied into this record.

## Backup and canonicalization

- Local backup directory:
  `~/.config/opencode/backups/pre-phase-r-20260903T190513+0200/`
- Both original files and their hashes are retained there.
- Canonical active file: `~/.config/opencode/opencode.jsonc`
- Retired active filename: `~/.config/opencode/opencode.json` no longer exists.
- Canonical JSONC SHA-256:
  `b996dc7d596b164337aca23cf60e00d4c5dcc5e4852d7475bcab3a8f1cc15e32`

The canonical file preserves the existing JSONC text/comments where practical
and adds the baseline-effective plugin setting from JSON. No routing value was
changed.

## Effective configuration comparison

- Baseline normalized resolved-config SHA-256:
  `d53f928722603295d8a9c6c6754dbf1db5e754c819894efef1e686e69b445e38`
- Post-normalization normalized resolved-config SHA-256:
  `d53f928722603295d8a9c6c6754dbf1db5e754c819894efef1e686e69b445e38`
- Semantic preservation: `PASS`

Complete resolved configuration output remains local and uncommitted.

## Override and selector status

- Environment override status: `PASS`; no top-level OpenCode config/content/dir
  override was active.
- Project routing-override status: `PASS`; one ancestor project config was
  present, but it contained no routing-owned top-level keys.
- Activation selector: `READY`
- Selected path: `~/.config/opencode/opencode.jsonc`

## Security and scope

No global configuration contents, resolved output, credentials, tokens, MCP
headers, or backup contents are committed. Repository production routing and
production agent definitions are unchanged. The user-global routing remains the
pre-Phase-R profile. No model calls were made. Phase R, Phase 3, and Phase 4 were
not started.
