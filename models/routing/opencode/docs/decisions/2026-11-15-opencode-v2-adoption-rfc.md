# OpenCode V2 Adoption RFC

## Status

Accepted for implementation on 2026-11-15. This record changes the toolkit's
installer, service runbook and service scripts to target OpenCode 2.x. It does
not change any tracked routing profile.

## Trigger

`docs/decisions/2026-09-02-multi-model-routing-v3.4.3.md` section 41 requires a
separate V2 RFC when upstream promotes 2.x to stable and the 1.x line enters
maintenance, and states that "The RFC must precede toolkit adoption of V2".
Both parts of the first condition now hold:

- 2.x is the stable line; the latest release is 2.3.0 (2026-11-13), not a
  prerelease.
- The last 1.x release is 1.19.5 (2026-10-28), and the 1.x installer
  (`https://opencode.ai/install`) refuses to install 2.x.

## Evidence boundary

Everything below was measured in isolated sandboxes on a WSL2 workstation,
2026-11-15, with OpenCode 2.3.0. No live service was upgraded. The
host-verification record in the runbook for 1.18.31 stays as history; the 2.x
material is sandbox-verified, not a live service run.

## Scope

In scope: the installer, the service runbook, the readiness probes and the
gateway-restart helper. Out of scope: the tracked routing profiles, the routing
eval adapter and the observe tool (see "Follow-ups").

## Decisions

### A. Installer

`install_opencode` uses the 2.x installer `https://opencode.ai/v2/install`
(flags `--version <v>`, `--binary`, `--no-modify-path`; destination
`~/.opencode/bin`). The version is pinned by the catalog entry
`opencode=2.3.0`, overridable with `ADT_OPENCODE_VERSION`, and passed with
`--version`. The toolkit keeps no 1.x pin and no 1.x install path.

The installer guards on data, not on the binary. The 2.x first start migrates
`opencode.db` in place and upstream does not support downgrade, so the
installer never starts that path for an existing database:

| State | Behaviour |
|---|---|
| `${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db` exists, installed binary is 1.x | Binary left untouched, clear warning (also under `--upgrade`) naming the runbook's major-upgrade procedure; the rest of the run succeeds |
| DB exists, no binary | Stops before any mutation, naming `--skip-opencode` and the runbook |
| DB exists, binary already 2.x | Normal; under `--upgrade` moves to the pinned 2.x |
| No DB | Fresh install of the pinned 2.x |

Version detection runs `opencode --version`. A sentinel-database test measured
that `--version` and `--help` neither open nor modify the database.

Rejected alternatives:

- **A1, a silent major upgrade under `--upgrade`.** It performs an irreversible
  data migration for someone who only meant to upgrade unrelated tools.
- **A2, an in-installer backup.** The backup would be taken with the service
  live and would be stale by the time the migration fires; a consistent backup
  needs the service stopped, which is an operator step, not an installer one.

### B. Service runbook

`docs/opencode-service.md` documents 2.x as the target:

- `ExecStart` is `opencode serve --hostname 127.0.0.1 --port 4096`. `opencode
  web` does not exist in 2.x.
- `OPENCODE_DISABLE_AUTOUPDATE=1` in the unit, and config `autoupdate: false`,
  so the pin is not defeated by self-upgrade.
- The server reads `OPENCODE_PASSWORD`; `OPENCODE_SERVER_PASSWORD` is also
  accepted and `OPENCODE_PASSWORD` wins when both are set. The Basic-auth
  username is always `opencode`; `OPENCODE_SERVER_USERNAME` is ignored. A
  password is mandatory for this deployment.
- 2.x clients by default start or reuse a shared background service
  (`opencode serve --service`), configured with `opencode service
  get|set|unset` (keys `disabled|hostname|port|password|cors|env|remote`). The
  operator runs `opencode service set disabled true` before any client runs.
  With it disabled, a client without `--server` starts a private in-process
  server on the same database (1.x `run` without `--attach` behaved the same).
  `remote` opens a public access tunnel and must never be set.
- `opencode attach` is gone. Clients use `--server <url>` with
  `OPENCODE_PASSWORD`, `OPENCODE_SERVER_PASSWORD` or credentials in the URL (all
  three measured working).
