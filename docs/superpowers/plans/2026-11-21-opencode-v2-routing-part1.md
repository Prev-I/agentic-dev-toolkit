# OpenCode 2 routing alignment, Part 1 — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the routing bundle in native OpenCode 2 shape, with 2.x tools to:

- convert a 1.x config once;
- activate a profile;
- check for drift;
- verify against the running server;
- probe Breakglass.

The installer's Superpowers writer moves to the 2.x shape too.

**Architecture:**

- **Bundle:** a new `models/routing/opencode/v2/` bundle is the single V2
  routing authority.
- **Tools:** new tools live in `eval/runtime/opencode-v2-adapter/`. They share
  one Python helper for JSONC loading and shape detection, and one Bash helper
  for authenticated, polled HTTP calls.
- **History:** the V1 bundle and the V1 adapter are untouched history.

**Tech stack:**

- Bash (`set -Eeuo pipefail`, `IFS=$'\n\t'`) and Python 3 standard library;
- `jq` and `curl`;
- OpenCode 2.3.0's HTTP API.

Tests are Bash suites run by `models/routing/opencode/eval/run-tests.sh`, using
fakes injected through `OPENCODE_BIN` and a fake API server.

**Spec:** `docs/superpowers/specs/2026-11-21-opencode-v2-routing-alignment-design.md`
(Part 1). Read it before any task.

## Global constraints

- Branch `feat/opencode-v2-routing`; integration by pull request.
- Never edit:
  - `eval/runtime/opencode-v1-adapter/**`;
  - the root `opencode.jsonc`;
  - `profiles/**`;
  - the root `.opencode/**`;
  - `eval/manifests/**`;
  - `eval/records/**`;
  - `eval/fixtures/**`.
- The only existing test file a Part 1 task may edit is `tests/install.sh`
  (Task 8). The V1 suites must pass unchanged.
- **No mixed shapes.** No file written by these tools contains any of the V1
  top-level keys `agent`, `provider`, `permission`, `plugin`,
  `disabled_providers`, `autoupdate` or `server`, or a `mcp` object without
  `servers`.
- **The V1 → V2 permission action map** (measured): `bash` → `shell`,
  `task` → `subagent`. Every other action keeps its name. Nested V1 patterns
  become `{action, resource: <pattern>, effect}` entries, in V1 order.
- **The V2 agent prompt key is `system`.** `prompt` is not V2.
- **Routing-owned keys:**
  - `model`;
  - `agents.<role>` for every declared role (each row replaced whole);
  - top-level `permissions` entries whose `action` is `subagent`;
  - the single `instructions` entry equal to the absolute path of the installed
    `model-routing.md`.
- **Credentials** reach curl only through `curl -K -` on stdin, never in argv. A
  password containing `"` or `\` is refused with exit 2.
- **Agents load lazily per location.** Every agent lookup against a server polls
  until the agent resolves, bounded at 30 s (`V2_AGENT_POLL_TIMEOUT`, default
  `30`).
- Scripts are tracked executable (`100755`) and shellcheck-clean, with LF line
  endings. No line starts with `# shellcheck ` unless it is a directive.
- Bump `environments/linux/install.sh` `SCRIPT_VERSION` from `0.4.0` to `0.5.0`
  in the installer commit.
- No secrets in any file, test or output.

## Review focus

The five conditions most likely to bite a user that no task's core tests cover.
Each now has a test in the task that owns it.

1. **A live config written by V1 activation is non-strict JSONC**, with `//`
   header comments and URLs containing `//` inside strings. Activation,
   alignment and the installer must parse it correctly, never cut at a `//`
   inside a string (Tasks 2, 8).
2. **The live file is `opencode.json`, strict JSON, not `.jsonc`.** Activation
   must write back to that same file, keep strict JSON, and not create a
   `.jsonc` beside it (Task 3).
3. **A minimal V2 config freshly created by the installer**
   (`{"$schema","update","plugins"}`, with no `agents`, `permissions` or
   `instructions`): activation must add them, not fail (Task 3).
4. **A server freshly restarted when the verifier runs**: the first lookup
   returns `AgentNotFoundError`. The verifier must poll and report `PASS`, not
   `MISMATCH` (Task 5).
