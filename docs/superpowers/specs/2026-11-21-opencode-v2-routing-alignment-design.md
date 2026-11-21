# OpenCode 2 routing alignment — design

Date: 2026-11-21. Status: draft for approval.

## Intent

The toolkit now installs OpenCode 2.x (`opencode=2.3.0`). Its routing bundle
under `models/routing/opencode/` is still written for 1.x:

- the tracked config and profiles are V1-shaped;
- the tools that apply and verify a profile depend on V1 keys and on
  `opencode debug agent`;
- the evaluation harness drives OpenCode the 1.x way.

A V1-shaped config keeps working on 2.x only because 2.x translates it in
memory. That translation drops some settings silently, and the 1.x tools are
wrong on 2.x or unsafe there.

This work aligns the whole bundle with OpenCode 2:

1. config, profiles and the operational routing tools;
2. per-role model screening, so newer models can be evaluated on 2.x;
3. the `observe` tool.

It closes follow-ups 1, 2 and 5 of
`models/routing/opencode/docs/decisions/2026-11-15-opencode-v2-adoption-rfc.md`.

## Goals

- Every config and profile the toolkit ships is in OpenCode 2's native shape.
  Nothing relies on in-memory V1 translation.
- An operator can, on 2.x:
  - apply a routing profile;
  - check the installed file for drift;
  - verify what the running server actually resolves;
  - probe Breakglass.

  All four are 2.x tools.
- The toolkit can convert an existing V1 config to V2 once, with a check that
  the result means what 2.x's own translation means.
- The installer's Superpowers configuration writes V2.
- A reusable runner can screen new models per role on 2.x, as the latest
  evaluations did. Its results start a fresh baseline.
- `observe` reads a 2.x database.

## Non-goals

- Comparability with the 1.x evaluation records. New results are a new
  baseline; nothing ranks a 2.x score against a 1.x one.
- Changing which models the tracked profiles assign to roles. Model choice is a
  separate decision.
- Supporting 1.x in any operational path. The toolkit is 2.x-only, as its
  installer already is.
- Organisation-specific provider declarations. A consumer that rewrites profiles
  for a private gateway keeps doing so outside this repository. It only needs
  the documented V2 profile format.

## Anti-goals

These would make the work a failure even if it ran.

- **A file mixing V1 and V2 shapes.** Upstream warns that mixed shapes within a
  section silently lose settings (anomalyco/opencode#56816). Every writer here
  refuses a V1-shaped target instead of adding V2 keys beside V1 ones.
- **Any tool or harness run touching a user's real OpenCode data or config**
  without being asked to. A 2.x client without `--server` starts or reuses a
  server on the real database.
- **Editing the 1.x history.** The V1 adapter, the 1.x evaluation records, and
  any fixture or manifest a frozen record or freeze manifest depends on stay
  byte-identical. The freeze manifests must still verify.
- **Routing that passes without being true.** An undeclared variant is ignored
  silently. A verifier that compares only model names would pass a role running
  on the wrong variant.
- **Hard-coded model identifiers in scripts.** Models come from a profile or an
  argument.

## Constraints

- Company-neutral and portable, like the rest of the repository's core (see
  `AGENTS.md`, Scope).
- Repository conventions apply to every script:
  - Bash with `set -Eeuo pipefail`;
  - `run` / `run_sudo` for every mutation in the installer;
  - a `SCRIPT_VERSION` bump in the same commit as a behaviour change;
  - shellcheck clean;
  - LF line endings;
  - tests run by `bash models/routing/opencode/eval/run-tests.sh --strict`
    and the other suites listed in `AGENTS.md`.
- Integration is by pull request (`.repository-policy.yaml`: github-flow).
- Only measured 2.x behaviour is relied on. Where this design depends on
  something unmeasured, it says so and the builder measures it first.

### The V2 shape, as measured