- `/global/health` is no longer a health endpoint: it returns 200 `text/html`
  (the web UI's SPA fallback) even unauthenticated. The health surface is
  `GET /api/info`: 401 unauthenticated, 200 JSON with `version` and `pid`
  authenticated.
- A new section, "Moving an existing 1.x installation to 2.x". Measured on a
  14.8 GB / 1,688-session database: the server answered within 1 s,
  `GET /api/experimental/migration/v1` reported `{"status":"completed"}` after
  34 s, every session was preserved and the file mode became 0600. The
  procedure is preflight, a required rehearsal gate in an isolated sandbox
  restored from the backup artifact, an at-rest backup with SQLite's backup
  API taken with everything stopped, the binary swap, a foreground migration
  step outside the unit (the unit's readiness window could expire mid-migration
  on a slower host), verification, an explicit no-go point and a rollback that
  restores the database, config, auth and the saved 1.x binary.

### C. Readiness probe

`opencode-startup-ready.sh` supports 2.x only. READY requires all of: an
authenticated `GET /api/info` answering HTTP 200; a body that parses as JSON;
`version` with major 2; and `pid` equal to `MAINPID` when it is set. It is not
READY while `GET /api/experimental/migration/v1` reports a status other than
`completed`. An unauthenticated `GET /api/info` must return 401; a 200 means
the server runs without a password and the probe fails. `READY_TOOL_MARKER` is
an error: 2.x has no tool-ID listing in its OpenAPI, so the tool guarantee has
no endpoint. A detected 1.x server (`/global/health` returning JSON with
`"healthy":true`) fails immediately, so a stale unit trips the start limit
instead of looping.

Rejected alternatives:

- **C2, a dual-mode probe.** `ExecStart` changes between majors anyway, so unit
  and probe are swapped as a pair.
- **C3, an explicit mode variable.** It keeps a branch for a line the toolkit no
  longer installs.

### D. Other scripts

- `opencode-telegram-ready.sh` replaces its `/global/health` check with the same
  2.x `/api/info` check (200, JSON, major 2; no `MAINPID` comparison because
  `MAINPID` there is the bot's). The bot needs a release with OpenCode 2
  support (`@grinev/opencode-telegram-bot` 0.26.0 or newer, configured with
  `OPENCODE_SERVER_VERSION=v2`; the bot's V2 default URL is the shared service,
  so it must be pointed at the unit's URL). The `Bot @... started!` journal
  marker must be re-verified on the new bot version.
- `opencode-gateway-restart.sh` reads 1.x `/session/status`. It is declared
  unsupported on 2.x: when the server identifies as 2.x it exits non-zero
  without restarting. A latent hazard is fixed as well: a 404 or non-JSON body
  from `/session/status` no longer counts as idle.

## Config translation, as measured

A V1-shaped `opencode.jsonc` runs on 2.x. It is normalised in memory and the
file is not rewritten; `opencode debug config` shows the result:

| V1 | V2 |
|---|---|
| `provider` | `providers` (`npm` becomes `package: "aisdk:..."`, `options.baseURL` becomes `settings.baseURL`, value preserved) |
| model `variants` | array of `{id, settings}` |
| `disabled_providers` | `policies` with `provider.use deny` |
| `permission` | ordered `permissions` array (`task` becomes `subagent`, per-agent deny rules preserved) |
| `agent` | `agents` with `{providerID, model, variant}` |
| `plugin` | `plugins` (Superpowers v7.0.1 loaded active) |
| `mcp.<name>` | `mcp.servers.<name>` |
| `server` | dropped |
| provider `blacklist` | **dropped silently** |

Upstream warns not to mix V1 and V2 shapes within one section
(anomalyco/opencode#56816: a custom provider silently lost its `baseURL` when
shapes were mixed).

## Ruling on routing

- The tracked V1 profiles stay V1 and are not made portable, per the
  2026-09-02 record.
- Running a V1-shaped config on 2.x through upstream's documented in-memory
  translation is permitted for cutover.
- Conversion to V2 shape needs a V2 routing adapter.
  `eval/runtime/opencode-v1-adapter/` (`activate-profile.sh`,
  `verify-effective-routing.sh`) and `observe/` (session storage keyed to
  1.18.32) remain V1-only until then.
- The provider `blacklist` being dropped silently means a profile relying on it
  needs an explicit check after cutover.

## Ruling on temperature

Measured through a logging proxy against an OpenAI-compatible LiteLLM gateway
declared as a custom provider:

- Agent-level `temperature` is **not** sent on 2.3.0 (the request had no
  `temperature` key).
- `temperature` placed in a model variant
  (`"variants": {"<name>": {"reasoningEffort": "high", "temperature": 0.1}}`) **is**
  sent, together with `reasoning_effort`.

So on 2.x a role that needs a temperature must reference a model variant that
carries it. The tracked profiles set agent-level temperature on `reviewer` and
`expert`; this is a follow-up for the V2 adapter and the V1 profiles are not
edited. It was not measured whether 1.x sent the agent-level temperature.

## Other measured facts

- Effort is sent as `reasoning_effort` with the variant's value for every role
  tested (`high`, `xhigh`, `medium`, `low`).
- 2.x did not call the gateway's `/v1/models` and listed only declared models:
  there is no discovery of undeclared models.
- Credentials in V1 `auth.json` are imported into the database on first start.
- The first 2.x start marks the V1 import as done (anomalyco/opencode#57226), so
  later V1 data is not re-imported.

## Upstream references

- Migration guide: `https://opencode.ai/v2/docs/migrate-v1`.
- No downgrade: anomalyco/opencode#60394, #55555, #53221.
- Superpowers V2 support: obra/superpowers#2306 (needs 6.4.1 or newer).

## Follow-ups

1. A V2 routing adapter and V2-shaped profiles, including variant-carried
   temperature for `reviewer` and `expert` and an explicit replacement for the
   dropped provider `blacklist`.
2. The observe tool on the 2.x database tables.
3. `opencode-gateway-restart.sh` on 2.x.
4. A live cutover verification record for the runbook.