5. **A password with `"` or `\` in the credentials file**: the verifier and the
   probe refuse with a clear message and exit 2, rather than sending broken
   auth (Task 5).

---

### Task 1: The V2 bundle and its shared Python helper

**Files:**
- Create: `models/routing/opencode/v2/opencode.jsonc`
- Create: `models/routing/opencode/v2/.opencode/agents/reviewer.md`, `expert.md`, `scout.md`
- Create: `models/routing/opencode/v2/.opencode/model-routing.md`
- Create: `models/routing/opencode/v2/manifests/current-routing-targets.json`
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/v2config.py`
- Test: `models/routing/opencode/eval/tests/v2-bundle-test.sh`

**Interfaces:**
- Produces: `v2config.py`, a CLI, `python3 v2config.py <subcommand> …`, exit 0
  on success, 1 on a finding, 2 on usage:
  - `load FILE` — prints the file as strict JSON. Comments are stripped by the
    same string-aware scanner as V1's `load-routing-profile.sh`.
  - `shape FILE` — prints `v1`, `v2` or `empty` (missing or zero bytes). Exits
    1 with `invalid` if it cannot be parsed.
  - `md-frontmatter FILE` — prints the markdown frontmatter as JSON. It accepts
    only the measured subset: scalar keys, and a `permissions:` list of
    `action/resource/effect` mappings.
- Produces: the targets manifest format `opencode-v2-routing-targets/1`:

  ```json
  {
    "format": "opencode-v2-routing-targets/1",
    "profile_id": "v7-opencode2-2026-11-21",
    "default_model": {"providerID": "...", "model": "..."},
    "agents": {
      "<role>": {"providerID": "...", "model": "...", "variant": "...", "mode": "primary|subagent|null"}
    },
    "breakglass": {"agent": "breakglass", "deny_as_subagent": true},
    "forbidden_model_references": ["claude-opus-4.6", "gpt-5.3-codex"],
    "forbidden_effective_state": { "...": "copied from the V1 manifest, in V2 model form" }
  }
  ```

- [ ] **Step 1: Write the failing test `v2-bundle-test.sh`.** Assertions:
  - `v2config.py shape v2/opencode.jsonc` prints `v2`;
  - no key named `temperature` anywhere in `v2/opencode.jsonc`, nor in any V2
    agent markdown;
  - for each of the eleven roles in the V1 `eval/manifests/current-routing-targets.json`,
    `v2/opencode.jsonc` has `agents.<role>.model` equal to the V1 model split
    at the first `/` into `{providerID, model}`, with the same `variant`. The
    same holds for `default_model` against `.model`;
  - the V2 manifest's `agents` equal `v2/opencode.jsonc`'s rows on
    `providerID`, `model`, `variant` and `mode`;
  - the top-level `permissions` in `v2/opencode.jsonc` end with
    `{"action":"subagent","resource":"breakglass","effect":"deny"}`;
  - every V2 agent markdown has no `permission:` and no `model:` key, and its
    `permissions` list equals the V1 root `.opencode/agents/<name>.md`
    permissions under the action map. Assert the reviewer's `shell` list
    exactly: `* deny`, `git status* allow`, `git diff* allow`, `git log* allow`,
    `git show* allow`;
  - `v2config.py shape` on a fixture with `{"agent":{}}` prints `v1`; on
    `{"agents":{},"plugins":[]}` prints `v2`; on an empty file prints `empty`;
  - `v2config.py load` keeps `"https://example.invalid//x"` intact in a JSONC
    file that also carries `// comment` lines (Review focus 1).
- [ ] **Step 2: Run it.** `bash models/routing/opencode/eval/tests/v2-bundle-test.sh`. Expected: FAIL (`missing file`).
- [ ] **Step 3: Write `v2config.py`.** Shape rule: `v1` if any V1 top-level key
  from Global constraints is present; otherwise `v2`.
- [ ] **Step 4: Write `v2/opencode.jsonc`** from the root `opencode.jsonc`:
  - same assignments, translated by the RFC table and the action map;
  - agent `prompt` → `system`;
  - `temperature` dropped;
  - a header comment naming the profile id and stating that this file is the V2
    routing authority.
- [ ] **Step 5: Write the V2 markdown copies.** Prose is copied from the root
  `.opencode/` files. Frontmatter is converted by the action map, and any
  sentence about temperature is removed. Then write the V2 manifest.
