# OpenCode 2 routing alignment, Part 3: `observe` on 2.x — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to carry out this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** make `models/routing/opencode/observe/observe` read an OpenCode 2.x
database, logs, config and targets manifest. It keeps 1.x support, picks the
format by what it detects, and fails closed on anything unknown.

**Architecture:** the 970-line analysis in `collect()` stays as it is. A
normalisation layer reads either schema and produces the same internal records
`collect()` consumes today:
- per-session dicts;
- per-message dicts with `texts`, `edits`, `snapshot_edits`, `tasks`, `skills`,
  `answers` and `retries`.

The manifest and config loaders also accept the 2.x formats and normalise them
to the internal `provider/model` + `variant` form.

**Tech stack:** Python 3 standard library (`sqlite3`, `json`); tests are plain
Python scripts run by `models/routing/opencode/eval/tests/routing-observe-test.sh`.

**Spec:** `docs/superpowers/specs/2026-11-21-opencode-v2-routing-alignment-design.md`
(Part 3), plus the measurements below, which supersede that section's
"unmeasured" notes.

## Measured on the live 2.3.0 database and log (2026-11-21, read-only, structure only)

**The 2.x database keeps the 1.x tables, frozen at the migration.**

- `session` holds 1,720 rows, and `message` and `part` likewise stop at the
  migration.
- 2.x writes to `session_v2`, which holds all 1,769 sessions: every migrated one
  plus the new ones.
- Messages go to `session_message`, which holds the migrated history too.
- `session_part` exists but is empty.

**So on a 2.x database `observe` must read only `session_v2` and
`session_message`.** Reading `session` would silently miss every post-migration
session.

**`session_v2` columns** (superset of 1.x `session`): `id`, `parent_id`,
`directory`, `version` (e.g. `2.3.0`, or `1.18.32` for migrated rows), `agent`,
`model`, `time_created`, `time_updated`, plus 2.x-only columns. `model` is NULL
for sessions created on 2.x: the model is per message.

**`session_message`** has the columns `id`, `session_id`, `type`, `seq`,
`time_created`, `time_updated` and `data` (JSON). The `type` values observed are
`assistant`, `user`, `system`, `synthetic`, `idle`, `agent-switched` and
`compaction`. `data` by type:

| `type` | `data` keys |
|---|---|
| `assistant` | `agent`, `model: {id, providerID, variant}`, `content: [...]`, `finish`, `rawFinish`, `cost`, `tokens`, `time: {created, completed, firstToken, streamed}` |
| `user` | `text`, `files`, `time.created` |
| `system`, `synthetic` | `text`, `time.created` |
| `compaction` | `status`, `reason`, `summary`, `metadata`, `time.created` |
| `agent-switched` | `agent`, `previous`, `time.created` |
| `idle` | `outcome`, `time.created` |

**Items in `assistant.content`**, keyed by `type`:

- `text`: `text`, `native`.
- `reasoning`: `text`, `native`, `time`.
- `tool`: `id`, `name`, `executed`, `state: {status, input, metadata, content}`,
  `time`.

**Tool state on 2.x** is the same as the 1.x part state, except the tool name is
`name`, not `tool`:

- `task`: `input.subagent_type`, `input.prompt`; `metadata.sessionId`,
  `metadata.model`. Same as 1.x.
- **New** `subagent`: `input.agent`, `input.prompt`; `metadata.sessionID`.
- `apply_patch`: `metadata.files`. Same as 1.x.
- `skill`: `input.name`.
- `edit` and `write` were not observed in the 2.3.0 sample. Keep the 1.x mapping
  (`input.filePath`, `metadata.exists`).
- `status` values: `completed`, `error`.

**Not observed on 2.x:** a `patch` part (`snapshot_edits`), a `retry` part, and
an `agent` part. They have no counterpart: the 2.x reader produces no
`snapshot_edits` and no `retries`, and reports that in its source coverage.

**The log stays logfmt** in the same single `log/opencode.log`, which spans both
eras.
- There is **no `message="stream"` line on 2.x.** `message="llm runtime selected"`
  has `llm.provider` and `llm.model` but no `session.id`, so per-session stream
  attribution must come from the database (assistant messages), not from the log.
- `message="stream error"` keeps `providerID`, `modelID`, `session.id`, `agent`
  and `error.error`.

**Manifests and config:**
- The 2.x targets manifest is `opencode-v2-routing-targets/1`: `agents.<role>:
  {providerID, model, variant, mode}` and `default_model: {providerID, model}`.
  The toolkit's own `v2/manifests/current-routing-targets.json` has **no**
  `decision_reference`; a private one may have one.
- A 2.x config has `agents.<role>.model: {providerID, model, variant}`, not
  `agent.<role>.model` + `variant`.

## Global constraints

- **Never edit the frozen 1.x files:**
  - `models/routing/opencode/eval/runtime/opencode-v1-adapter/**`;
  - the root `opencode.jsonc`;
  - `profiles/**`;
  - the root `.opencode/**`;
  - `eval/manifests/**`;
  - `eval/records/**`;
  - `eval/fixtures/**`.
