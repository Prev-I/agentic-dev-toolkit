# OpenCode 2 per-role screening — Implementation Plan (Part 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run per-role model screenings on OpenCode 2.x the way the October
screenings ran on 1.x: one reusable runner, a sandboxed server per dispatch, and
role definitions for `reviewer` and `build`.

**Architecture:** The shared V1 pieces are ported into
`models/routing/opencode/eval/runtime/opencode-v2-adapter/` with their contracts
kept. A new `v2-sandbox.sh` builds a sandbox, starts `opencode serve` inside it,
checks its config layers and stops it. `dispatch-fixture.sh` runs one call
through a fresh sandbox server. `run-screening.sh` drives three phases:
`prepare`, then `dispatch` (after the operator's approval), then `score`. Each
role is a JSON definition that names its fixture, prompts, agent, extraction,
normaliser and scorer.

**Tech Stack:** Bash 5, Python 3 (stdlib only), jq, curl, OpenCode 2.3.0, and
the existing fakes under `eval/tests/fixtures-v2/`.

**Spec:** `docs/superpowers/specs/2026-11-21-opencode-v2-routing-alignment-design.md`,
section "Part 2 — per-role screening on OpenCode 2". Its "The V2 shape, as
measured" section lists the 2.x facts relied on here.

Paths below are relative to `models/routing/opencode/eval/` unless they start
with `models/` or `docs/`. `ADAPTER` = `runtime/opencode-v2-adapter`.

## Global Constraints

- Bash scripts start with `set -Eeuo pipefail`, are shellcheck clean (the
  `AGENTS.md` command covers `ADAPTER/*.sh`, `tests/v2-*-test.sh` and
  `tests/fixtures-v2/*.sh`), use LF line endings and are tracked `100755`.
  Python is stdlib only, run with `python3 -I -B` where it reads untrusted files.
- `bash models/routing/opencode/eval/run-tests.sh --strict` passes: every new
  test is `tests/v2-*-test.sh`, and every existing V1 test still passes.
- **V1 is history.** Nothing under `runtime/opencode-v1-adapter/`, `records/`,
  `fixtures/` or the V1 tests changes. Ported pieces are copies, never `source`s
  of V1 files.
- Company-neutral. No organisation, gateway or host name appears in any file.
  Test providers are called `fakep`.
- Secrets. The runner never prints a password or a credential. HTTP goes
  through `v2-http.sh` (password on curl's stdin). A credentials file is copied
  only into a sandbox, mode 600, and every sandbox is deleted when its dispatch
  ends, on success, failure or a signal. A record holds only the sha256 of the
  provider fragment and of the credentials file, never their content.
- Only measured 2.x behaviour is relied on. Measured for this plan on
  2026-11-21 on 2.3.0:
  - a 1.x-format `auth.json` in a fresh `XDG_DATA_HOME/opencode/` is imported
    into the database's `credential` table on first start;
  - `GET /api/model` lists each model with `variants: [{id, settings}]` and
    `cost`: a non-empty array for a priced model, `[]` for an unpriced one;
  - `$!` after `( cd D && env … opencode serve … ) &` is the subshell, not the
    server. Only `( cd D; exec setsid env … ) &` makes `$!` the server's pid,
    as `convert-v1-config.sh` does.
- Unmeasured; the runner tolerates both outcomes. Whether `GET /api/config`
  honours `?directory=`. The layer check queries it with and without, and both
  answers must pass.
- No model identifier in commit messages. Conventional commits.
- Branch `feat/opencode-v2-screening`. Integration is by PR (github-flow).

## Rulings made in this plan (spec silent or ambiguous)

1. **Order.** The runner runs `prepare` (protocol, catalog snapshot, freeze
   manifest), then the operator's approval, then `dispatch` (capability, runs),
   then `score` (normalise, scores, result skeleton). The spec lists the
   capability check before the freeze. This order freezes before any spend and
   gates spend on approval, as `opus55-gpt61-build-quality-screening` did. The
   spec says to follow that screening where the three differ.
2. **One dispatch path.** A `model:` candidate runs through a role agent row
   that the runner writes with the candidate's model, and every call uses
   `--agent`. This way a reviewer under test has reviewer permissions, not the
   default `build` agent's. `dispatch_fixture --model provider/model#variant`
   is still supported, as the spec requires, but the runner does not use it.
3. **Routing is verified per call.** After each call, `dispatch_fixture` reads
   the session's assistant messages and compares `v2config.assistant_uses`
   against the expected `agent@provider/model#variant`. A mismatch is the new
   classification `ROUTING_MISMATCH`. It replaces V1's grep for "Falling back to
   default agent".
4. **Credits.** credits = reported `cost` × 100, for any provider. `prepare`
   refuses a candidate whose model has `cost: []` in `GET /api/model`, because
   no cap could hold for it.
   - A call whose stream has no `step_start` costs 0.
   - A call with a `step_start` and no reported cost is "unknown cost". Unknown
     cost stops the screening.
5. **Stops.**
   - `CAPABILITY_REGRESSION`, or a failed capability probe, stops that
     candidate.
   - `BUDGET_STOP` or unknown cost stops the whole screening: the record is
     marked `INCOMPLETE` and the runner exits 1.
   - Every other non-OK run is recorded and the candidate continues.
6. **Budget.** `--budget` is split equally into one account per candidate,
   `candidate_<key>`. Admission per call is `cap / calls_per_candidate`. The
   in-flight stop is the account's remaining allowance.
7. **Record location.** `--out` may be anywhere outside the refused
   directories, and its basename must start with `v2-`. Scratch lives in
   `<out>/.work/` and is removed when the runner exits; `TMPDIR` points there.
8. **The build scorer** is a port of the record-local `verify-results-v2.py`
   plus the gate classifier from `verify-results.sh`. It becomes
   `scoring/build-quality-oc2.py`, which takes `--record` and `--repo`. The
   record-local originals stay unchanged.

## Review Focus

1. **The runner is interrupted** (Ctrl-C or TERM) mid-dispatch. Expected: the
   client and server process groups are stopped, `.work/` is removed, and no
   `auth.json` is left. Pinned in Task 5 (`interrupt_cleans_up`).
2. **Credentials leak into the record** after success or after a failed
   dispatch. Expected: no `auth.json`, no `*.db`, and the credential's token
   string appears in no record file. Pinned in Task 5 (`no_credential_in_record`).
3. **`dispatch` is re-run on a record that already has runs.** Expected:
   refused with exit 2 and nothing overwritten. Pinned in Task 5
   (`dispatch_twice_refused`).
4. **A candidate with an unknown variant, an unlisted model or an unpriced
   model.** Expected: `prepare` refuses it before any server call that could
   spend. Pinned in Task 5 (`prepare_refuses_unpriced_and_unknown`).
5. **The build scorer runs in a clone without the reference commits**, for
   example a shallow clone. Expected: it exits non-zero naming the missing
   commit, and writes no partial scores. Pinned in Task 4
   (`build_scorer_missing_commit_fails_closed`).

---

### Task 1: Port the server-free shared pieces

**Files:**
- Create: `ADAPTER/budget-ledger.sh`, `ADAPTER/provenance.sh`,
  `ADAPTER/classify-capability-failure.sh`, `ADAPTER/verify-freeze-manifest.sh`,
  `ADAPTER/capture-tree-patch.sh`
- Test: `tests/v2-screening-helpers-test.sh`

Sources are the same-named files in `runtime/opencode-v1-adapter/`. Copy each,
then apply only the changes listed in Step 3.

**Interfaces (produced):**
- `ledger_init LEDGER CAPS_JSON`: CAPS_JSON is an object `{account: cap}`.
  Writes `{"caps": CAPS, "entries": []}`. A no-op if LEDGER exists.
- `ledger_spent LEDGER ACCOUNT`, `ledger_admit LEDGER ACCOUNT PROJECTED`,
  `ledger_append LEDGER ACCOUNT LABEL PROVIDER CREDITS`: the V1 contracts, minus
  `--reclaim-recovery`.
- `ledger_credits_from_cost COST`: prints `COST*100`, or `null` when COST is
  empty or `null`. There is no provider argument (Ruling 4).
- `emit_run_record PROFILE_ID PROFILE_DIGEST COMMIT RUNTIME RUNNER PROVIDER MODEL VARIANT`
  prints one JSON object, with the V1 fields plus `profile_digest`. There is no
  `pricing_regime` argument; the field is `"opencode_reported"`.
- `classify_capability_failure PARSED_JSON` and `capability_stop_class CLASS`
  are unchanged from V1.
- `verify_freeze_manifest REPO_ROOT MANIFEST [RECORD_DIR]`. A `path` starting
  with `record:` resolves under RECORD_DIR; any other path resolves under
  REPO_ROOT and must stay inside it. Exits non-zero naming the first bad path.
- `write_freeze_manifest REPO_ROOT RECORD_DIR EXPERIMENT_ID OUT PATH...` writes
  `{"experiment_id", "status": "PRE_DISPATCH_FREEZE", "files": [{path, sha256}]}`.
  Each PATH is absolute; one inside RECORD_DIR is stored as `record:<rel>`, any
  other as REPO_ROOT-relative.
- `capture-tree-patch.sh BEFORE AFTER OUTPUT`: unchanged.

- [ ] **Step 1: Write the failing test** `tests/v2-screening-helpers-test.sh`,
  sourcing `tests/test-lib.sh`. Assertions:
  - `ledger_init` with `{"candidate_a": 10}`, then `ledger_append … 4.5`, then
    `ledger_spent` prints `4.5`. `ledger_admit … 5` succeeds and
    `ledger_admit … 6` fails.
  - `ledger_credits_from_cost 0.026` prints `2.6`;
    `ledger_credits_from_cost null` prints `null`.
  - `emit_run_record` output parses with jq. It has
    `.profile_digest == "d1"` and `.pricing_regime == "opencode_reported"`.
  - `write_freeze_manifest` over one repo file and one record file, then
    `verify_freeze_manifest` succeeds.
    - Change one byte of the record file and it fails with output containing
      `freeze digest mismatch: record:`.
    - A manifest path `../outside` fails with `invalid freeze path`.
  - `classify_capability_failure` on `{"error_text":"Model not found: x"}`
    prints `MODEL_UNRESOLVABLE`.
  - `capture-tree-patch.sh` on two directories that differ in one file writes a
    patch that `patch -p1` applies to a copy of BEFORE.
- [ ] **Step 2: Run** `bash tests/v2-screening-helpers-test.sh`. Expected: it
  fails, because the sources are missing.
- [ ] **Step 3: Create the five files.**
  - Each comment header says it is ported from the V1 file of the same name,
    for OpenCode 2, and what changed.
  - `budget-ledger.sh` sources `provenance.sh` from its own directory.
  - Credits are derived for every provider (Ruling 4).
- [ ] **Step 4: Run** the test and `shellcheck ADAPTER/*.sh tests/v2-screening-helpers-test.sh`.
  Expected: PASS and no findings.
- [ ] **Step 5: Commit** `feat(routing): port screening ledger, provenance and freeze helpers to OpenCode 2`.

### Task 2: Sandboxed server per dispatch

**Files:**
- Modify: `ADAPTER/v2config.py`. Add `check_layers` and the `layers` and
  `build-config` commands.
- Modify: `ADAPTER/convert-v1-config.sh`. `_cv_py document` calls
  `v2config.check_layers` instead of its inline loop, with unchanged behaviour
  and messages.
- Create: `ADAPTER/v2-sandbox.sh`, `tests/fixtures-v2/fake-opencode-screening.sh`
- Test: `tests/v2-sandbox-test.sh`

**Interfaces (produced):**
- `v2config.check_layers(layers: list, sandbox: str) -> list[str]` returns the
  problems, empty when clean. It uses the rule from the converter: each layer
  must be inside the sandbox, or be the account's `~/.opencode` holding none of
  `opencode.json`, `opencode.jsonc`, `agents`, `agent`, `command`, `plugins`.
  `v2config.py layers API_CONFIG_JSON SANDBOX` exits 0 when clean, and 1 with
  one `  - <problem>` line per problem on stderr.
- `v2config.py build-config BASE_JSON_OR_- FRAGMENT AGENT_ROW_JSON_OR_- OUT`:
  - BASE is a loaded profile, or `-` for the minimal
    `{"$schema": "https://opencode.ai/config.json", "update": "disable"}`.
  - FRAGMENT may hold only `providers` and `policies`; any other key exits 2.
    Its `providers` are merged over the base's, and its `policies` are appended.
  - AGENT_ROW is `{"name": N, "row": {...}}`, placed at `agents.N`.
  - The result always has `"update": "disable"`. It is written as strict JSON.
- `v2config.py real-dirs` prints, one per line, the directories a sandbox must
  not resolve inside:
  - the account home's `.config/opencode`, `.local/share/opencode`,
    `.local/state/opencode` and `.opencode`, from `pwd.getpwuid`;
  - plus `$XDG_CONFIG_HOME/opencode`, `$XDG_DATA_HOME/opencode` and
    `$XDG_STATE_HOME/opencode` when those variables are set.
- `ADAPTER/v2-sandbox.sh`, to be sourced; it sources `v2-run.sh`:
  - `v2_sandbox_create PARENT` prints a new sandbox directory under PARENT,
    with `home config/opencode data/opencode state cache work` inside.
    Returns 2 if PARENT resolves inside, or equal to, any `real-dirs` entry.
  - `v2_sandbox_populate SANDBOX CONFIG_JSON CREDENTIALS [OPENCODE_DIR]`:
    - copies the config to `config/opencode/opencode.json`;
    - copies the credentials to `data/opencode/auth.json` with mode 600;
    - copies `OPENCODE_DIR/agents/*.md` and `OPENCODE_DIR/model-routing.md`
      into `config/opencode/` when given;
    - then, if the config has `instructions`, rewrites it to the single
      absolute path `SANDBOX/config/opencode/model-routing.md`, as activation
      does on a real host.
  - `v2_sandbox_serve SANDBOX`:
    - starts `( cd SANDBOX/work; exec setsid env -i … "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port P ) &`.
      The env allowlist is `PATH=/usr/bin:/bin`, the sandbox `HOME` and
      `XDG_*`, `OPENCODE_PASSWORD` and `OPENCODE_SERVER_PASSWORD` set to a fresh
      random 32-character alphanumeric password, `OPENCODE_DISABLE_AUTOUPDATE=1`,
      `OPENCODE_DISABLE_PROJECT_CONFIG=1`, `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`
      and `OPENCODE_DISABLE_EXTERNAL_SKILLS=1`.
    - Appends the pid to `_V2_PIDS` and polls `GET /api/config` (bound
      `V2_CONFIG_POLL_TIMEOUT`, default 30 s).
    - Runs `check_layers` on the answer without `directory` and with
      `?directory=<SANDBOX/work>`.
    - Writes `SANDBOX/layers.json` (both answers), `SANDBOX/version` (from
      `GET /api/info`), `SANDBOX/url` and `SANDBOX/pid`.
    - Returns 0, or 1 with a message: early exit, auth refused, timeout, or
      layers refused.
  - `v2_sandbox_destroy SANDBOX` runs `v2_stop_pid "$(cat SANDBOX/pid)"`, then
    `rm -rf SANDBOX`. It is idempotent.
- `fake-opencode-screening.sh`, a test double. Tests reach it through a
  generated wrapper that bakes `FAKE_SCREEN_STATE=<dir>` and execs it, because
  `env -i` strips the environment.
  - `serve`: like `fake-opencode-serve.sh`, it writes `api_config.json` layers
    (the config document plus the cwd), `api_info.json` (`2.3.0-fake`) and
    `api_model.json` from `$FAKE_SCREEN_STATE/models.json`. It execs
    `fake-api.py`, and appends `serve pid=$$ cwd=$PWD home=$HOME` to
    `$FAKE_SCREEN_STATE/log`.
  - `FAKE_SCREEN_STATE/mode` containing `leak` adds a layer
    `/etc/opencode-outside`.

- [ ] **Step 1: Write the failing test** `tests/v2-sandbox-test.sh`:
  - `layers_clean_and_leak`: `v2config.py layers` exits 0 on
    `[{"path":"<sb>/config/opencode/opencode.json","type":"document"},{"path":"<sb>/work","type":"directory"}]`.
    It exits 1 when a layer `/etc/x` is added, and stderr contains
    `/etc/x (directory) is outside the sandbox`.
  - `build_config_minimal`: from base `-`, a fragment with `providers.fakep`
    and a row `{"name":"screening-reviewer","row":{"mode":"primary"}}`, the
    output has `.update == "disable"`,
    `.agents["screening-reviewer"].mode == "primary"` and `.providers.fakep`.
  - `build_config_rejects_fragment_keys`: a fragment holding `agents` exits 2.
  - `populate_rewrites_instructions`: a config with
    `"instructions": [".opencode/model-routing.md"]` and
    `OPENCODE_DIR=models/routing/opencode/v2/.opencode` gives
    `.instructions == ["<SANDBOX>/config/opencode/model-routing.md"]`.
    `config/opencode/agents/reviewer.md` exists, and `auth.json` has mode 600.
  - `create_refuses_real_dirs`: with `XDG_CONFIG_HOME=$work/xdg`,
    `v2_sandbox_create "$work/xdg/opencode/x"` returns 2.
  - `serve_and_destroy`, through the fake wrapper:
    - `SANDBOX/layers.json`, `SANDBOX/version` and `SANDBOX/url` exist;
    - the log line's `cwd` equals `SANDBOX/work` and its `home` equals
      `SANDBOX/home`;
    - the logged pid equals `SANDBOX/pid`;
    - after `v2_sandbox_destroy`, that pid is gone and SANDBOX is removed.
  - `serve_refuses_leak`: with mode `leak`, `v2_sandbox_serve` returns 1, its
    stderr names `/etc/opencode-outside`, and destroy leaves no process.
  - The existing `tests/v2-convert-test.sh` still passes, unchanged.
- [ ] **Step 2: Run** `bash tests/v2-sandbox-test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above. Model `v2_sandbox_serve` on
  `_cv_serve` in `convert-v1-config.sh`.
- [ ] **Step 4: Run** `bash tests/v2-sandbox-test.sh && bash tests/v2-convert-test.sh`
  and shellcheck. Expected: PASS and no findings.
- [ ] **Step 5: Commit** `feat(routing): sandboxed OpenCode 2 server for screening dispatch`.

### Task 3: Capped client, dispatch and capability probe

**Files:**
- Create: `ADAPTER/capped-opencode.sh`, `ADAPTER/dispatch-fixture.sh`,
  `ADAPTER/capability-probe.sh`
- Modify: `tests/fixtures-v2/fake-opencode-screening.sh` to add `run`
- Test: `tests/v2-dispatch-test.sh`

**Interfaces:**
- Consumes: Task 1 (ledger, provenance, classify) and Task 2 (`v2_sandbox_*`).
- `capped-opencode.sh ARGS…` is V1's wrapper. Differences:
  - besides `EVAL_CALL_STOP_CREDITS`, it reads `EVAL_SERVER_PID`;
  - on a budget stop and on TERM or INT, it stops the client's process group
    and then `EVAL_SERVER_PID`'s group;
  - it prints `EVAL_BUDGET_STOP: completed-step cost reached <N> credits` to
    stderr and exits 143, as V1 does.
- `dispatch_fixture` takes V1's options (except `--variant`), plus:
  - `--sandbox-parent DIR`, required: the sandbox is created there and
    destroyed before return;
  - `--config FILE`, required: the full sandbox config, from
    `v2config.py build-config`;
  - `--credentials FILE`, required;
  - `--opencode-dir DIR`, optional;
  - `--expect USE`, the expected `agent@provider/model#variant`. When absent
    for `--agent`, it is resolved from `v2_agent_get` before the call;
  - `--profile-id ID` and `--profile-digest SHA`, both optional;
  - `--stop-credits N`, optional. When given, the call runs through
    `capped-opencode.sh`.

  `--model` takes `provider/model#variant`.
- Flow:
  1. Create, populate and serve the sandbox.
  2. Copy the `--workspace` contents into `SANDBOX/work`; the call's cwd is
     `SANDBOX/work`.
  3. For `--agent`, poll `v2_agent_get URL AGENT SANDBOX/work` (lazy load).
  4. Run `timeout --preserve-status T [capped] "$OPENCODE_BIN" --server URL run (--agent A | --model M) --format json --archived --auto "$prompt"`,
     with the client's own `XDG_*` under the sandbox and `OPENCODE_PASSWORD`.
  5. Parse the stream as V1 does. Fetch `GET /api/session/<sid>/message`,
     filter it with `V2_PICK_ASSISTANT` into `OUTDIR/assistant.json`, and set
     `routing_observed = assistant_uses(...)`.
  6. When `--workspace-out DIR` is given, copy `SANDBOX/work` there before
     destroying the sandbox. The build role uses this for the patch.
  7. Destroy the sandbox. A trap destroys it on any exit path.
- Classification, in order:
  1. `BUDGET_STOP`
  2. `TIMEOUT` (exit 124, 137 or 143)
  3. `CAPABILITY_REGRESSION` or `INVALID_ENVIRONMENT` (non-zero exit)
  4. `ROUTING_MISMATCH` (`routing_observed` is not exactly `[expected]`)
  5. `EMPTY_RESPONSE`
  6. `OK`

  A sandbox serve failure is `INVALID_ENVIRONMENT` with `failure_class: "SANDBOX_REFUSED"`.
- `dispatch.json`, which V1 tests read, keeps every V1 field and adds:
  - `profile_digest`;
  - `routing_expected` and `routing_observed`;
  - `server_layers`, the content of `layers.json`;
  - `cost_known` (bool).

  It sets `eval_runner_version: "oc2-dispatch-v1"`. `runtime_version` is the
  server's `/api/info` version. `routing_profile_id` is `--profile-id`, or
  `direct-model-evaluation` when that is absent.
- Credits follow Ruling 4. Unknown cost writes `derived_credits: null` and
  `cost_known: false`. Known cost is appended to `--ledger` even when the call
  failed.
- `dispatch_extract_json OUTDIR`, `dispatch_classification OUTDIR` and
  `dispatch_response_text OUTDIR` are unchanged.
- `v2_capability_probe OUTDIR KEY DISPATCH_OPTION…` calls `dispatch_fixture`
  with the given options (sandbox parent, config, credentials, agent, expect,
  ledger, account, profile, stop credits), plus `--outdir OUTDIR/dispatch`,
  `--label capability-KEY`, a prompt file holding exactly
  `Reply with exactly: CAPABILITY_OK` and `--timeout 120`. It writes `OUTDIR/probe.json` with `{key, classification: USABLE|<dispatch classification>|WRONG_RESPONSE}`.
  It returns 0 only for USABLE: dispatch OK and a stripped response equal to
  `CAPABILITY_OK`.
- Fake `run`. It reads `$FAKE_SCREEN_STATE/scenario.json`, keyed by the
  `--agent` value (or `--model`), with fields:
  - `text`;
  - `cost_per_step`, `steps`, `step_sleep`;
  - `exit`, `error_message`;
  - `observed_model` (`{providerID, id, variant}`);
  - `write_file` (`{path, content}`, written into its cwd).

  It emits 2.x JSONL (`step_start`, `tool_use`, `step_finish`, `text`, or
  `error` with `error.data.message`) under `sessionID` `ses_<n>`. It writes
  `api_session_ses_<n>_message.json` into the fake server's fixture directory,
  with one assistant message carrying `agent` and `model`. It logs
  `run cwd=$PWD xdg_config=$XDG_CONFIG_HOME` to the state log.

- [ ] **Step 1: Write the failing test** `tests/v2-dispatch-test.sh`:
  - `dispatch_ok`:
    - classification `OK`;
    - `derived_credits == 5.2` (2 steps × 0.026 × 100);
    - `routing_observed == ["screening-reviewer@fakep/m1#high"]`;
    - `runtime_version == "2.3.0-fake"`;
    - the ledger has one entry of 5.2;
    - the logged run cwd ends in `/work` under the sandbox parent;
    - the sandbox parent is empty afterwards.
  - `dispatch_routing_mismatch`: `observed_model` set to variant `low` gives
    `ROUTING_MISMATCH`.
  - `dispatch_capability_failure`: `exit: 1` with
    `error_message: "Model not found: fakep/nope"` gives
    `CAPABILITY_REGRESSION` and `failure_class: MODEL_UNRESOLVABLE`.
  - `dispatch_budget_stop`:
    - `steps: 20`, `step_sleep: 0.3`, `cost_per_step: 0.05` and
      `--stop-credits 12` give `BUDGET_STOP`;
    - the recorded server pid is gone within 3 s of return;
    - the ledger total is ≥ 12.
  - `dispatch_timeout_kills_server`: `--timeout 2` with a 10-step 1 s fake
    gives `TIMEOUT`, and both the client and the server pid are gone.
  - `dispatch_unknown_cost`: a stream with `step_start` and `text` but no
    `step_finish` gives `cost_known == false` and adds no ledger entry.
  - `dispatch_model_flag`: `--model fakep/m1#high` produces argv containing
    `[--model] [fakep/m1#high]` and no `--variant`.
  - `probe_usable_and_wrong`: text `CAPABILITY_OK` returns 0 with `USABLE`;
    text `ok` returns 1 with `WRONG_RESPONSE`.
  - `workspace_out`: `write_file` `{"path":"lib/new.sh"}` appears in
    `--workspace-out`.
- [ ] **Step 2: Run** `bash tests/v2-dispatch-test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** the test, `bash tests/v2-sandbox-test.sh` and
  shellcheck. Expected: PASS and no findings.
- [ ] **Step 5: Commit** `feat(routing): OpenCode 2 dispatch with per-call server, budget stop and routing check`.

### Task 4: Role definitions, normaliser and build scorer

**Files:**
- Create: `ADAPTER/roles/reviewer.json`, `ADAPTER/roles/build.json`, and
  `ADAPTER/roles/reviewer/request.txt` (a byte copy of
  `records/reviewer-cross-family-screening/reviewer-request.txt`).
- Create: `ADAPTER/roles/build/coding-prompt.txt` and
  `ADAPTER/roles/build/gate-prompt.txt` (byte copies from
  `records/opus55-gpt61-build-quality-screening/`).
- Create: `scoring/reviewer-normalise-oc2.py` and `scoring/build-quality-oc2.py`.
- Test: `tests/v2-roles-test.sh`

**Interfaces (produced).** The role definition schema, which Task 5 consumes.
All paths are toolkit-root-relative.

```json
{
  "role": "reviewer",
  "fixture": "models/routing/opencode/eval/fixtures/reviewer-seeded-defects-v2",
  "agent": {
    "name": "screening-reviewer",
    "markdown": "models/routing/opencode/v2/.opencode/agents/reviewer.md",
    "mode": "primary",
    "permissions_append": [
      {"action": "webfetch", "resource": "*", "effect": "deny"},
      {"action": "websearch", "resource": "*", "effect": "deny"}
    ]
  },
  "workloads": [
    {"id": "clean", "base": "{fixture}/clean", "overlay": [], "prompt": "…/roles/reviewer/request.txt"},
    {"id": "R-API", "base": "{fixture}/clean", "overlay": ["{fixture}/cases/R-API/api.sh"], "prompt": "…"}
  ],
  "extract": "json",
  "capture_patch": false,
  "timeout_seconds": 480,
  "normalise": {"per": "candidate-run", "argv": ["python3", "-I", "-B", "{eval}/scoring/reviewer-normalise-oc2.py", "{record}", "{fixture}", "{key}", "{rep}"]},
  "score": {"per": "candidate-run", "argv": ["python3", "-I", "-B", "{eval}/scoring/reviewer-v2.py", "{fixture}", "{record}/findings-{key}-r{rep}.json"], "stdout": "scores/{key}-r{rep}.json"},
  "frozen": ["{fixture}", "{eval}/scoring/reviewer-v2.py", "{eval}/scoring/reviewer-normalise-oc2.py"]
}
```

- `reviewer.json` has 6 workloads: `clean`, plus one per seeded case in
  `oracle.json` `expected_ids` order. Each case overlays its `ground-truth.json`
  `overrides` files.
- The agent row is built as follows:
  - the markdown's frontmatter `permissions`, plus `permissions_append`;
  - `system` set to the markdown body;
  - `mode` from the definition;
  - `model` set by the runner per candidate.
- `build.json`:
  - agent `screening-build`, `mode: primary`, no markdown, `system` absent;
  - permissions: allow `*` on `*`, then deny `subagent` `*`, `webfetch` `*`
    and `websearch` `*`;
  - workloads:
    - `coding`: base `{eval}/records/astra-build-followup/base-snapshot`,
      prompt `coding-prompt.txt`;
    - `gate`: base `{eval}/fixtures/build-workloads/build-feature/snapshot`,
      prompt `gate-prompt.txt`;
  - `extract: "none"`, `capture_patch: true`, `timeout_seconds: 480`;
  - `normalise: null`;
  - score `{"per": "record", "argv": ["/usr/bin/python3", "-I", "-B", "{eval}/scoring/build-quality-oc2.py", "--record", "{record}", "--repo", "{repo}"], "stdout": null}`;
  - `frozen` lists both bases, the prompts and the scorer.
- `reviewer-normalise-oc2.py RECORD FIXTURE KEY REP` ports
  `records/reviewer-cross-family-screening/normalize-results.sh`'s Python for
  one key and repetition. It reads `runs/*-<case>-r<REP>-<KEY>/reported.json`
  and writes `RECORD/findings-<KEY>-r<REP>.json` in the same document shape,
  with `scorer: "eval/scoring/reviewer-v2.py"`. A missing `reported.json`
  counts as zero findings and is listed in `missing_runs`.
- `build-quality-oc2.py --record R --repo REPO [--out R/post-run-diagnostic]`
  ports `verify-results-v2.py`:
  - the same controls (REFERENCE and BROKEN commits, read with `git show` in
    REPO) and the same per-patch checks over `runs/*-coding-*/work-product.patch`;
  - plus V1's `classify_gate` regex over `runs/*-gate-*` (response at
    `dispatch/response.txt`, patch at `work-product.patch`);
  - writes `R/scores/build-quality.json` as
    `{"classification": "POST_RUN_DIAGNOSTIC", "adjudicates": false, "controls_passed", "coding": [...], "gate": [{label, verdict}]}`;
  - exits 1 without writing scores when a reference commit is not available
    (message `reference commit not available: <sha>`) or a control fails.

- [ ] **Step 1: Write the failing test** `tests/v2-roles-test.sh`:
  - `role_files_valid`:
    - both JSON files parse;
    - every `{fixture}`/`{eval}` path they name exists;
    - the reviewer's workload ids equal `["clean"] + expected_ids`;
    - each overlay basename is in its case's `overrides`;
    - `cmp` holds between each copied prompt and its October original.
  - `normalise_and_score_reviewer`: on a synthetic record whose six
    `reported.json` files each carry one material finding quoting the case's
    witness (clean: `[]`), the normaliser and then `reviewer-v2.py` give
    `gate == "pass"`. Dropping the R-API report gives
    `attribution["R-API"] == "missed"`, `gate == "block"`, and `missing_runs`
    lists it.
  - `build_scorer_missing_commit_fails_closed`: `--repo` pointing at a fresh
    `git init` exits 1, stderr contains `reference commit not available`, and
    no `scores/` exists.
  - `build_gate_classifier`: an empty patch with a response asking "Should I
    proceed" gives `ADHERENT`; a non-empty patch gives `NON_ADHERENT`. Call the
    module's gate function directly, so the controls do not run.
- [ ] **Step 2: Run** `bash tests/v2-roles-test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Run** the test. Expected: PASS. Also run
  `bash tests/build-verifier-v2-test.sh`, which shows the October verifier is
  untouched.
- [ ] **Step 5: Commit** `feat(routing): reviewer and build role definitions for OpenCode 2 screening`.

### Task 5: The screening runner, and docs

**Files:**
- Create: `ADAPTER/run-screening.sh`
- Test: `tests/v2-screening-runner-test.sh`
- Modify: `models/routing/opencode/README.md` (a section "Screening a model on
  OpenCode 2"), `AGENTS.md` (layout line for the adapter's screening runner),
  and the spec's Part 2 bullet "Unmeasured, measure first". That bullet gets an
  appended "Measured 2026-11-21:" line with the credential-import result; the
  rest of the spec is not edited.

**Interfaces:**
- Consumes: Tasks 1–4.
- `run-screening.sh prepare --role ROLE --out DIR --candidate KEY=SPEC… --runs N --budget CREDITS --providers FILE --credentials FILE [--profile FILE --profile-id ID] [--opencode-dir DIR] [--timeout S]`
  - SPEC is `model:PROVIDER/MODEL#VARIANT`, or `agent:NAME`, which requires
    `--profile`.
  - KEY matches `^[a-z0-9][a-z0-9-]{0,23}$`, and keys are unique.
  - `--opencode-dir` defaults to `models/routing/opencode/v2/.opencode`.
  - Exit 2: usage error, an existing `DIR`, a basename not starting with `v2-`,
    or `DIR` inside a real dir.
  - Writes `protocol.json`:
    - `experiment_id` (`<basename>-<UTC date>`), `status_at_freeze: "AWAITING_APPROVAL"`;
    - `role`, `role_definition`, `candidates` (key, spec, account, expect);
    - `runs`, `order`, `timeout_seconds`;
    - `budget`: `ceiling_credits`, `per_candidate_cap`, `admission_per_call`;
    - `providers_sha256`, `credentials_sha256`, `profile_id`, `profile_digest`;
    - `runtime_version`, `toolkit_commit`.
  - Writes `catalog-snapshot.json` from one sandbox server, with no model
    call: `{runtime_version, captured_at, models: {"p/m": {variants, cost}}}`
    for the candidates' providers.
  - Refuses with exit 1 an unlisted model, an unknown variant, or `cost == []`.
  - Writes `freeze-manifest.json` over:
    - the role definition and the adapter's `*.sh` and `v2config.py`;
    - every `frozen` path;
    - `record:protocol.json` and `record:catalog-snapshot.json`.
  - Prints the exact `approval.json` the operator must write:
    `{experiment_id, status: "APPROVED_FOR_DISPATCH", approved_ceiling_credits, freeze_manifest_sha256}`.
- `run-screening.sh dispatch --out DIR --providers FILE --credentials FILE [--profile FILE]`:
  - Exit 3 when `approval.json` is not exactly that object. The provider and
    credential digests and the profile digest must match the protocol, else
    exit 3.
  - Exit 2 when `runs/` or `capability/` already exist.
  - `verify_freeze_manifest` runs before every dispatch; a mismatch exits 1.
  - Builds each candidate's config with `build-config`. A model candidate
    gets the role agent row with its model; an agent candidate gets the
    profile alone.
  - Probes each candidate into `capability/<key>/`. A failed probe marks the
    candidate `STOPPED_CAPABILITY` in `ledger.json`'s sibling `status.json`.
  - Then for rep in 1..N, and for each workload in definition order, it runs
    the live candidates. The candidate order alternates by
    `(rep + workload_index) % 2`, as the October interleaving did.
  - Labels are `NN-<workload>-r<rep>-<key>`; outputs go to
    `runs/<label>/dispatch/`.
  - `extract: json` writes `runs/<label>/reported.json`; on failure it writes
    `extract-error.txt`.
  - `capture_patch` writes `runs/<label>/work-product.patch` from the base
    against `--workspace-out`.
  - Applies Ruling 5. Ends by writing `status.json`
    `{state: COMPLETE|INCOMPLETE, stopped: {...}}`; exit 0 when COMPLETE,
    1 when INCOMPLETE.
- `run-screening.sh score --out DIR`:
  - runs `normalise` and `score` per the definition, with placeholders
    `{eval} {repo} {record} {fixture} {key} {rep}`;
  - writes `result.md`, with headings Protocol, Candidates, Spend (from the
    ledger), Capability, Scores (one table row per candidate and repetition,
    from `scores/`), and Adjudication, which says "Operator: not yet
    adjudicated".
  - It never writes `adjudication.json`.
- The runner sets `TMPDIR=<out>/.work` and passes `--sandbox-parent <out>/.work`.
  An EXIT, INT and TERM trap removes `.work`.

- [ ] **Step 1: Write the failing test** `tests/v2-screening-runner-test.sh`,
  using the fake wrapper. The provider is `fakep`, with models `m1` and `m2`
  priced and `m3` unpriced. Each case:
  - `full_two_candidate_reviewer_run`:
    - prepare, write the printed approval, dispatch, score;
    - exit 0;
    - 2 capability dirs and 12 run dirs (6 workloads × 2 candidates × 1 run);
    - `scores/a-r1.json` and `scores/b-r1.json` exist;
    - `result.md` contains `Operator: not yet adjudicated`;
    - every `dispatch.json` has `routing_observed` equal to `[routing_expected]`.
  - `capability_failure_stops_candidate`: candidate `b`'s probe errors with
    `Model not found`. Exit 0; no `runs/*-b`; `status.json.stopped.b == "STOPPED_CAPABILITY"`;
    `a`'s 6 runs exist.
  - `budget_stop_halts_screening`: a fake costing 0.5 per step over 10 steps,
    with `--budget 30`. Exit 1, `status.json.state == "INCOMPLETE"`, and no
    run dispatched after the stopped one.
  - `freeze_mismatch_refuses`: after prepare and approval, append a byte to
    `record/protocol.json`. Dispatch exits 1 with
    `freeze digest mismatch: record:protocol.json`, and no `runs/` exists.
  - `approval_mismatch_refuses`: `approved_ceiling_credits` differing by 1
    exits 3.
  - `prepare_refuses_unpriced_and_unknown`: `model:fakep/m3#high` (unpriced),
    `model:fakep/m1#ultra` (unknown variant) and `model:fakep/zz#high`
    (unlisted) each exit 1, and the fake log shows no `run` line.
  - `dispatch_twice_refused`: a second `dispatch` exits 2, and the run files'
    mtimes are unchanged.
  - `isolation_writes_only_record`:
    - run with `HOME=$work/home` (pre-populated with a marker file) and
      `TMPDIR=$work/tmp`;
    - afterwards `$work/home` holds only the marker and `$work/tmp` is empty;
    - every `home=`, `cwd=` and `xdg_config=` path in the fake log is under the
      record's `.work/`;
    - `create_refuses_real_dirs` is covered in Task 2.
  - `no_credential_in_record`: the credentials file holds the token
    `tok-SECRET-123`. After a full run and after a run that failed on
    capability, `grep -r tok-SECRET-123 record` finds nothing, and
    `find record -name auth.json -o -name '*.db'` is empty.
  - `interrupt_cleans_up`: start dispatch with a 20-step, 0.5 s fake and send
    TERM after the first serve log line. The runner exits non-zero, no fake
    server pid from the log is alive, and `record/.work` is absent.
  - `build_role_captures_patch`: role `build` with a fake that writes
    `lib/strings.sh` for `gate`. `runs/*-gate-r1-a/work-product.patch` contains
    `lib/strings.sh`. `score` is not run here; Task 4 covers the build scorer.
- [ ] **Step 2: Run** `bash tests/v2-screening-runner-test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `run-screening.sh` per the interfaces, then write
  the README section. The section covers:
  - the three phases and the approval step;
  - what the operator supplies (provider fragment, credentials, optional
    profile) and why: they are deployment-specific;
  - the isolation guarantees and the layer check;
  - the record layout;
  - the rulings that affect operators (5 and 6).
- [ ] **Step 4: Run**
  `bash models/routing/opencode/eval/run-tests.sh --strict` and the
  `AGENTS.md` shellcheck command. Expected: every suite passes, none is
  skipped, and shellcheck has no findings.
- [ ] **Step 5: Commit**
  `feat(routing): per-role screening runner for OpenCode 2`, then
  `docs(routing): document screening on OpenCode 2`.