- [ ] **Step 6: Run the test.** Expected: PASS. Then run
  `bash models/routing/opencode/eval/run-tests.sh --strict`. Expected: all
  previous tests still pass.
- [ ] **Step 7: Commit.** `feat(routing): add the OpenCode 2 routing bundle and its config helper`

### Task 2: The HTTP helper and a fake API for tests

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/v2-http.sh`
- Create: `models/routing/opencode/eval/tests/fixtures-v2/fake-api.py`
- Test: `models/routing/opencode/eval/tests/v2-http-test.sh`

**Interfaces:**
- Produces (sourced Bash functions):
  - `v2_load_credentials FILE` sets the global `V2_PASSWORD` from
    `OPENCODE_PASSWORD`, falling back to `OPENCODE_SERVER_PASSWORD`, in a
    dotenv file. It returns 2 if the file is missing, the password is empty, or
    it contains `"` or `\`.
  - `v2_api_get URL_BASE PATH` writes the body to stdout and returns 0 on 200,
    1 otherwise. Authentication is `opencode:$V2_PASSWORD` via `curl -K -`.
  - `v2_agent_get URL_BASE ROLE DIR` polls
    `GET /api/agent/<role>?directory=<dir>` until `.data.model` is present or
    `V2_AGENT_POLL_TIMEOUT` seconds pass. It prints `.data`, or returns 1.
- Produces: `fake-api.py PORT FIXTURE_DIR` serves `GET <path>` from
  `FIXTURE_DIR/<path-with-/-as-_>.json` and requires Basic auth
  `opencode:test-only`. A file `<name>.lazy` makes the first request for that
  path answer `{"_tag":"AgentNotFoundError"}`. It writes the port and pid to
  stdout.

- [ ] **Step 1: Write the failing test `v2-http-test.sh`.** Assertions:
  - credentials with `OPENCODE_PASSWORD=test-only` load;
  - a password containing `"` returns 2 with a message naming the file
    (Review focus 5);
  - `v2_api_get` with the wrong password returns 1;
  - `v2_agent_get` against a `.lazy` fixture succeeds on the second poll;
  - with `V2_AGENT_POLL_TIMEOUT=1`, a missing agent returns 1 within 3 s;
  - `ps -o args` of the running curl never shows the password. Assert this by
    replacing `curl` on `PATH` with a stub that records its argv.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement `v2-http.sh` and `fake-api.py`.** Use
  `http.server.ThreadingHTTPServer`, bound to `127.0.0.1` on a free port chosen
  by the test.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(routing): add authenticated polled HTTP helper for OpenCode 2`

### Task 3: V2 activation

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/activate-profile.sh`
- Test: `models/routing/opencode/eval/tests/v2-activation-test.sh`

**Interfaces:**
- Consumes: `v2config.py load|shape` (Task 1).
- Produces:

  ```
  activate_profile_v2 --profile FILE --targets FILE --config-root DIR \
    --backup-root DIR --model-routing PATH [--dry-run]
  ```

  - exit 0 on success; 1 on refusal or conflict; 2 on usage;
  - prints `target=`, `backup_dir=`, `before_sha256=` and `after_sha256=`
    lines, as V1 does;
  - target selection, inlined: exit 1 if both `opencode.json` and
    `opencode.jsonc` exist;
  - a missing target is created as `{"$schema": "https://opencode.ai/config.json"}`
    before merging.

