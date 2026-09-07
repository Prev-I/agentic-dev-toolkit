# User-Selected Routing: Sol Build, Opus Review, Astra Expert

## Decision

The user explicitly approved updating the managed bundle and the active global
configuration on 2026-09-07:

| Role | Model | Variant |
|---|---|---|
| Build | `github-copilot/gpt-5.6-sol` | `high` |
| Reviewer | `github-copilot/claude-opus-5` | `high` |
| Expert | `openai/gpt-6-astra` | `xhigh` |

The default model follows Build. All other roles, variants, permissions, prompts,
and non-routing settings remain unchanged. In particular, Plan remains Copilot
Opus 5/max and Breakglass remains direct OpenAI Sol/max, human-only and not
Task-routable. Expert uses the existing OpenAI subscription authentication;
no credentials or provider settings are changed.

## Rationale And Evidence Boundary

This is a user preference, not a benchmark-driven promotion. Prior KEEP_OPUS
decisions, the restored profile, Phase-R targets, installed-profile record, and
all historical benchmark evidence remain historical and unchanged. The current
source is `opencode.jsonc`, with `eval/manifests/current-routing-targets.json` as
its verification contract. No duplicate current profile snapshot is needed.

Build and General use GPT models, while Reviewer uses Claude. Plan and Reviewer
still share Opus. Expert remains provider-separated from Build, but Astra and
Sol belong to the broader GPT family; this is not proof of independent reasoning.

`opencode models openai --verbose` exposed `openai/gpt-6-astra` and the `xhigh`
variant before approval. Catalog discovery and configuration resolution do not
prove successful inference or role fitness. The user approved no new paid
benchmark, so activation is configuration-verified only; direct OpenAI Astra
inference and its Expert-role quality remain untested by this change.

## Verification And Activation

The current-routing test compares the full parsed source to the historical
profile with only the four approved model substitutions (including default).
This pins every permission and unaffected role. Historical invariant tests use
the frozen restored profile; activation tests and the ordinary alignment entry
point use the current source and targets.

Activation uses the backup-and-merge helper, preserving unrelated
global configuration. The installed routing policy prose is updated separately
with a local backup. Fresh-process effective routing is checked from neutral and
project directories without model calls. Current activation evidence is recorded
separately under `eval/records/routing-selection-2026-09-07/`; the Phase-R installed
manifest remains an immutable record of that earlier installation.

Activation completed at 22:16 +02:00. `activation.json` records the source digest,
local backup location, sanitized verification summary, and configuration hashes.
All eleven roles passed effective resolution from neutral and toolkit project
directories, with no project overrides; the three changed roles also resolved
correctly in the invoking project. Alignment is ALIGNED. A full parsed comparison
against the backup confirmed only the three role models and default changed.
All four repository suites passed (doctor: 148 passed, 0 failed).

The helper now uses neutral routing labels rather than labelling later installs
as Phase R, and records the source-file SHA-256. Git HEAD is context only, not
complete provenance for an uncommitted source. Historical experiment scope tests
are pinned to their result commits, not a diff of future worktrees against main.

OpenCode must be restarted after activation. Existing sessions retain their
already-loaded configuration and may also have explicit model selections.