The reference is what a 2.3.0 server reports for a V1 config, through
`GET /api/config` (the `info` of the `document` layer). That is the shape the
tracked files must take:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": { "providerID": "<p>", "model": "<m>" },
  "update": "disable",                                  // V1 "autoupdate": false
  "permissions": [                                      // ordered; the last match wins
    { "action": "websearch", "resource": "*", "effect": "allow" },
    { "action": "subagent", "resource": "*", "effect": "allow" },
    { "action": "subagent", "resource": "breakglass", "effect": "deny" }
  ],
  "policies": [                                         // V1 "disabled_providers"
    { "action": "provider.use", "resource": "<provider>", "effect": "deny" }
  ],
  "plugins": [ "superpowers@git+https://github.com/obra/superpowers.git#<tag>" ],
  "providers": {
    "<p>": {
      "name": "...",
      "package": "...",
      "settings": { "baseURL": "..." },
      "models": {
        "<m>": {
          "name": "...",
          "limit": { "context": 0, "output": 0 },
          "variants": [ { "id": "high", "settings": { "reasoningEffort": "high" } } ]
        }
      }
    }
  },
  "agents": {
    "build": {
      "mode": "primary",
      "model": { "providerID": "<p>", "model": "<m>", "variant": "high" },
      "permissions": [ /* same grammar as above */ ]
    },
    "expert": {
      "mode": "subagent",
      "hidden": true,
      "steps": 0,
      "system": "prompt text (V1 `prompt`)",
      "model": { "providerID": "<p>", "model": "<m>", "variant": "xhigh" },
      "permissions": [ ]
    }
  }
}
```

Facts measured on 2.3.0 (RFC; phase reports kept by the operator):

- V1 `task` permissions become `subagent`.
- An agent's `temperature` becomes `request.body.temperature`, and **is not
  sent**.
- A provider's `blacklist` is dropped.
- Undeclared models are not discovered (2.x does not call `/v1/models`).
- `GET /api/agent` **without** `directory` lists only the built-in agents.
  `GET /api/agent/<id>` and `GET /api/agent?directory=<dir>` list every agent
  with its resolved model and variant.
- `opencode run --server <url> --agent <role> --format json` accepts subagents
  and hidden agents. It emits:
  - `step_start`;
  - `tool_use` (with `part.tool`, `part.state`);
  - `step_finish` (with `part.cost`, `part.tokens`, `part.reason`);
  - `text` (with `part.text`).

  Each event carries `sessionID`.
- `GET /api/session/<id>/message` returns each assistant message with `agent`
  and `model: {id, providerID, variant}`.
- `GET /api/session` is paginated:
  - default 50;
  - `limit` honoured;
  - `cursor.next` passed back as `cursor=`.

Measured on 2.3.0 on 2026-11-21, in sandboxes with only a gateway credential:

- **Native V2 agents work.** These are not a translation artefact:
  - a new agent declared only as an `agents` row resolves with its model,
    variant, mode and permissions;
  - so does a `build` override;
  - **the row's prompt key is `system`.** V1 `prompt` is translated to it;
    `prompt` in a V2 file is dropped.
- **Markdown agents work natively** in `<config>/agents/*.md`:
  - V2 frontmatter is supported: `model: {providerID, model, variant}` and a
    `permissions:` list of `{action, resource, effect}`;
  - a markdown-only agent resolves, and a config row plus markdown merge;
  - the markdown body becomes `system`;
  - V1 frontmatter is still translated.
- **A top-level `permissions` entry applies to every agent's effective
  permissions.** `subagent <name> deny` appears on each agent, built-ins
  included.
- **Agents load lazily, per location.** The first request for a directory
  starts loading and returns `AgentNotFoundError`. About 1 s later, every agent
  resolves. A server left idle has loaded nothing. Any check against a freshly
  started server must poll `GET /api/agent/<id>?directory=<dir>` until the agent
  resolves, with a bound, before judging.
- **`GET /api/model`** lists every model with its `variants`, built-in providers
  included (`openai/gpt-6.2-astra`: `low`–`max`). `GET /api/provider/<id>`
  does not list models.
- **A sandbox is not fully isolated by `HOME` and `XDG_*`.**
  - The server also loads the real user's `~/.opencode` as a config directory
    layer: it is resolved from the account, not from `$HOME`.
  - It also loads the config of the working directory it starts in.

  `GET /api/config` lists every layer.
- A client run as `opencode --server <url> run …` with sandboxed `XDG_*` wrote
  nothing outside the sandbox. A one-call tool-using probe cost 0.0008 and was
  served by the intended agent, model and variant.

## Approaches considered (for applying routing)

- **A. An overlay, with V2 keys.** *Chosen by the operator.* The profile owns
  only the routing keys; activation merges them into the user's V2 config;
  everything else stays the user's.
  - *For:* it keeps today's ownership split and workflow, and a private profile
    generator keeps its role.
  - *Against:* it still merges into a file the user edits, and comments are lost
    on each activation, as today.
- **B. Routing only in agent markdown files.**
  - *For:* no merge at all.
  - *Against:* it depends on unmeasured behaviour — whether `.md` agents can
    override the built-in agents and the default model. Rejected.
- **C. Generate the whole file** from the profile plus a user-owned base.
  - *For:* the result is fully determined.
  - *Against:* the user stops editing the live file, the installer must write to
    the base, and hand edits are lost. Rejected.

## Decisions

### Part 1 — config, profiles, operational tools

**Layout.** *(Builder-check call)*

The V2 bundle lives in its own directory, `models/routing/opencode/v2/`:

| File | Role |
|---|---|
| `v2/opencode.jsonc` | **The single V2 routing authority.** There is no second V2 profile file. It is the documented profile format a private generator targets. |
| `v2/.opencode/agents/{reviewer,expert,scout}.md` | V2 agent markdown |
| `v2/.opencode/model-routing.md` | the semantic routing layer |
| `v2/manifests/current-routing-targets.json` | names `providerID`, `model` and `variant` per role |

The V1 files stay exactly where they are, as history:

- the root `opencode.jsonc`;
- `profiles/`;
- the root `.opencode/`, whose `reviewer.md` a freeze manifest pins by digest;
- `eval/manifests/`.

Because those files do not move or change, the V1 tests that load them keep
passing without being edited.

New tools live in `models/routing/opencode/eval/runtime/opencode-v2-adapter/`.
`opencode-v1-adapter/` is not edited.

`eval/check-alignment.sh`, the README's no-argument entry point, switches to the
V2 checker and the V2 bundle. If a V1 test drives that entry point, the test is
repointed at the V1 adapter's own `check-alignment.sh`. That is the only V1 test
edit allowed.

The routing README states V2 as current and V1 as history, with the paths of
both.

**Agent markdown, V2.** *(Builder-check call)*

- All three agent files and `model-routing.md` get V2 copies under `v2/.opencode/`.
  Their frontmatter is V2-native, as measured: `description`, `mode`, and a
  `permissions:` list. There is no V1-shaped block anywhere in the V2 bundle.
- The markdown never carries `model`. Model and variant stay routing-owned in
  `v2/opencode.jsonc`'s `agents` rows, so routing has one place.
- The V2 alignment check compares the installed markdown with these copies, as V1
  did: frontmatter differences are `DRIFT`, prose differences are `STALE`.

**Temperature is removed.**

- `reviewer` and `expert` lose `temperature: 0.1` in `v2/opencode.jsonc` and in
  the V2 agent markdown.
- *Reason:*
  - every routed role runs on a reasoning model with an effort set;
  - Anthropic's Fable 5.x models reject `temperature`;
  - OpenAI reasoning models do not honour it either;
  - on 2.x an agent-level value is not sent at all.

  Effort is the lever for review depth.
- No temperature-carrying variants are introduced.

**`blacklist` is removed** and not replaced. 2.x has no equivalent, and it does
not discover undeclared models. The routing README states the rule: a model you
must not use is a model you do not declare.

**Routing-owned keys** (what activation writes):

- `model`;
- `agents.<role>` for each role the V2 targets manifest declares. The row is
  replaced whole, as V1 replaced whole `agent` rows;
- within the top-level `permissions` list, only entries whose `action` is
  `subagent`;
- within `instructions`, exactly one entry: the absolute path of the installed
  `model-routing.md`. Activation makes sure it is present, as V1 activation
  normalised its relative entry. Every other `instructions` entry is
  user-owned. *(Builder-check call)*

Activation removes every existing top-level `subagent` entry. It then appends
the profile's `subagent` entries **after** the user's remaining entries, in
profile order, because the list is ordered and the last match wins.

Everything else is user-owned and preserved: `providers` (with their variants),
`policies`, `plugins`, `mcp`, `instructions`, `references`, `update`, other
agents, and non-`subagent` permissions.

**`activate-profile.sh` (V2).** It keeps V1's safety properties:

- target selection fails when both `opencode.json` and `opencode.jsonc` exist;
- a timestamped backup with a manifest is taken before the change;
- `--dry-run`;
- a generated header that records the profile id, the source digest and the
  activation time;
- an atomic replace.

It **refuses a V1-shaped target**, meaning one that has any of `agent`,
`provider`, `permission`, `plugin`, `disabled_providers` or `autoupdate`. It
names the conversion tool in its message.

For a provider declared in the target's `providers` section, it checks that
every variant the profile assigns is declared on that model. An undeclared
variant is an error, because 2.x would ignore it silently.

Built-in providers need no declaration. *Measured* on a 2.3.0 host:
`openai/gpt-6.2-astra#xhigh` resolved and served a call although the config
declared no `openai` provider.

Activation therefore does not validate built-in providers' variants statically.
The verifier does it against the server, through `GET /api/model`, which lists
every model's variants (measured). Built-in provider entries never become
routing-owned.

**`convert-v1-config` (new).** A one-time conversion of a V1 config file to V2,
following the RFC's translation table.

- It writes beside the file. It never replaces in place without a flag, and
  always takes a backup.
- It drops `temperature`, `blacklist` and `server`, and reports each dropped
  key.
- **How it converts:** it uses 2.x's own translation rather than reimplementing
  the table. It starts a sandboxed 2.3.0 server whose only config is the V1 file
  (isolated as Part 2 describes, with no credentials needed), polls
  `GET /api/config`, and takes the `document` layer's `info` as the V2 result.
  It then removes `agents.*.request.body.temperature`, and `request` if that
  leaves it empty.
- **Check:** the result must have no V1 key, and must reload in a second
  sandboxed server with an identical `GET /api/config` `info`.

*Builder first:* check upstream's `migrate-v1` guide for an official converter
command. If one exists, prefer it and keep the reload check.

**`check-alignment.sh` (V2).** A file-level drift check of an installed V2
config against a V2 profile. It reports `ALIGNED`, `DRIFT`, `STALE` or `ABSENT`
like V1, and never repairs. It compares exactly the routing-owned keys above.

**`verify-effective-routing.sh` (V2).**

- **Its oracle is the running server's HTTP API**, never `opencode debug ...` and
  never the database.
- **Input:**
  - the server URL (default `http://127.0.0.1:4096`);
  - credentials read from an env file named by argument, passed to curl over
    stdin, never in argv;
  - a V2 targets manifest;
  - a neutral directory and, optionally, a project directory.
- **Calls:** `GET /api/agent/<role>?directory=<dir>` for each role, from each
  directory. The first request per directory is retried until the agent
  resolves, bounded at 30 s, because agents load lazily per location. A role
  still missing after the bound is a `MISMATCH`.
- **Checks:**
  - `providerID`, `model`, `variant` and `mode`;
  - that the effective `permissions` deny `subagent` on `breakglass` for every
    agent where the profile says so (last match wins);
  - forbidden models.
- **Output:** `effective-routing.json`, with `PASS`, `PROJECT_OVERRIDE` and
  `MISMATCH`, as in V1.
- An optional `--call` mode sends one short tool-using prompt per role through
  `opencode run --server … --agent <role> --format json --archived`. It reads the
  model actually used back from `/api/session/<id>/message`, so it measures
  behaviour, not only configuration.

**`probe-breakglass.sh` (V2).** The Breakglass model and variant come from the
profile, not from constants. It checks:

- that Breakglass resolves as a primary agent;
- that no other agent can dispatch it as a subagent.

It runs through the server API (and `--call` for a live probe).

**Installer.** `configure_opencode_superpowers` writes V2:

- `plugins` (an array) instead of `plugin`;
- a new config is created as `{ "$schema": …, "plugins": [ … ] }`;
- it refuses a V1-shaped existing config, with the same message as activation.
  This applies to non-strict JSONC as well, the common case, since activation
  writes a comment header. *(Builder-check call)*
  - Today's awk exact-line match would accept a V1 `plugin` array that contains
    the pinned line. So the installer gains a small `python3`
    comment-stripping parse, standard library only, used solely to detect V1
    top-level keys.
  - A file that cannot be parsed fails closed, as today.
  - The existing rule that non-strict JSONC is never rewritten stays.
- tests in `tests/install.sh` cover V2 create, V2 update, and V1 refusal.

*Builder's call:* whether the installer also writes `"update": "disable"` when it
creates a config. The runbook already requires it; prefer doing it if it fits
the existing writer.

**Docs.**

- `models/routing/opencode/README.md`:
  - the V2 workflow: convert once, activate, check, verify;
  - the V2 profile format, as the contract a private generator targets;
  - the removal of temperature and blacklist.
- `docs/opencode-service.md`, verification step: use the V2 verifier.
- The RFC's follow-ups 1, 2 and 5 are marked closed, with links.

### Part 2 — per-role screening on OpenCode 2

**Scope.** *(Operator decision.)* Newer models are evaluated the way the latest
evaluations were: **per-role screenings**. Candidate models are compared on one
role's task. The October records `reviewer-cross-family-screening`,
`opus55-reviewer-screening` and `opus55-gpt61-build-quality-screening` show the
flow.

The Phase-R gate runners are **not ported**. They stay as V1 history:

- the reviewer, explore, compaction and build-restoration gates;
- the phase-3 build fixture;
- self-variance;
- readiness validation.

So no `compaction-invariants-oc2` copy is needed.

**What is ported.** These are the shared pieces the screening scripts call. They
are ported into `opencode-v2-adapter/`, with their contracts kept (inputs,
output files, exit codes):

- `dispatch-fixture`;
- `capped-opencode`, which sums `step_finish.part.cost`, reported by 2.x;
- `capture-tree-patch`;
- `verify-freeze-manifest`;
- `budget-ledger` and `provenance`;
- `classify-capability-failure`;
- the capability probe that screenings run before spending.

Scoring under `eval/scoring/` is reused unchanged, because the V2 dispatcher emits
the same output files. On 2.x, `--model` takes `provider/model#variant`; the V1
`--variant` flag is not used.

**A reusable screening runner (new).** It replaces the one-off `run-screening.sh`
copied into each record directory with one runner in `opencode-v2-adapter/`.

- **Inputs:**
  - the role;
  - one or more candidates, each `provider/model#variant` or `--agent <role>`
    under a given V2 profile;
  - the run count;
  - a budget;
  - an output record directory.
- **What it does,** in the order the October screenings did:
  1. writes the protocol;
  2. takes a catalog snapshot;
  3. runs the capability check per candidate, stopping that candidate on
     failure;
  4. writes and verifies a freeze manifest over the runner, fixture and scorer
     it is about to use;
  5. dispatches the runs under the budget ledger;
  6. normalises the results;
  7. scores them;
  8. writes a result skeleton.
- **What stays with the operator:** adjudication and the written conclusion, as
  in the October records. The runner produces the inputs for them; it does not
  decide.
- **Roles.** Each role it supports is described by one small definition file:
  fixture, prompt, scorer, and what counts as a valid run. Two are defined now,
  because they are the two with screenings:
  - **reviewer:** `fixtures/reviewer-seeded-defects-v2` with
    `scoring/reviewer-v2.py`. Its README names it the design input for future
    screenings, and results start a fresh baseline anyway;
  - **build:** `fixtures/build-workloads` with the verification the build-quality
    screening used (`verify-results-v2`).

  More roles are added later by adding definitions, not code.
- **Output.** A record directory with the same artifact set as the October
  screenings, with a `v2-` prefixed name:
  - `protocol`, `catalog-snapshot`, `freeze-manifest.json`, `ledger.json`;
  - `capability/` and `runs/`;
  - normalised findings or attempts, and scores;
  - a `result.md` skeleton.

  Each record also carries `runtime_version` and the profile digest.

*Builder first:* read the three October `run-screening.sh` scripts and their
`protocol` files, and reproduce their flow. Where the three differ, follow
`opus55-gpt61-build-quality-screening`, the most recent and most complete.

**Isolation, mandatory.** Every run executes in a sandbox:

- scratch `HOME` and `XDG_{CONFIG,DATA,STATE,CACHE}_HOME`, under the record
  directory;
- `env -i` with an explicit allowlist. The October screenings' switches carry
  over: `OPENCODE_DISABLE_PROJECT_CONFIG`,
  `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`, `OPENCODE_DISABLE_EXTERNAL_SKILLS`;
- a 2.x server started with `opencode serve` on a spare loopback port, with a
  throwaway password and `OPENCODE_DISABLE_AUTOUPDATE=1`;
- every call made with `opencode run --server <that url>`;
- the server stopped by pid at the end.

The runner refuses to start if any sandbox path resolves inside the invoking
user's real config or data directories.

**Config layers are checked**, because `HOME` and `XDG_*` alone do not isolate.
This was measured: the real `~/.opencode` and the working directory's config
are also loaded. The runner therefore:

- starts the server with its working directory inside the sandbox;
- reads `GET /api/config` before any dispatch, and refuses unless every layer
  is inside the sandbox, or is the account's `~/.opencode` holding none of
  `opencode.json`, `opencode.jsonc`, `agents/`, `agent/`, `command/`, `plugins/`;
- records the layer list in the run record.

The sandbox config is **built in full**, never overlaid on the user's:

- the V2 profile under test, or a minimal config naming only the candidate model;
- the operator's provider fragment, a V2 `providers` and `policies` file passed
  by path, because providers and credentials are deployment-specific;
- the operator's credentials file, passed by path;
- the V2 instructions and agent markdown from `v2/.opencode/`.

*Unmeasured, measure first:* the cleanest way to give a fresh 2.x data
directory credentials. Phase 0 showed that a 1.x-format `auth.json` in the data
directory is imported on first start.

**One sandbox server per dispatch.** *(Builder-check call)* Generation runs
inside the server, so killing only the client would not stop spending. On a
budget stop or a timeout, the runner kills both the client's and the server's
process groups. Starting a server per dispatch costs about a second, and it
keeps the V1 contracts for `BUDGET_STOP` and `TIMEOUT` true without an
unmeasured session-abort call.

**Records.** `dispatch.json` and the attempt records gain `runtime_version: 2.x`
and the profile digest. They replace the V1 sentinel `routing_profile_id` with
the real id, or `direct-model-evaluation` for `--model` candidates.

Folders copied for OpenCode 2 take the suffix `-oc2`, because `-v2` already means
"fixture revision 2" in this tree (`reviewer-seeded-defects-v2`).
*(Builder-check call)*

**Tests.**

- Every ported script, and the screening runner, gets a test in `eval/tests/`
  with a fake `opencode`. The fake answers `serve` (it records its args, prints
  the "listening" line, and serves nothing), and answers `run --server …` with
  recorded 2.x JSONL (`step_start`, `tool_use`, `step_finish`, `text`).
- A sandbox-isolation test asserts that no path outside the record directory is
  written, and that the refusal fires.
- A runner test covers the full flow with a fake: capability failure stopping a
  candidate, a budget stop, a freeze-manifest mismatch, and a complete
  two-candidate run.
- The existing V1 tests stay and keep passing.

### Part 3 — `observe`

`observe` gains 2.x support: it reads the 2.x tables. `session_v2` is known; the
builder inspects the rest of the 2.3.0 schema on a sandbox copy and writes the
fail-closed schema check for it.

- It keeps V1 support, because it is a read-only metadata tool and old
  databases exist. It selects by detected schema and fails closed on an unknown
  one.
- *Unmeasured:* the 2.x log format under `log/`. Measure it before porting the
  log classifier. If it changed beyond reason, the log path is V1-only and
  documented as such.
- Tests: a 2.x sqlite fixture beside the V1 one.

## Order of work

1. Part 1. Parts 2 and 3 need the V2 profile format and the verifier.
2. Part 2.
3. Part 3. It is independent of Part 2 and may go in parallel once Part 1 has
   merged.

Each part is its own pull request.

## Left to the builder

- Exact file names inside `opencode-v2-adapter/`, and how to share helpers
  between the operational tools and the runners.
- How credentials enter the sandbox (measure first).
- The 2.x schema for `observe`, and the log format (measure first).
- Whether an upstream V1→V2 converter exists to wrap.
- Whether the installer also writes `"update": "disable"`.

## Consumers outside this repository

A deployment that generates its own profiles, for example for a private
gateway, must emit the V2 profile format documented in the routing README.

A host with a V1 config converts it once with `convert-v1-config`. It then
activates the V2 profile and verifies against its running server. Those steps
belong to the host's own records, not to this repository.