- [ ] **Step 1: Write the failing test `v2-activation-test.sh`.** Assertions:
  - activating `v2/opencode.jsonc` onto a V2 config that carries a user
    `providers`, `plugins`, `mcp.servers`, a user agent `custom-agent`, a user
    `permissions` entry `websearch * allow`, a stale
    `subagent breakglass allow`, and a user `instructions` entry
    `docs/house-style.md`:
    - `providers`, `plugins`, `mcp` and `custom-agent` are preserved byte-equal;
    - every declared role row equals the profile's;
    - top-level `permissions` is
      `[websearch * allow, <profile subagent entries in profile order>]`, so
      the stale entry is gone;
    - `instructions` contains `docs/house-style.md` and exactly one copy of the
      `--model-routing` absolute path;
  - a V1-shaped target (`{"agent":{}}`) exits 1, with `convert-v1-config` in
    stderr, and the file is unchanged;
  - both `opencode.json` and `opencode.jsonc` present: exit 1;
  - `--dry-run` changes nothing and prints `dry_run=1`;
  - the backup directory holds the original, `SHA256SUMS` and `manifest.json`;
  - the written file starts with a `//` header naming `profile_id` and the
    source digest;
  - a profile assigning `gewiss/gpt-sol#xhigh` while the target declares only
    `low|medium|high` for that model exits 1, naming the variant;
  - the same assignment on a provider not declared in `providers` (built-in)
    passes;
  - **Review focus 2:** with only `opencode.json` (strict JSON) present, the
    result is written to `opencode.json`. It parses with `jq`, which means it
    has no comment header in strict JSON: the header goes into `manifest.json`
    instead. No `opencode.jsonc` is created;
  - **Review focus 3:** a target of exactly
    `{"$schema":…,"update":"disable","plugins":[…]}` activates. The result
    gains `model`, `agents`, `permissions` and `instructions`, and keeps
    `update` and `plugins`;
  - the write is atomic: the temp file is in the target directory and is gone
    afterwards.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement `activate_profile_v2`.** The merge is a Python heredoc
  using `v2config.py load`. The header comment is written only for `.jsonc`.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(routing): add OpenCode 2 profile activation`

### Task 4: V2 alignment check and the entry point

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/check-alignment.sh`
- Modify: `models/routing/opencode/eval/check-alignment.sh` (switch to V2)
- Test: `models/routing/opencode/eval/tests/v2-alignment-test.sh`

**Interfaces:**
- Consumes: `v2config.py load|shape|md-frontmatter` (Task 1).
- Produces:

  ```
  check_alignment_v2 --profile F --targets F --bundle-root DIR \
    --live-config F --live-support-root DIR [--json OUT]
  ```

  - prints `ALIGNED`, `DRIFT`, `STALE` or `ABSENT`, with the V1 wording;
  - exit 0 for `ALIGNED`/`STALE`, 1 for `DRIFT`, 2 for usage or `ABSENT`;
  - a V1-shaped live config is `DRIFT`, with the message
    `live config is OpenCode 1.x-shaped; run convert-v1-config`.

- [ ] **Step 1: Write the failing test `v2-alignment-test.sh`.** Assertions:
  - after Task 3's activation onto a fixture, plus the V2 markdown copied into
    `<live>/agents/` and `model-routing.md`, the result is `ALIGNED`, exit 0;
  - changing a role's `variant` gives `DRIFT`, exit 1, naming the role;
  - removing the `subagent breakglass deny` entry gives `DRIFT`;
  - removing the `model-routing.md` instruction gives `DRIFT`;
  - editing a markdown body sentence gives `STALE`, exit 0;
  - changing a markdown `permissions` entry gives `DRIFT`;
  - deleting `<live>/agents/scout.md` gives `DRIFT`;
  - a V1-shaped live config gives `DRIFT` with the conversion message;
  - a user-owned change (`providers`, a user agent, `websearch`) stays
    `ALIGNED`;
  - the entry point `eval/check-alignment.sh`, with
    `XDG_CONFIG_HOME=<fixture>`, reports against `v2/` (its JSON output names
    `v2/opencode.jsonc`).
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement it, and repoint the entry point** to the V2 checker,
  `v2/opencode.jsonc`, `v2/manifests/current-routing-targets.json` and
  `v2/.opencode`. Keep its usage comment and exit codes.
- [ ] **Step 4: Run** the new test and
  `bash models/routing/opencode/eval/run-tests.sh --strict`. Expected: PASS,
  with `alignment-check-test.sh` (V1) unchanged and passing.
- [ ] **Step 5: Commit.** `feat(routing): check installed config against the OpenCode 2 bundle`

