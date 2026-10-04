# Title provider check — 2026-10-04

Record status: **POST_RUN_DIAGNOSTIC**. Runtime: OpenCode **1.18.32**.
Classification: **LEAK_DISPATCHER_OVERRIDE_ONLY** for the investigated incident.
One authorized Build parent session and one Expert Task child completed.

## B1 — source and historical evidence, no inference

Version-pinned source inspected:

- [session/prompt.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/prompt.ts),
  `ensureTitle`: returns immediately for `session.parentID`; otherwise prefers
  explicit `title` agent model, then small model on the main provider, then the
  main model. `createUserMessage` prefers supplied model over configured agent
  model. A CLI `--model` override alone does **not** override an explicitly
  configured title model.
- [cli/cmd/run.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/cli/cmd/run.ts):
  sends a supplied CLI model to the prompt; requesting a subagent as primary
  falls back to the default primary. Normal configured primary selection uses
  the agent model when no CLI model is supplied.
- [tool/task.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/task.ts):
  creates a child with parentID and an explicit descriptive title; uses the
  subagent's configured model, falling back to the parent model only if absent.
- [session/summary.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/session/summary.ts):
  `SessionSummary.summarize` computes snapshot diffs and updates metadata. It
  does not call an LLM or activate the `summary` agent.
- [agent/agent.ts](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/agent/agent.ts):
  `summary` is a hidden primary agent with its own prompt. Explicit agent
  invocation can activate it; it is not automatically called by the snapshot
  summary path. This probe did not explicitly invoke it or trigger compaction.

The historical `current-routing-capability-2026-10/run-probes.sh` changes
`XDG_CONFIG_HOME` to a temporary config containing only a Build permission deny,
and disables project config. It dispatches `--model openai/gpt-6-astra` without
the configured title agent model. Consequently title resolution falls back to
the main provider. Historical log evidence (already retained in
`../current-routing-capability-2026-10/breakglass-completion/auxiliary-request-evidence.json`):

```text
2026-10-04T07:56:47.875Z session=ses_efa15a6b2ffeRPg9AmTzZhQAJi provider=openai model=gpt-6-astra agent=title small=true
2026-10-04T07:56:48.011Z session=ses_efa15a6b2ffeRPg9AmTzZhQAJi provider=openai model=gpt-6-astra agent=build small=false
```

The later Breakglass experiment-only primary preserved global title routing;
its title used Copilot Luna. Thus the historical leak is attributable to the
combination of dispatcher config isolation and direct model override, not to
`--model` alone. Historical dispatches and conclusions remain as recorded.

## B2 — bounded production-agent path

`run-once.py` checks runtime, active Build/Expert/Title/Summary model resolution,
and OAuth metadata without retaining credentials. It reserves **10 credits** in
a new `title_provider_check` structure in the existing ledger, plus **1 Expert
Task dispatch** in the subscription account. Previous ledger structures remain
semantically unchanged. `started.json` refuses any second invocation. There was
no dispatcher/model/config override and no retry or quota error.

Invocation: `opencode --print-logs --log-level INFO run --agent build --format json`.
The runner requested a disposable cwd, but the CLI's inherited `PWD` selected
the repository directory, as recorded by both session exports. This was the
actual configured production-agent path, with ordinary repository/global
configuration. No agent file-edit tools, commands or other tool calls occurred
in either session. OpenCode snapshots do show `raw.jsonl` diffs: the harness
wrote that file while the runtime snapshotted the real repository, including
its uncommitted ledger reservation. Those diffs are harness output, not agent
edits. The temporary directory was used only for stderr scratch.

Provider stream evidence (`provider-streams.log`, runtime run `9879f9c4`):

| Session | Role | Provider/model | Streams |
|---|---|---|---:|
| Parent `ses_ef99d2383ffe5kmy5YzdllvTtl` | Title | Copilot GPT-6 Luna | 1 |
| Same parent | Build | Copilot GPT-6.1 Sol | 2 |
| Child `ses_ef99d0781ffe8ctrqhFoTL1tRT` | Expert | OpenAI GPT-6 Astra | 1 |
| Parent and child | Summary | no stream observed | 0 |
| Child | Title | no stream observed | 0 |

The child export links to the parent. The sole tool call is a completed Expert
Task carrying all seven decision-packet fields; the parent final response is
`PROVIDER_PROBE_DONE`. Session exports retain message-level model/provider,
tokens and costs. Runtime `stream` lines identify LLM invocations, not an
independent HTTP-level count of SDK retries. The retained streams/messages
show no additional session-level attempts; full runtime stderr was disposable,
so SDK/HTTP retry events cannot be audited from this record.
The title source allows internal retries (2); the outer harness did not retry.

## B3 — result and accounting boundary

**LEAK_DISPATCHER_OVERRIDE_ONLY**: no auxiliary OpenAI invocation occurred on
the sampled configured Build→Expert path; the historical isolated direct-model
dispatcher explains the earlier OpenAI title. This is a bounded diagnostic,
not a universal proof over all plugins, primary agents or future runtimes.

- Copilot message costs: `0.047031 + 0.0027672 = 0.0497982` runtime units;
  multiplied by 100 = **4.97982 observed credits**.
- **1 new OpenAI subscription call**, meaning one Expert Task dispatch;
  one corresponding Expert LLM stream observed. OpenAI runtime cost 0 is not
  free-billing evidence and is not converted to credits.
- **1 auxiliary Copilot title stream**, with cost and tokens unavailable.
  Consequently 4.97982 is observed primary spend, not total provider spend.
- The watchdog checks completed parent steps and stops at 10 observed credits;
  it cannot prevent in-flight overshoot and cannot meter title cost. The
  reserved ceiling is an admission/observed-spend boundary, not a proved hard
  cap on total provider consumption. No additional inference was used to close
  that accounting gap.

The one-Task allowance was reserved before dispatch and satisfied in this run.
The prompt asks for exactly one Task; the subscription watchdog would detect a
second Expert stream only after it starts, so it is not a pre-dispatch hard
enforcement mechanism. `openai_provider_requests` in outcome/ledger counts
Expert LLM stream lines, not independently attested HTTP requests.

The new structure is deliberately separate from historical top-level entries.
Existing `ledger_spent`/`ledger_admit` helpers do not include it: they still see
2.26529 credits, while combined observed primary spend is **7.24511 credits**.
Future admission must include the appended structure explicitly; this record
does not claim the legacy ledger helper automatically accounts for it.

The harness README now requires experiment-only primary agents for future
isolated capability probes, with active metadata routing preserved and verified.
No routing fix or global config change is warranted by this record.

Independent reviewer: approved with evidence-boundary follow-ups. Added the
aggregate-account limitation, stream-vs-HTTP and watchdog boundaries, snapshot
side-effect explanation, and an offline test environment that denies dispatch
even if the started marker is missing. Deferred minors: generalized CLI guards
and reuse hardening (the retained run is single-use), auxiliary schema alignment,
and reduced encrypted-reasoning metadata. No additional model probe was run.

## Prepared pull request

Title: `docs: distinguish dispatcher title fallback from production routing`

Summary:
- Diagnose version-pinned title/Task/summary resolution and historical isolated
  direct-model fallback.
- Retain one configured Build→Expert session, provider evidence and appended
  budget accounting; classify LEAK_DISPATCHER_OVERRIDE_ONLY.
- Add an append-only decision addendum and guidance for future capability probes.

Validation: provider streams and both session exports cross-checked offline;
observed Copilot 4.97982 credits plus one OpenAI subscription call, with one
unmetered auxiliary Copilot title stream. No routing/global config edits.