- **`observe` stays read-only and private:**
  - database opened `mode=ro`;
  - no session titles, prompts or transcript content in any output;
  - reports keyed by session hash as today.
- **Test data stays synthetic.** Test fixtures are synthetic sqlite databases
  built by the tests, never copies of a real database; the existing `CANARY`
  privacy assertions extend to the 2.x path.
- **1.x behaviour is unchanged.** All existing tests pass without edits, except
  where a test asserts the default `--manifest` path (see Task 1).
- **Schema selection is explicit and fails closed:**
  - `v2` when `session_v2` and `session_message` have the required columns;
  - otherwise `v1` when the current 1.x required set is present;
  - otherwise `unsupported_session_schema`.

  A 2.x database is never read through its frozen 1.x tables.
- `python3` standard library only. Python helpers are written without bytecode
  (`PYTHONDONTWRITEBYTECODE=1` in the test runner, as today).

## Review focus

1. **A 2.x database is read through its frozen 1.x tables.** The result would
   report zero recent activity. Test: a 2.x database fixture that also holds
   stale 1.x tables reports only the `session_v2` rows.
2. **Sessions created on 2.x have `model` NULL.** Routing must come from the
   assistant messages, not the session row. Test: such a session's routing
   audit uses the message model.
3. **The new `subagent` tool and the 1.x-shaped `task` tool both count as Expert
   or task delegations.** Test both.
4. **A 2.x manifest without `decision_reference`** must not crash. The profile
   boundary falls back to the aligned config's mtime, or else needs
   `--profile-effective`, with a clear error. Test both.
5. **Privacy.** Canary text placed in a 2.x user `text`, an assistant `text`
   item and a `tool` input never appears in any output. Test.

---

### Task 1: 2.x targets manifest and 2.x config

**Files:** modify `models/routing/opencode/observe/observe` (`load_manifest`,
`profile_boundary`, the `--manifest` default, the use of `--previous-config`).
Tests go in a new `models/routing/opencode/observe/tests/test_v2_config.py`,
added to `eval/tests/routing-observe-test.sh`.

**Interfaces:**
- `load_manifest(path) -> {role: {"model": "provider/model", "variant": str|None, "mode": str|None}}`.
  It accepts the 1.x format, where `model` is already `provider/model`, and
  `opencode-v2-routing-targets/1`, where `providerID` and `model` are joined
  with `/`. Any other `format` raises `ObserveError("unsupported_manifest_format")`.
- `profile_boundary(manifest, override, config)`:
  - It accepts both config shapes. For 2.x, the config's
    `agents.<role>.model.{providerID, model, variant}` is compared with the
    normalised manifest.
  - Without `decision_reference`: if the config is aligned, return the config
    mtime with `source: aligned_config_mtime`, skipping the date-match rule,
    which needs a record date. Otherwise raise
    `ObserveError("profile_effective_required")`.
- The `--manifest` default stays the 1.x path when `--db` is detected as `v1`,
  and is the toolkit's `v2/manifests/current-routing-targets.json` when it is
  detected as `v2`. Detection uses the same schema function as Task 2. An
  explicit `--manifest` always wins.