### Task 5: V2 effective-routing verifier

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/verify-effective-routing.sh`
- Create: `models/routing/opencode/eval/tests/fixtures-v2/api/` (canned
  `/api/agent/<role>`, `/api/model` and `/api/session/<id>/message` bodies, in
  the measured 2.3.0 shapes)
- Test: `models/routing/opencode/eval/tests/v2-effective-routing-test.sh`

**Interfaces:**
- Consumes: `v2-http.sh` (Task 2); the targets manifest (Task 1).
- Produces:

  ```
  verify_effective_routing_v2 --server URL --credentials FILE --targets FILE \
    --outdir DIR --neutral-cwd DIR [--project-cwd DIR] [--call]
  ```

  - writes `DIR/effective-routing.json` as
    `{runtime_version, server, roles: {<role>: {neutral: {...}, project: {...}, status}}, overall}`;
  - `status` is `PASS`, `PROJECT_OVERRIDE` or `MISMATCH`;
  - exit 0 if `overall` is `PASS` or `PROJECT_OVERRIDE`, 1 on `MISMATCH`, 2 on
    usage or credentials;
  - `runtime_version` comes from `GET /api/info` `.version`.
- Checks per role:
  - `providerID`, `model`, `variant` and `mode` against the manifest;
  - the variant appears in `GET /api/model`'s `variants` for that model;
  - unless the role is the breakglass agent, the last effective `permissions`
    entry matching `subagent`/`breakglass` has `effect: deny`;
  - no model id contains a `forbidden_model_references` string;
  - the role does not equal `forbidden_effective_state`.
- `--call` sends, per role,
  `$OPENCODE_BIN --server URL run --agent <role> --format json --archived --auto "<read-probe prompt>"`
  with `OPENCODE_PASSWORD` in the child's environment only. It reads the agent,
  model and variant actually used from `/api/session/<id>/message` and records
  them as `called: {used, tool_called, cost}`. A used model differing from the
  expected one is a `MISMATCH`.

- [ ] **Step 1: Write the failing test `v2-effective-routing-test.sh`**, with
  `fake-api.py` serving `fixtures-v2/api`. Assertions:
  - all eleven roles `PASS`;
  - one role served with the wrong variant gives `MISMATCH`, naming the field;
  - a variant missing from `/api/model` gives `MISMATCH`;
  - a `build` whose permissions end `subagent breakglass allow` gives
    `MISMATCH`;
  - a project-directory response differing from the neutral one gives
    `PROJECT_OVERRIDE`, exit 0;
  - **Review focus 4:** every agent fixture marked `.lazy` still gives `PASS`;
  - **Review focus 5:** a credentials file whose password contains a backslash
    exits 2 and makes no request (the fake's request log is empty);
  - `--call` with a fake `OPENCODE_BIN` printing recorded 2.x JSONL
    (`step_start`, `tool_use` with `"tool":"read"`, `step_finish` with `cost`,
    `text`) and the matching message fixture records `called.used` as
    `<role>@<provider>/<model>#<variant>`;
  - `called.used` with a different model gives `MISMATCH`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement it.** The comparison is a Python heredoc fed the
  collected JSON.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(routing): verify effective routing through the OpenCode 2 API`

### Task 6: V2 Breakglass probe

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/probe-breakglass.sh`
- Test: `models/routing/opencode/eval/tests/v2-breakglass-test.sh`

**Interfaces:**
- Consumes: `v2-http.sh` (Task 2); `fixtures-v2/api` (Task 5); the manifest
  `breakglass` block (Task 1).
- Produces:

  ```
  probe_breakglass_v2 --server URL --credentials FILE --targets FILE \
    --outdir DIR --cwd DIR [--call]
  ```

  - writes `DIR/breakglass.json` as
    `{resolved_primary, model, non_exposure: {<agent>: deny|EXPOSED}, called?, status}`;
  - exit 0 on `PASS`, 1 on `FAIL`, 2 on usage;
  - the expected model comes from the manifest. The script contains no model id.

