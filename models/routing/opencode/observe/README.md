# OpenCode Routing Observation

`observe` is a post-hoc, read-only observer for the current OpenCode routing
profile. It reads local session metadata and runtime logs without starting
OpenCode, loading plugins, registering hooks, changing routing, or making model
calls.

The tool is intentionally local. Session reports and review decisions stay
outside this public repository under
`${XDG_STATE_HOME:-~/.local/state}/agentic-dev-toolkit/routing-observe/` by
default.

## Weekly review in about ten minutes

Run the report from the routing bundle directory:

```bash
./observe/observe report --since 2026-09-20
```

The output first shows source coverage, session classes, signal counts and Build
gate checkpoint progress. It then lists pending items as a keyed session hash,
signal and reason code. It never prints session titles or transcript content.

For each pending item:

```bash
./observe/observe locate SESSION_HASH
opencode export SESSION_ID --sanitize > /tmp/opencode-review.json
./observe/observe review confirm SESSION_HASH SIGNAL REASON --note "short local note"
# or
./observe/observe review dismiss SESSION_HASH SIGNAL REASON --note "short local note"
```

`locate` prints the real ID only to the current terminal. It never stores the
mapping. The sanitized export is a manual review aid and remains outside the
repository. Remove it when the review is complete. Use `--rollback` only when
confirming a `rework` signal that required a rollback:

```bash
./observe/observe review confirm SESSION_HASH rework same_file_modified_after_user_turn \
  --rollback --note "rollback required"
```

Run the report again. Trigger thresholds use only confirmed signals in the
selected window:

- any production routing mismatch;
- provider errors in two distinct production sessions for the same provider;
- two skipped gates;
- one confirmed rework marked `--rollback`.

One skipped gate remains visible as progress toward the threshold and is not a
trigger. The checkpoint tracks Build sessions with an observed brainstorming
gate against the target range of 15 to 20.

## Signals

| Signal | Meaning |
|---|---|
| `routing` | A production request or session differs from `current-routing-targets.json`. Eval dispatchers and sessions before the current profile are classified separately. |
| `provider_error` | A non-user-abort API or stream error, reduced to `rate_limit`, `timeout`, `server`, or `other`. |
| `escalation` | Counts Expert and Reviewer Task calls and Breakglass use. Breakglass appearing as a child is reviewable. |
| `gate` | A Build tree invoked `brainstorming` and then modified files before an observed approval. |
| `scope` | An existing shared test/setup file changed, or files fall outside one identifiable active OpenSpec change. This is a flag only. |
| `rework` | A user turn occurs between two modifications to the same file. This is a flag only unless review confirms rollback was required. |

Reports also include provider/model/variant request counters. Title requests
come from logs and therefore have no variant. OpenCode 1.18.32 automatic
snapshot summaries do not invoke the Summary agent; explicit Summary or
Compaction requests remain observable through session messages.

## Storage discovery

Discovery was performed against OpenCode **1.18.32**:

- `opencode session list --format json` lists sessions but is not used by the
  observer.
- `opencode export SESSION_ID` exports complete session data but is unsuitable
  for bulk privacy-preserving collection.
- `${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db` is the SQLite source.
  The observer opens it with `mode=ro` and reads `session`, `message`, and
  `part`. OpenCode 1.18.32 stores `session.model` as JSON with `providerID`,
  `id`, and `variant`. `session.parent_id` and Task metadata connect children.
- `${XDG_DATA_HOME:-~/.local/share}/opencode/log/*.log` provides `stream` and
  `stream error` lines, including Title requests.

Use `--db`, `--log-dir`, `--eval-records`, `--manifest`, or `--state-dir` for
isolated fixtures and non-default XDG layouts. A state directory inside any Git
worktree is refused.

## Privacy properties

The serialized schema is an allowlist: keyed session hash, timestamp, agent,
provider, model, variant, counters, flags, reason codes, review status and
worktree-relative paths. Paths outside the session worktree become
`<outside-worktree>`.

The observer does not serialize prompts, responses, titles, reasoning, diffs,
tool input/output, error text or file content. Text used for classification
exists only in memory. A synthetic integration test plants a canary across all
of these fields and rejects the canary in stdout, stderr and every state file.

The keyed hash is pseudonymous, not anonymous. Anyone with access to the local
key and database can resolve it. State directory and key modes are `0700` and
`0600` respectively.

## Heuristic limits

- Storage cannot prove whether a root-model difference came from config drift
  or an intentional TUI selection; review is mandatory.
- Eval dispatcher recognition uses retained record IDs and experiment-agent or
  temporary-worktree evidence. Unknown external harnesses may need dismissal.
- Log rotation limits Title and stream-error coverage. Reports disclose how
  many log files were read.
- A retry is inferred from a later stream for the same session and agent; it is
  not an HTTP-level SDK retry audit.
- Approval detection recognizes explicit English and Italian confirmation plus
  structured `question` answers. Ambiguous wording can produce a false flag.
- Snapshot `patch` parts and structured edit tools cover normal file changes.
  Commands that mutate files without a persisted snapshot may be missed.
- OpenSpec scope is evaluated only when one active change name appears in user
  text. Declared paths are extracted from backtick-delimited artifact paths.
- Rework means overlapping paths across a user turn. It does not prove the
  first implementation was wrong.
- The default profile boundary is the PR #65 merge timestamp, not a proven
  machine activation timestamp. Override it with `--profile-effective` when
  local activation evidence gives a more precise boundary.

## Tests

```bash
bash ../eval/tests/routing-observe-test.sh
bash ../eval/run-tests.sh --strict
```

The test covers aligned routing, mismatch, dispatcher classification, provider
error and retry, respected and skipped gates, shared test setup, active OpenSpec
scope, rework, parent/child sessions, review thresholds, locate, read-only
database access, state placement and canary non-disclosure. It also verifies
parity with the six retained `classify_gate` results.
