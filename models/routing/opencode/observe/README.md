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
./observe/observe report
```

The output first shows source coverage, session classes, signal counts and Build
gate checkpoint progress. It then lists pending items as a keyed session hash,
signal and reason code. It never prints session titles or transcript content.

Every counter belongs to a `production`, `eval_dispatcher`, or `pre_profile`
section. Pre-profile sessions are counted only: their requests are not compared
with the current manifest. Top-level JSON counter fields are production-only
aliases for existing consumers. Only production contributes to triggers,
checkpoint progress and the pending review list; dispatcher findings are
informational and never inherit human review decisions.

The default `--since` uses the mtime of the local active configuration when all
manifest agent models/variants match and that mtime falls on the alignment
record date. `profile_boundary.source` is then `aligned_config_mtime`. This is
evidence of configuration writing, not proof of a running session's reload.
If it cannot be validated, the alignment record date is a day-precision proxy
(UTC midnight), disclosed as `alignment_record_date`. `--activation-config`
selects the local file (an empty value disables this evidence), and
`--profile-effective` supplies an explicit timestamp. Use an earlier `--since` to count
historical populations; historical activity in a resumed session is excluded
from current-profile counters.

Routing audit metadata uses the actual message/stream timestamp and contains
expected/observed models and an activation class. `PRE_ACTIVATION` requests
precede configuration writing; `SESSION_SPANNING_ACTIVATION` requests follow it
in a requesting session created earlier; `POST_ACTIVATION` requests originate
in a new requesting session. Only confirmed post-activation routing flags can
trigger action. The other two classes are informational. An explicit earlier
window exposes same-day pre-activation evidence for audit, without adding it to
current-profile request counters. Root-model metadata uses session creation
time as a proxy; it is not an independently timestamped request.

Production counters are also split by normalized working repository: `toolkit`
by Git remote (repository name as fallback), `product` for other Git roots,
`workspace` for existing cwd directories with no Git root, and `unknown` for
missing directories. No complete path is serialized or inferred from edited files.
The Build gate checkpoint includes **product only**, excluding toolkit,
workspace and unknown work. `expert_escalations` has one row per distinct observed Expert
Task child: parent hash, repository class, and decision-packet boolean only.
Packet presence requires all seven structured headings and does not assess
their content, correctness, or whether escalation was justified.

`STALE_PROCESS` denotes a session created after configuration writing whose
runtime log run was already loading before that boundary. Run-first-seen is a
logged startup bound, not an OS process creation timestamp. Log rotation can
remove this evidence; absence is not proof of a fresh process. These flags are
informational and never automatically trigger routing rollback.

`MANUAL_OVERRIDE` is a review candidate when assistant messages for the same
agent change models mid-session to neither the current manifest model nor the
previous model read from `--previous-config` (default: the local 20261003 backup).
It is not proof of human action: plugins or other runtime paths can also select
a model. Known stale processes take precedence; the candidate requires review
before any action. If previous configuration is unavailable, that evidence gap
limits the classification.

Repository identity prefers Git remote URLs (including linked-worktree common
config): `github.com/Prev-I/agentic-dev-toolkit` is toolkit. Directory naming is
only a fallback when remotes are absent. Git config is read without executing
Git, includes, commands, or URLs. Gate, scope and rework episodes record the
observed message model/variant; the product Build checkpoint counts only gate
episodes observed on the current Build model. Agent names alone do not qualify.

The alignment check reports a non-blocking `WARN STALE_PROCESS` for running
Linux OpenCode processes started before the latest configuration mtime. It
reads `/proc` process names/start ticks, not command arguments, and never stops
or reloads a process. File-alignment status and exit code remain unchanged.

### Compaction variant diagnosis — OpenCode 1.18.32

The 2026-10-04 19:54:11.861 UTC compaction inherited a Plan parent message using
`claude-opus-5.5` / `xhigh`. The selected compaction model was configured
`claude-sonnet-5.5`, but the recorded variant was `xhigh`, not configured `low`.
Version-pinned sources:

- [compaction.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/compaction.ts)
  selects `agent.model` but assigns `variant: userMessage.model.variant` and
  passes the parent user message to the processor.
- [llm/request.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/llm/request.ts)
  selects `input.model.variants[input.user.model.variant]`, rather than the
  configured compaction agent variant. Missing model variants resolve to no
  variant options; stored `xhigh` is not proof the provider applied that effort.

Classification: **OpenCode variant inheritance behavior**, not config drift.
Proposed upstream correction (not applied): resolve the compaction variant from
the compaction agent, validate it against the selected model, and pass a copied
user request with that resolved variant to both metadata and LLM preparation.
Add a runtime test with parent `xhigh` and compaction `low`; both stored metadata
and prepared options must use `low`. No runtime/config/plugin changes are made
by this observer.

This parent-linked variant-only discrepancy is `KNOWN_DEVIATION` for version
1.18.32, referencing the append-only
[alignment addendum](../docs/decisions/2026-10-03-current-routing-alignment.md#addendum--2026-10-04-compaction-variant-inheritance).
It appears only as informational metadata and never requires repeated review
or triggers rollback. Model mismatches and unverified parent inheritance remain
outside this exemption. [UPSTREAM-ISSUE.md](UPSTREAM-ISSUE.md) is an English
issue draft without session content; it has not been submitted.

### Local activation evidence inspected on 2026-10-04

`opencode.jsonc.bak-20261003` preserves a 2026-09-29 modification time; its
2026-10-03 19:09:38 UTC creation time proves backup creation, not activation.
The active `opencode.jsonc` has matching birth/mtime/ctime at approximately
**2026-10-03 19:36:38.291 UTC**, twenty seconds after alignment commit `ff7a09f`.
The observer validates the live routing against the target manifest before
using that mtime. It does not read or modify credentials or global settings.

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

Explicit authorization to implement in the preceding human prompt yields
`PRE_AUTHORIZED`, not `NON_ADHERENT`, and produces no skipped-gate flag.
Negated authorization is rejected. Each brainstorming episode ends when the
next one starts. Task counts use distinct child session IDs per agent;
continuations of an existing child and bare agent mentions do not inflate them.

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
- The default profile boundary is derived from the alignment record, not an
  attested machine activation time. Override it with `--profile-effective` when
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