- `--previous-config` is read only when it exists. On 2.x, its 1.x `agent`
  rows are ignored unless it is 1.x-shaped (keep today's behaviour).

- [ ] **Step 1: Write the failing tests:**
  - both manifest formats normalise to the same internal rows;
  - an unknown format raises;
  - a 2.x config aligned with a 2.x manifest that has no `decision_reference`
    gives `aligned_config_mtime`;
  - the same manifest with an unaligned config raises
    `profile_effective_required`;
  - `--profile-effective` always wins.
- [ ] **Step 2:** run them and see them fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the new tests and `bash models/routing/opencode/eval/tests/routing-observe-test.sh </dev/null`. All pass.
- [ ] **Step 5:** commit: `feat(observe): read OpenCode 2 targets manifests and configs`.

### Task 2: schema detection and the 2.x session reader

**Files:** modify `models/routing/opencode/observe/observe` (`connect_readonly`,
the session and message reading in `collect()`, and `locate_command`'s session
lookup). Tests go in a new `models/routing/opencode/observe/tests/test_v2_db.py`,
added to `routing-observe-test.sh`.

**Interfaces:**
- `detect_schema(db) -> "v2" | "v1"`, raising `ObserveError("unsupported_session_schema")`.
  The required columns are:
  - **v2:** `session_v2` with `{id, parent_id, directory, version, agent, model, time_created, time_updated}`,
    and `session_message` with `{id, session_id, type, time_created, data}`;
  - **v1:** today's set.
- `read_sessions(db, schema) -> dict` keeps the same keys as today (`id`,
  `parent`, `directory`, `version`, `agent`, `model`, `created`, `updated`).
- `read_messages(db, schema, session_ids) -> dict[sid, list[message]]` returns
  exactly the per-message dict `collect()` builds today from `message` + `part`.
  Read today's code to list every key, and fill the same keys from 2.x:
  - **`assistant`:** `agent`, and provider, model and variant from
    `data.model.{providerID, id, variant}`.
  - **Time:** from the row's `time_created`.
  - **Errors and finish:** map whatever today's code reads from 1.x
    `message.data` (e.g. `error`) from the closest 2.x field (`finish`,
    `rawFinish`). Read the code and document the mapping in a comment. If a 1.x
    signal has no 2.x source, leave it empty, never invented.
  - **`content`, one branch per item `type`:**
    - `text` → `texts`, kept as today: counted and screened, never output;
    - `tool` → the same branch as a 1.x tool part, with `tool = item.name`;
    - `subagent` tool → `tasks` with `{agent: input.agent, child: metadata.sessionID, packet: packet_present(input.prompt)}`;
    - `reasoning` → ignored.
  - **`user`:** `text` → `texts`, as a 1.x user text part.
  - **`system`, `synthetic`, `idle`, `agent-switched`, `compaction`:** ignored for
    message signals. The `system`/`synthetic` text must not count as user text,
    mirroring 1.x's `synthetic`/`ignored` filter.
  - **No `snapshot_edits` and no `retries` on 2.x.** The report's source
    coverage gains `"session_schema": "v1"|"v2"` and, for v2,
    `"unavailable_signals": ["snapshot_edits", "retries"]`.
- **Routing when the session's `model` is NULL** comes from that session's
  assistant messages. Read how `collect()` uses `parse_session_model`, and feed
  it the message model when the session column is NULL.

- [ ] **Step 1: Write the failing tests** with a synthetic 2.x database builder
  (in the style of `test_observe.py`'s `schema()`). It also creates stale 1.x
  tables holding *different* sessions, so the tests fail if the reader looks at
  them (Review focus 1). Cover:
  - Review focus 2, 3 and 5;
  - a `task` delegation and a `subagent` delegation;
  - an `apply_patch` edit;
  - a `skill` call;
  - a session on a `version: "2.3.0"` row with `model` NULL;
  - a migrated `1.18.32` row;
  - `detect_schema` on 1.x, 2.x and an unknown database.
- [ ] **Step 2:** run them and see them fail.
- [ ] **Step 3:** implement, keeping the 1.x path byte-for-byte equivalent.
  Every existing observe test must pass unedited.
- [ ] **Step 4:** run the new tests and `routing-observe-test.sh`. All pass.
- [ ] **Step 5:** commit: `feat(observe): read the OpenCode 2 session tables`.

### Task 3: logs on 2.x

**Files:** modify `parse_log_files` in `models/routing/opencode/observe/observe`.
Add tests to `test_v2_db.py` or to a new `test_v2_log.py`.

**Interfaces:**
- `parse_log_files(log_dir, since, schema)`:
  - `stream error` is parsed exactly as today on both schemas.
  - On `v2`, stream counts no longer come from the log (no `stream` lines; `llm
    runtime selected` carries no `session.id`). Report them as derived from the
    database's assistant messages, with source coverage
    `"stream_source": "database"`.
  - On `v1`, behaviour is unchanged.
  - Process starts: read today's code. Keep whatever it derives from `run=` and
    `role=` if those keys still exist on 2.x lines (they do: `run=...`,
    `role=server|cli`).

- [ ] **Step 1: Write failing tests** with a synthetic logfmt log mixing 1.x-era
  `stream` lines and 2.x-era `llm runtime selected` and `stream error` lines.
  - On a `v2` database, errors are attributed per session and stream counts come
    from the database.
  - On a `v1` database, the result is as before.
- [ ] **Step 2:** run them and see them fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the tests. All pass.
- [ ] **Step 5:** commit: `feat(observe): read OpenCode 2 logs`.

### Task 4: docs, and a read-only run on a live 2.x host

**Files:**
- modify `models/routing/opencode/observe/README.md` (a "OpenCode 2" section:
  schema detection, the measured table mapping, unavailable signals, manifest
  defaults);
- modify `models/routing/opencode/README.md` (one line pointing at it);
- modify `models/routing/opencode/docs/decisions/2026-11-15-opencode-v2-adoption-rfc.md`
  (Follow-ups: mark 2 closed, with a link to this plan's PR context).

- [ ] **Step 1:** write the docs.
- [ ] **Step 2:** run the full gate:
  - `bash models/routing/opencode/eval/run-tests.sh --strict </dev/null`;
  - plain `shellcheck` on any changed `.sh`;
  - the frozen-files diff against `origin/main`, which prints nothing.
- [ ] **Step 3:** run a **manual check, not part of the suite**, on a host
  running 2.x:
  `models/routing/opencode/observe/observe report --format json --manifest <the host's targets manifest>`.
  Record only these in the PR description: counts, source coverage, and the
  detected schema. Never record content, titles or hashes from a real database.
- [ ] **Step 4:** commit: `docs(observe): document OpenCode 2 support`.