- [ ] **Step 1: Write the failing test `v2-breakglass-test.sh`.** Assertions:
  - the fixtures give `PASS`, with `resolved_primary: true` and the manifest's
    model;
  - breakglass served as `mode: subagent` gives `FAIL`;
  - any other agent (fixtures list all API agents, including the built-ins
    `build`, `general`, `explore`, `plan`, `compaction`, `title`, `summary`)
    whose last matching entry allows `subagent breakglass` gives `FAIL`, naming
    it;
  - `grep -E 'gpt-|claude-'` on the script finds nothing;
  - `--call` with the fake binary records `called.used`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(routing): probe Breakglass through the OpenCode 2 API`

### Task 7: One-time V1 → V2 config conversion

**Files:**
- Create: `models/routing/opencode/eval/runtime/opencode-v2-adapter/convert-v1-config.sh`
- Create: `models/routing/opencode/eval/tests/fixtures-v2/fake-opencode-serve.sh`
  (a fake `opencode` whose `serve` starts `fake-api.py` with a canned
  `/api/config`)
- Test: `models/routing/opencode/eval/tests/v2-convert-test.sh`

**Interfaces:**
- Consumes: `v2-http.sh` and `v2config.py shape` (Tasks 1–2).
- Produces:

  ```
  convert_v1_config --input FILE --output FILE [--in-place] \
    --backup-root DIR [--opencode-bin BIN]
  ```

  - exit 0 on success; 1 if the reload check fails or the result is not `v2`;
    2 on usage, or if the input is not `v1`;
  - prints `dropped: <key path>` for every removed
    `agents.*.request.body.temperature`, and for the V1 input's provider
    `blacklist` and `server` keys.
- Sandbox, in both of its servers:
  - a temporary directory with `home`, `config/opencode/opencode.json` (the
    input, comments stripped), `data`, `state`, `cache` and `work`;
  - `cd work`;
  - `env -i PATH=/usr/bin:/bin` with sandbox `HOME` and `XDG_*`, a random
    password and `OPENCODE_DISABLE_AUTOUPDATE=1`;
  - `serve --hostname 127.0.0.1 --port <free>`;
  - poll `GET /api/config` until the `document` layer appears (30 s bound);
  - kill by pid, and remove the directory on exit, failure included.

- [ ] **Step 1: Check upstream first.** Read `https://opencode.ai/v2/docs/migrate-v1`
  for an official converter command. If one exists, note it in the script
  header and prefer it in Step 4, keeping the reload check. Record what you
  found in the commit message.
- [ ] **Step 2: Write the failing test `v2-convert-test.sh`.** Assertions:
  - with the fake binary, the output equals the canned translation minus the
    temperature, and stdout lists `dropped: agents.reviewer.request.body.temperature`;
  - the output's `shape` is `v2`;
  - a `v2` input exits 2;
  - without `--in-place`, the input file is unchanged;
  - with `--in-place`, the original is in `--backup-root` and the input path now
    holds V2;
  - a fake whose second server returns a different `info` exits 1, leaving the
    output path absent;
  - no process started by the test survives it (`pgrep -f fake-api.py` is empty
    after the run);
  - nothing is written outside the test's temporary root (`find` with
    `-newer`).
- [ ] **Step 3: Run it.** Expected: FAIL.
- [ ] **Step 4: Implement it.**
- [ ] **Step 5: Run it.** Expected: PASS.
- [ ] **Step 6: Manual check against the real binary,** not part of the suite.
  Run `convert_v1_config --input models/routing/opencode/opencode.jsonc --output /tmp/v1-root-converted.json --backup-root /tmp/bk --opencode-bin ~/.opencode/bin/opencode`.
  Expected: exit 0. Then `diff <(python3 v2config.py load v2/opencode.jsonc | jq -S '.agents') <(jq -S '.agents' /tmp/v1-root-converted.json)`
  must show no difference in any role's `model`. Record the result in the PR
  description.
- [ ] **Step 7: Commit.** `feat(routing): convert an OpenCode 1.x config with 2.x's own translation`

### Task 8: Installer Superpowers writer in V2 shape

**Files:**
- Modify: `environments/linux/install.sh`:
  - `opencode_superpowers_configured` (~354);
  - `preflight_opencode_superpowers` (~377);
  - `configure_opencode_superpowers` (~1512);
  - `SCRIPT_VERSION` (line 15).
- Modify: `tests/install.sh` (the Superpowers tests, ~76–215)

**Interfaces:**
- Produces: `opencode_config_shape FILE`. It prints `v1`, `v2`, `empty` or
  `unparseable`. It uses `jq` for strict JSON, and otherwise a `python3` heredoc
  with the string-aware comment scanner.
  - The shape rule is the same as `v2config.py shape`, inlined because the
    installer ships alone with its catalog.
  - If `python3` is absent and the file is not strict JSON, it returns
    `unparseable`.

Behaviour of each function:

