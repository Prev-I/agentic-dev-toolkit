# Routing Observation Design

Status: **APPROVED** on 2026-10-04.

## Purpose

`observe` is a post-hoc, read-only observer for the OpenCode routing profile
accepted on 2026-10-03 and closed on 2026-10-04. It reads local session
evidence without starting OpenCode, changing its configuration, installing a
plugin, registering a hook, or calling a model.

## Privacy boundary

The observer may read transcript text in memory only to classify approval,
correction, provider-error, and OpenSpec-path signals. Its serialized output is
an allowlisted metadata projection: keyed session hash, timestamps, agent,
provider, model, variant, counters, reason codes, flags, and normalized paths
relative to the session worktree. It never serializes titles, prompts,
responses, reasoning, diffs, tool input/output, error text, or file content.

State defaults to
`${XDG_STATE_HOME:-~/.local/state}/agentic-dev-toolkit/routing-observe/` and is
refused inside a Git worktree. A local HMAC key keeps hashes stable without
making session identifiers public. `observe locate` recomputes hashes from the
read-only database and prints a matching raw ID only to the terminal; it never
stores the mapping.

## Sources

OpenCode 1.18.32 stores sessions in
`${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db`. The observer opens the
SQLite database with `mode=ro` and reads `session`, `message`, and `part`.
`session.parent_id` and Task metadata link children to their parents. Message
metadata carries agent, provider, model, and usually variant. Structured part
metadata carries skill names, Task subagent types, and edited file paths.

OpenCode logs under the same data root provide `stream` and `stream error`
events, including Title requests. Logs do not provide variants. In 1.18.32 the
automatic snapshot summary does not invoke the Summary agent; explicit Summary
or Compaction messages remain observable in the database. The observer reports
source coverage and fails closed when required schema is absent.

## Session classes

- `pre_profile`: before the 2026-10-03 profile merge timestamp; never a current
  routing mismatch.
- `eval_dispatcher`: temporary-directory or experiment-agent sessions. These
  include the `LEAK_DISPATCHER_OVERRIDE_ONLY` class retained by PR #68 and do
  not count as production mismatches.
- `production`: all remaining session trees.

Every root is analyzed together with Task children. A root model difference is
reviewable because storage cannot distinguish config drift from an intentional
TUI model selection. Title and child differences are stronger evidence but
still require human confirmation before triggering action.

## Signals

- `routing`: provider/model/variant requests compared with
  `eval/manifests/current-routing-targets.json`.
- `provider_error`: API and stream errors classified as `rate_limit`,
  `timeout`, `server`, or `other`; user aborts are excluded. A retry is inferred
  only from a later stream for the same session and agent.
- `escalation`: Expert and Reviewer Task calls and Breakglass use. Breakglass as
  a child is reviewable.
- `gate`: Build trees invoking `brainstorming` are classified
  `ADHERENT`, `NON_ADHERENT`, or `AMBIGUOUS` according to whether repository
  edits precede an approval. Tests preserve parity with the six retained
  `classify_gate` results without editing frozen evidence.
- `scope`: updates/deletes to existing shared test or setup files, and files
  outside one identifiable active OpenSpec change, are reviewable flags only.
- `rework`: a user turn between two edit sets that overlap by path is a flag
  only. Correction vocabulary raises review priority but never triggers by
  itself.

## Review and triggers

`observe review confirm|dismiss` appends a decision outside the repository.
The latest decision for a session/signal/reason tuple wins. `--rollback` is
valid only for confirmed rework.

Only confirmed production evidence in the report window triggers action:

- any routing mismatch;
- provider errors in at least two distinct sessions for the same provider;
- at least two skipped gates;
- any confirmed rework requiring rollback.

A single skipped gate remains visible as progress toward the two-event trigger.
The Build checkpoint reports observed gate-bearing sessions against the target
range of 15 to 20.