- **`configure_opencode_superpowers`:**
  - `empty` → write `{"$schema":"https://opencode.ai/config.json","update":"disable","plugins":[$plugin]}`;
  - `v1` → `die` naming the file and `models/routing/opencode/eval/runtime/opencode-v2-adapter/convert-v1-config.sh`;
  - strict-JSON `v2` → the jq update on `.plugins`, same semantics as today's
    `.plugin`;
  - non-strict `v2` → today's exact-line check, never a rewrite;
  - `unparseable` → today's fail-closed `die`.
- **`opencode_superpowers_configured`:** `jq` checks `.plugins`, never `.plugin`.
- **`preflight_opencode_superpowers`:** dies on `v1`.

- [ ] **Step 1: Update and add tests in `tests/install.sh`.**
  - Existing fixtures that write `{"plugin":[…]}` become `{"plugins":[…]}`.
  - A fresh config contains `"update": "disable"` and `.plugins`, and has no
    `.plugin`.
  - Strict V1 `{"plugin":[…]}` makes configure die with `convert-v1-config` in
    the message, leaving the file unchanged.
  - **Review focus 1:** non-strict JSONC with a `// header`, a URL string
    containing `//`, `"agent": {}` and the pinned plugin line dies as `v1`. The
    old code accepted it.
  - Non-strict V2 JSONC with the pinned line on its own line is accepted
    unchanged.
  - Preflight dies on V1.
  - `SCRIPT_VERSION` is `0.5.0`.
- [ ] **Step 2: Run it.** `bash tests/install.sh`. Expected: FAIL on the new
  assertions.
- [ ] **Step 3: Implement it.** Every new mutation goes through the existing
  write path. Do not add direct writes outside it.
- [ ] **Step 4: Run** `bash tests/install.sh`, `bash -n environments/linux/install.sh`
  and `shellcheck environments/linux/install.sh tests/install.sh`.
  Expected: PASS, no findings.
- [ ] **Step 5: Commit.** `feat(installer)!: write the OpenCode 2 config shape for Superpowers`

### Task 9: Documentation and the full gate

**Files:**
- Modify: `models/routing/opencode/README.md`
- Modify: `docs/opencode-service.md` (Verification, and step 9 of "Moving an
  existing 1.x installation to 2.x")
- Modify: `models/routing/opencode/docs/decisions/2026-11-15-opencode-v2-adoption-rfc.md`
  (Follow-ups section only: mark 1 and 5 closed, with a link to the design)
- Modify: `AGENTS.md` (Repository Layout: one line for `models/routing/opencode/v2/`)

- [ ] **Step 1: Write the README sections.**
  - "OpenCode 2 (current)": the `v2/` layout and the workflow, in order:
    convert once, activate, check alignment, verify against the server, probe
    Breakglass. Give one runnable command each.
  - "V2 profile format": the contract a private generator targets. Cover
    routing-owned keys, the targets manifest format, `system` as the prompt key,
    the permission action map, and the rule that markdown never carries `model`.
  - "Removed in V2": temperature, with the reason from the spec; and
    `blacklist`, with the rule "a model you must not use is a model you do not
    declare".
  - "OpenCode 1.x (history)": where the V1 bundle and adapter are, and that
    they are not to be run against a 2.x host.
- [ ] **Step 2: Replace step 9's "one call per role" in the runbook.** It
  becomes `verify-effective-routing.sh --call`, with the lazy-loading note:
  poll; the first lookup can miss.
- [ ] **Step 3: Run the full gate** from the repository root:
  - `bash models/routing/opencode/eval/run-tests.sh --strict`;
  - `bash tests/install.sh`;
  - `bash tests/opencode-service.sh`;
  - shellcheck over every new or changed `.sh`;
  - `git ls-files -s models/routing/opencode/eval/runtime/opencode-v2-adapter`
    shows `100755` for the scripts;
  - `git diff origin/main --stat -- models/routing/opencode/eval/runtime/opencode-v1-adapter models/routing/opencode/opencode.jsonc models/routing/opencode/profiles models/routing/opencode/.opencode models/routing/opencode/eval/manifests models/routing/opencode/eval/records models/routing/opencode/eval/fixtures`
    prints nothing.

  Expected: all pass, and the last command prints nothing.
- [ ] **Step 4: Commit.** `docs(routing): document the OpenCode 2 routing workflow and profile format`
