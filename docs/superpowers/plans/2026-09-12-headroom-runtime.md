# Headroom Runtime Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, reproducible Headroom 0.37.0 runtime installer, non-destructive auditor, safe removal path, and operational documentation without integrating Headroom with OpenCode.

**Architecture:** A single strict-mode Bash CLI delegates package installation to uv and persistent-service generation to Headroom's upstream CLI. It owns policy and validation, not generated service artifacts: fixture-driven tests replace every host command and path, while component-local documentation records runtime `TRIAL`, plugin `HOLD`, known findings, rollback, upgrades, and the independent Telegram failure.

**Tech Stack:** Bash 4.4+, uv, Headroom 0.37.0, jq, curl, systemd user services, ss/iproute2, fixture command stubs, Markdown.

**Spec:** `docs/superpowers/specs/2026-09-12-headroom-runtime-design.md`

## Global Constraints

- Work only in the isolated `feat/headroom-runtime` worktree based on `main`; do not modify the dirty `feat/software-catalog` checkout.
- Headroom is standalone and opt-in; do not modify `environments/linux/install.sh` or depend on the unmerged software catalog.
- Pin `headroom-ai[proxy]==0.37.0` and request Python `3.13`; do not use `[all]` or `[ml]`.
- The persistent apply command uses `--scope provider --providers manual` with no `--target`; that absence is intentional and load-bearing.
- Never invoke `headroom deploy`, `headroom wrap opencode`, provider auto-selection, MCP, Serena, memory, learn, or OpenCode routing changes.
- Upstream-generated `~/.config/systemd/user/headroom-default.service` and `~/.headroom/deploy/default/*` are runtime artifacts, not committed source.
- OpenCode guards detect Headroom coupling but do not impose JSON versus JSONC ownership and never edit OpenCode.
- `audit` is non-destructive and uses `PASS`/`WARN`/`FAIL`/`ERROR` with exits `0`/`0`/`1`/`2`.
- Optional Kompress degradation, lifecycle exit 241, and generated permission observations are warnings, not runtime failures.
- Telegram is not queried by generic Headroom tooling; its known HTTP 409 duplicate-poller defect is independent evidence only.
- All mutating commands pass through `run`; `--dry-run` performs bounded read-only inspection and executes no mutation.
- Production script mode is `100755`; test entry point mode is `100644` and is invoked with Bash.
- No secrets, raw environment dumps, machine identifiers, PIDs, usernames, credentials, or host-specific absolute home paths enter committed files.

## File Map

| Path | Responsibility |
|---|---|
| `headroom-runtime/headroom-runtime.sh` | Versioned CLI, command resolution, policy checks, audit rendering, install orchestration, removal |
| `headroom-runtime/README.md` | Component quick start, command/status contract, file map |
| `headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md` | Sanitized validation facts, known findings, causal Telegram result |
| `headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md` | Plugin hold decision and future qualification matrix |
| `docs/headroom-runtime.md` | Full install/audit/WSL/rollback/upgrade runbook |
| `tests/headroom-runtime.sh` | End-to-end fixture suite with command/path stubs |
| `README.md` | Add opt-in component to public overview and repository layout |
| `AGENTS.md` | Add component invariants and sixth suite/syntax/ShellCheck commands |

---

### Task 1: CLI Foundation And Fixture Harness

**Files:**
- Create: `headroom-runtime/headroom-runtime.sh`
- Create: `tests/headroom-runtime.sh`

**Interfaces:**
- Produces CLI commands: `install`, `audit`, `remove`, `--help`, `--version`;
  Task 1 implements argument validation and temporary command handlers that
  resolve only the binaries each command needs, then return 0 without mutation.
- Produces constants: `SCRIPT_VERSION=0.1.2`, `HEADROOM_VERSION=0.37.0`, `HEADROOM_PYTHON=3.13`, `HEADROOM_PROFILE=default`, `HEADROOM_PORT=8787`.
- Produces mutation wrapper: `run COMMAND...`, controlled by `DRY_RUN`.
- Produces validated executable variables: `UV_BIN`, `HEADROOM_BIN`,
  `SYSTEMCTL_BIN`, `CURL_BIN`, `JQ_BIN`, `SS_BIN`, `UNAME_BIN`, and
  `SLEEP_BIN` from absolute `HRT_*_BIN` overrides or absolute resolved
  defaults.
- Produces `UPTIME_FILE` from the read-only `HRT_UPTIME_FILE` seam, defaulting
  to `/proc/uptime`.
- Test harness produces `new_case NAME`, isolated case roots, executable stubs,
  captured status/output, and command logs used by Tasks 2-4.
  `new_conforming_case NAME` is added in Task 2 after the audit fixture shape
  exists.

- [ ] **Step 1: Write failing tests for the public CLI and safe command seams**

Add repository-style `fail`, `assert_equal`, `assert_contains`, cleanup,
`new_case`, and `run_cli` helpers to `tests/headroom-runtime.sh`. `run_cli`
captures stdout and stderr together with `2>&1`, matching the existing service
suite. Add tests that assert:

```bash
test_version_is_exact() {
  new_case version
  run_cli --version
  assert_equal "$CLI_STATUS" "0" "--version must succeed"
  assert_equal "$CLI_OUTPUT" "0.1.2" "--version must print only the tool version"
}

test_help_lists_the_three_commands() {
  new_case help
  run_cli --help
  assert_equal "$CLI_STATUS" "0" "--help must succeed"
  assert_contains "$CLI_OUTPUT" "install [--dry-run]" "help must document install"
  assert_contains "$CLI_OUTPUT" "audit [--json]" "help must document audit"
  assert_contains "$CLI_OUTPUT" "remove [--dry-run] [--uninstall-tool]" \
    "help must document remove"
}

test_unknown_command_is_usage_error() {
  new_case unknown
  run_cli unknown
  assert_equal "$CLI_STATUS" "2" "unknown commands must exit 2"
}

test_relative_binary_override_is_rejected() {
  new_case relative-override
  export HRT_UV_BIN=relative/uv
  run_cli install --dry-run
  unset HRT_UV_BIN
  assert_equal "$CLI_STATUS" "2" "executable seams must be absolute"
  assert_contains "$CLI_OUTPUT" "HRT_UV_BIN must be an absolute executable path" \
    "the diagnostic must identify the unsafe seam"
}
```

The harness must set all `HRT_*` roots to the fixture and all executable seams
except jq to absolute stub paths, so no test can reach the real machine. Resolve
the real jq once with `command -v jq`, require it to be available, canonicalize
it with `readlink -f`, and pass that absolute path as `HRT_JQ_BIN`; malformed
JSON cases use jq's real parser.

- [ ] **Step 2: Run the focused suite and verify the expected failure**

Run:

```bash
bash tests/headroom-runtime.sh
```

Expected: fail because `headroom-runtime/headroom-runtime.sh` does not exist.

- [ ] **Step 3: Implement the minimal CLI parser and command resolution**

Create `headroom-runtime/headroom-runtime.sh` with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="0.1.2"
readonly HEADROOM_VERSION="0.37.0"
readonly HEADROOM_PYTHON="3.13"
readonly HEADROOM_PROFILE="default"
readonly HEADROOM_PORT="8787"
readonly HEADROOM_PACKAGE="headroom-ai[proxy]==${HEADROOM_VERSION}"

DRY_RUN=0
JSON_MODE=0
UNINSTALL_TOOL=0
```

Implement these top-level functions with no nested function definitions:

```text
usage()
die_usage(message)                 -> prints ERROR, exits 2
quote_command(args...)
run(args...)                       -> prints command, executes unless DRY_RUN=1
resolve_executable(env_name, default_name)
parse_args(args...)
main(args...)
```

`resolve_executable` must reject a supplied non-absolute or non-executable
`HRT_*_BIN`; otherwise it resolves the default through `command -v`,
canonicalizes it with `readlink -f`, and exits 2 if unavailable. Resolution is
lazy and per command: `--help` and `--version` resolve nothing, Task 1's
temporary `install` handler resolves only uv, and the temporary `audit` and
`remove` handlers return 0 until their tasks replace them.

Keep `main "$@"` as the final line. Make the production script executable; keep the test file non-executable.

- [ ] **Step 4: Run focused syntax and behavior checks**

Run:

```bash
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
bash tests/headroom-runtime.sh
```

Expected: all Task 1 tests pass and the suite prints `PASS: Headroom runtime tests`.

- [ ] **Step 5: Commit the CLI foundation**

```bash
git add headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
git commit -m "feat(headroom): add standalone runtime CLI"
```

---

### Task 2: Non-Destructive Audit Engine

**Files:**
- Modify: `headroom-runtime/headroom-runtime.sh`
- Modify: `tests/headroom-runtime.sh`

**Interfaces:**
- Produces finding arrays: `F_SEVERITY`, `F_CODE`, `F_SUBJECT`, `F_MESSAGE`.
- Produces `add_finding SEVERITY CODE SUBJECT MESSAGE`.
- Produces `audit_runtime`, `status_for_findings`, `render_human`, `render_json`, and `run_audit`.
- Produces audit statuses `PASS`, `WARN`, `FAIL`, `ERROR` and exits `0`, `0`, `1`, `2`.
- Consumes fixture seams and constants from Task 1.

- [ ] **Step 1: Add failing fixture tests for a conforming runtime**

Extend stubs so `systemctl`, `headroom`, `curl`, and `ss` return a complete
conforming state. Use the real absolute jq selected by the harness. The fixture
manifest must include:

```json
{
  "profile": "default",
  "targets": [],
  "mutations": [],
  "memory_enabled": false,
  "telemetry_enabled": false,
  "base_env": {
    "HEADROOM_BEACON": "off",
    "HEADROOM_UPDATE_CHECK": "off",
    "HEADROOM_TELEMETRY": "off"
  }
}
```

Add assertions:

```bash
test_conforming_runtime_passes() {
  new_conforming_case conforming
  run_cli audit
  assert_equal "$CLI_STATUS" "0" "a conforming runtime must pass"
  assert_contains "$CLI_OUTPUT" "Status: PASS" "human output must report PASS"
}

test_json_audit_has_stable_shape() {
  new_conforming_case json
  run_cli audit --json
  assert_equal "$CLI_STATUS" "0" "JSON audit must pass"
  assert_equal "$(jq -r '.schemaVersion' <<<"$CLI_OUTPUT")" "1" \
    "JSON schema version must be one"
  assert_equal "$(jq -r '.toolVersion' <<<"$CLI_OUTPUT")" "0.1.2" \
    "toolVersion must identify the toolkit component"
  assert_equal "$(jq -r '.status' <<<"$CLI_OUTPUT")" "PASS" \
    "JSON status must match human status"
}
```

- [ ] **Step 2: Add failing policy and error-classification tests**

Add one test per invariant, with explicit expected finding codes:

```text
HEADROOM_VERSION_MISMATCH                         FAIL / 1
HEADROOM_READINESS_VERSION_MISMATCH               FAIL / 1
HEADROOM_SERVICE_DISABLED                        FAIL / 1
HEADROOM_SERVICE_INACTIVE                        FAIL / 1
HEADROOM_NOT_READY                               FAIL / 1
HEADROOM_READINESS_INVALID                       ERROR / 2
HEADROOM_UNSAFE_BIND                             FAIL / 1
HEADROOM_FOREIGN_LISTENER                        FAIL / 1
HEADROOM_LISTENER_OWNER_AMBIGUOUS                ERROR / 2
HEADROOM_MANIFEST_UNREADABLE                     ERROR / 2
HEADROOM_MANIFEST_INVALID                        ERROR / 2
HEADROOM_PROFILE_MISMATCH                        FAIL / 1
HEADROOM_TARGETS_CONFIGURED                      FAIL / 1
HEADROOM_MUTATIONS_PRESENT                       FAIL / 1
HEADROOM_MEMORY_ENABLED                          FAIL / 1
HEADROOM_TELEMETRY_ENABLED                       FAIL / 1
HEADROOM_BEACON_NOT_DISABLED                     FAIL / 1
HEADROOM_UPDATE_CHECK_NOT_DISABLED               FAIL / 1
HEADROOM_OPENCODE_PACKAGE_PRESENT                FAIL / 1
HEADROOM_OPENCODE_CONFIG_PRESENT                 FAIL / 1
HEADROOM_OPENCODE_ENV_PRESENT                    FAIL / 1
HEADROOM_OPENCODE_UNIT_COUPLED                   FAIL / 1
HEADROOM_OPENCODE_ENV_UNREADABLE                 ERROR / 2
```

Include positive cases where OpenCode is absent/stopped and where either a JSON
or JSONC global config exists without Headroom references. Project-local config
must not be scanned as a global integration surface.

Test a missing required command by unsetting its `HRT_*_BIN` seam and running
the CLI with a controlled `PATH` that omits the command. Assert exit 2 and the
command-specific diagnostic; seam validation and default command resolution are
one error path, not a separate finding code.

Add an explicit `OPENCODE_CONFIG` fixture path and assert it is scanned as a
global candidate. Add invalid-combination cases: `audit --dry-run`, `install
--json`, and `remove --json` all exit 2.

- [ ] **Step 3: Add failing warning and causal-boundary tests**

Add tests proving:

```text
HEADROOM_KOMPRESS_OPTIONAL_DEGRADED               WARN / 0
HEADROOM_PERMISSIONS_BROAD                        WARN / 0
HEADROOM_LIFECYCLE_EXIT_241                       WARN / 0 when explicit evidence seam is supplied
```

The lifecycle warning reads `ExecMainStatus` from the existing systemctl stub;
no separate evidence file or environment seam is introduced.

Also add a Telegram stub that fails the test if invoked, then assert both human
and JSON audits complete without calling it. Assert warning-only JSON output is
byte-identical across two runs.

Add the non-secret marker `SENSITIVE_SENTINEL_DO_NOT_PRINT` as an unrelated
OpenCode environment value and assert it appears in neither human nor JSON
output. The marker deliberately does not resemble a real credential and does
not match the repository secret scans. Compare human and JSON status for one
`WARN` and one `FAIL` case as well as the clean `PASS` case.

- [ ] **Step 4: Run the audit tests and verify they fail before implementation**

Run:

```bash
bash tests/headroom-runtime.sh
```

Expected: the new audit cases fail because findings and checks are not implemented.

- [ ] **Step 5: Implement findings, rendering, and bounded checks**

Implement:

```text
add_finding(severity, code, subject, message)
check_headroom_version()
check_service_state()
check_readiness()
check_listener()
check_manifest()
check_generated_permissions()
check_opencode_config()
check_opencode_package()
check_opencode_environment()
check_unit_independence()
status_for_findings()
render_human()
render_json()
run_audit()
```

Use one curl call with `--connect-timeout 5 --max-time 5`. Capture curl and jq
statuses inside conditionals so `set -e` cannot abort before a finding is
recorded. A transport/non-2xx response is `HEADROOM_NOT_READY` (`FAIL`); a 2xx
body that jq cannot parse is `HEADROOM_READINESS_INVALID` (`ERROR`). Parse
readiness and manifest JSON only through the validated absolute jq command. A
CLI version mismatch uses `HEADROOM_VERSION_MISMATCH`; a ready endpoint serving
another version uses `HEADROOM_READINESS_VERSION_MISMATCH`. Inspect only
selected environment variable names from `/proc/<pid>/environ`; never print
values. Treat a stopped/absent OpenCode service as an informational independent
state. Scan present global config candidates textually for specific Headroom
integration identifiers; do not load or rewrite them.

Use stable finding order matching the check order above. `status_for_findings`
returns `ERROR` if any error exists, then `FAIL`, then `WARN`, else `PASS`.

The upstream runtime contract additionally resolves the Headroom executable
from `HRT_HEADROOM_BIN`, then the uv/XDG tool-bin destination, and finally
`PATH`. It identifies a managed listener by the numeric `default/runner.pid`,
matching every `ss` owner PID, and the NUL-separated `-m headroom.cli proxy`
process arguments under `/proc/<pid>/cmdline`; it does not trust the `ss`
process name. Missing ownership evidence is `ERROR`, a different owner PID is
`FAIL`, and an attributed pre-install listener is foreign existing state.

- [ ] **Step 6: Run focused checks**

```bash
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
bash tests/headroom-runtime.sh
```

Expected: all CLI and audit tests pass.

The suite also asserts that the production script is executable and the test
entry point is not executable, matching repository modes `100755` and `100644`.

- [ ] **Step 7: Commit the audit engine**

```bash
git add headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
git commit -m "feat(headroom): validate runtime isolation"
```

---

### Task 3: Idempotent Installation Orchestration

**Files:**
- Modify: `headroom-runtime/headroom-runtime.sh`
- Modify: `tests/headroom-runtime.sh`

**Interfaces:**
- Produces `classify_install_state` with states `ABSENT`, `PACKAGE_ONLY`, `CONFORMING`, `STOPPED`, `ORPHANED_DEPLOYMENT`, `WRONG_VERSION`, `NONCONFORMING`, `CONFLICT`, `AMBIGUOUS`.
- Produces `run_install` using Task 1's `run` and Task 2's read-only checks.
- Consumes exact package and apply constants from Task 1.

- [ ] **Step 1: Write failing tests for exact mutation commands**

Use stubs that log an invocation delimiter followed by one argument per line,
so spaces and brackets cannot be lost or reinterpreted. Reconstruct the argument
arrays in assertions and verify an absent installation invokes exactly:

```text
uv tool install --python 3.13 headroom-ai[proxy]==0.37.0
headroom install apply --preset persistent-service --runtime python --scope provider --providers manual --profile default --port 8787 --mode cache --no-telemetry --env HEADROOM_BEACON=off --env HEADROOM_UPDATE_CHECK=off
```

Assert the apply log has no `--target`, `--scope user`, `--providers auto`,
`deploy`, `wrap`, `[all]`, or `[ml]` token.

- [ ] **Step 2: Write failing state-matrix and dry-run tests**

Add cases for every design row:

| State | Expected exit and action |
|---|---|
| absent package + absent deployment | `0`; install package and apply deployment |
| exact package + absent deployment | `0`; apply deployment only |
| exact package + `PASS` deployment | `0`; no mutation |
| exact package + `WARN` deployment | `0`; no mutation |
| stopped or disabled valid deployment | `1`; refuse and name explicit upstream start/enable action |
| absent package + present deployment | `1`; refuse orphaned deployment |
| wrong package version | `1`; refuse implicit upgrade |
| wrong CLI version immediately after uv install | `1`; do not apply service |
| unreadable or malformed manifest | `2`; inspection could not establish ownership |
| readable but nonconforming deployment | `1`; report violated invariant |
| positively identified port/profile conflict | `1`; refuse recognized conflict |
| unattributable occupied port | `2`; ambiguous owner |
| non-Linux platform | `2`; unsupported environment |
| unusable user systemd | `2`; required supervisor unavailable |
| pre-existing Headroom OpenCode coupling | `1`; refuse before mutation |

For each mutable state, rerun with `--dry-run` and assert read-only stubs were
called, mutation logs remain empty, and output contains only the commands a real
run would execute. A conforming dry-run prints no mutation command.

Add failing cases in this step for immediate readiness, failures then success,
permanent timeout (exit 1), no request after the deadline, preservation of an
unrelated audit failure, and exactly one readiness request from generic audit.

- [ ] **Step 3: Run tests and verify the install cases fail**

```bash
bash tests/headroom-runtime.sh
```

Expected: install-state tests fail because orchestration is not implemented.

- [ ] **Step 4: Implement state classification and install flow**

Implement:

```text
headroom_package_state()
deployment_state()
classify_install_state()
install_package()
apply_deployment()
run_install()
```

Quote `HEADROOM_PACKAGE` as one argument. After an actual package install,
require the expected executable and exact version before applying the service.

Use `HRT_UNAME_BIN` to present Linux/non-Linux fixture results. Use
`HRT_UPTIME_FILE` (default `/proc/uptime`) as the monotonic elapsed-time source
and `HRT_SLEEP_BIN` for sleeps; the test sleep stub advances the fixture uptime
file deterministically.

After actual apply, run all non-readiness audit checks once and use an
installer-only bounded readiness verification. Share one one-shot readiness
primitive: generic audit calls it exactly once, while install retries only that
primitive for up to 30 elapsed seconds. Probe immediately, sleep at most one
second between attempts, and give each curl request the lesser of five seconds
or the remaining budget. Stop at the first success and use that result in final
verification; do not issue a redundant readiness request.

After actual apply, require the resulting full status to be `PASS` or `WARN`.

Do not call full audit to classify package-only state before the deployment
exists; use bounded file/version/service checks for the state matrix, then full
audit only for a present deployment and post-install verification.

- [ ] **Step 5: Run focused checks**

```bash
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
bash tests/headroom-runtime.sh
```

Expected: all CLI, audit, install, idempotency and dry-run cases pass.

- [ ] **Step 6: Commit installation orchestration**

```bash
git add headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
git commit -m "feat(headroom): install the pinned runtime"
```

---

### Task 4: Safe Automated Removal

**Files:**
- Modify: `headroom-runtime/headroom-runtime.sh`
- Modify: `tests/headroom-runtime.sh`

**Interfaces:**
- Produces `run_remove` and `verify_removed`.
- Consumes Task 3's package/deployment classification and Task 1's mutation wrapper.

- [ ] **Step 1: Write failing removal tests**

Add cases that assert:

```bash
headroom install remove --profile default
```

is the only default mutation, and:

```bash
uv tool uninstall headroom-ai
```

is added only for `--uninstall-tool`.

Cover:

- recognized deployment removal;
- already absent deployment succeeds without invoking Headroom;
- absent deployment plus exact tool and `--uninstall-tool` removes only the tool;
- corrupt/unreadable manifest exits 2 and names the manual runbook fallback;
- conflicting profile exits 1;
- detected OpenCode integration emits a warning but does not block recognized runtime removal;
- dry-run prints applicable commands and writes nothing;
- post-removal service/profile absence and free 8787 pass;
- unattributable remaining listener exits 2;
- no command writes OpenCode, Gateway or shell fixture paths;
- no toolkit-owned removal artifact is written outside the controlled fixture.

- [ ] **Step 2: Run tests and verify removal cases fail**

```bash
bash tests/headroom-runtime.sh
```

Expected: removal tests fail because `run_remove` is not implemented.

- [ ] **Step 3: Implement manifest-aware removal**

Implement `run_remove` so it:

1. classifies package and profile ownership;
2. reports but does not repair OpenCode integration;
3. no-ops when the deployment is absent;
4. refuses ambiguous/corrupt Headroom ownership;
5. delegates recognized removal to Headroom;
6. optionally delegates tool uninstall to uv;
7. verifies absence only after real execution, not dry-run.

Do not implement a force mode. Emit the manual fallback reference for corrupt
state.

- [ ] **Step 4: Run focused checks**

```bash
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
bash tests/headroom-runtime.sh
```

Expected: all component tests pass.

- [ ] **Step 5: Commit removal support**

```bash
git add headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
git commit -m "feat(headroom): add safe runtime removal"
```

---

### Task 5: Runbook, Status Evidence, And Repository Integration

**Files:**
- Create: `headroom-runtime/README.md`
- Create: `docs/headroom-runtime.md`
- Create: `headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md`
- Create: `headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Documents the exact CLI and status contract implemented in Tasks 1-4.
- Establishes runtime `TRIAL`, plugin `HOLD`, MCP/API `NOT_EVALUATED`, and current OpenCode optimization `NONE`.
- Adds the sixth suite and exact syntax/ShellCheck commands to maintainer guidance.

- [ ] **Step 1: Write the component README**

Create `headroom-runtime/README.md` with:

- version 0.1.2 and Headroom 0.37.0;
- file map;
- quick-start commands for dry-run, install, human/JSON audit, remove, and full uninstall;
- PASS/WARN/FAIL/ERROR and exit-code table;
- explicit no-target/provider-manual rationale;
- generated-artifact ownership warning;
- explicit statement that no OpenCode traffic is optimized.

- [ ] **Step 2: Write the operational runbook**

Create `docs/headroom-runtime.md` with sections:

```text
Policy
Architecture
Prerequisites
Install
Generated artifacts
Audit and findings
WSL shutdown/start validation
Known findings
Troubleshooting
Rollback
Upgrade procedure
Design constraints
References
```

Include exact validated commands, loopback-only policy, service-only scope
rationale, WSL recovery semantics, corrupt-manifest manual fallback, rollback,
the ten-step pinned upgrade strategy, the pinned-but-unlocked transitive
supply-chain boundary, the component script's semantic-version rule, and the
three known Headroom findings.
Do not include host-specific PIDs, timestamps, usernames or paths.

- [ ] **Step 3: Record runtime evidence and technology status**

Create `headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md` containing:

- sanitized versions and architecture from the approved design only;
- runtime and WSL lifecycle status `TRIAL`, operationally accepted with the
  findings named in the approved design;
- the generic service/readiness/network/config/outage/restart/WSL facts stated
  in the design, without inventing machine-specific measurements;
- `targets=[]`, `mutations=[]`, telemetry opt-outs;
- optional Kompress, exit 241 and permissions findings;
- Telegram `KNOWN_PREEXISTING_GATEWAY_FAILURE`, stopped-Headroom causal test,
  and `Headroom causal involvement: NONE`;
- runtime `TRIAL`, plugin `HOLD`, MCP/API `NOT_EVALUATED`;
- statement that no current OpenCode optimization exists.

- [ ] **Step 4: Record the plugin hold decision**

Create `headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md`
with:

- decision `HOLD`;
- process-global transport interception and shared Gateway process conflict;
- fail-closed proxy-unavailable behavior;
- compression effectiveness remains unevaluated and is a criterion of the
  future integration matrix;
- no installation/configuration action;
- future A/B/C/D evaluation matrix covering native plugin, MCP, explicit API,
  and no integration;
- promotion criteria for moving from `HOLD` to `TRIAL`.

- [ ] **Step 5: Update root documentation and maintainer guidance**

Update `README.md` to add the opt-in component to “What this is,” repository
structure, and a short Headroom section linking the component README and
runbook. State that it is not installed by the workstation installer.

Update `AGENTS.md`:

- add `headroom-runtime/`, `docs/headroom-runtime.md`, and
  `tests/headroom-runtime.sh` to the layout;
- add `bash tests/headroom-runtime.sh` as the fifth listed shell suite before
  the routing eval and change “five suites” to “six suites”;
- add separate `bash -n` commands for the production and test scripts;
- append both scripts to the ShellCheck command;
- add `## The Headroom runtime` with the no-target invariant, service-only scope
  rationale, generated-artifact boundary, OpenCode guard/non-ownership rule,
  status semantics, blocked plugin statement, component version rule, and
  pinned-but-unlocked supply-chain boundary.
- revise the statement that the repository-policy validator is the only
  dependency-bearing component: the standalone Headroom runtime also requires
  the explicitly checked host commands listed in its section.

- [ ] **Step 6: Verify documentation consistency and links**

Run:

```bash
git diff --check
test -r headroom-runtime/README.md
test -r docs/headroom-runtime.md
test -r headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md
test -r headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md

! grep -RInE '(/home/|previtalicl|Telegram.*token|Bearer |-----BEGIN|sk-[A-Za-z0-9])' \
  headroom-runtime docs/headroom-runtime.md README.md AGENTS.md
```

Expected: `git diff --check` passes; all files exist; the secret/machine-path
scan returns no matches. The generic word `token` may appear only in conceptual
phrases such as “token savings,” never as a credential value.

- [ ] **Step 7: Commit documentation and evidence**

```bash
git add AGENTS.md README.md headroom-runtime/README.md docs/headroom-runtime.md \
  headroom-runtime/docs/evidence/2026-09-12-runtime-trial.md \
  headroom-runtime/docs/decisions/2026-09-12-opencode-plugin-hold.md
git commit -m "docs(headroom): add runtime operations and status"
```

---

### Task 6: Full Verification And Independent Review

**Files:**
- Verify only; modify earlier files only to address concrete findings.

**Interfaces:**
- Produces a clean, PR-ready branch with all six suites passing and no live runtime mutation.

- [ ] **Step 1: Run focused Headroom validation**

```bash
bash tests/headroom-runtime.sh
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh
shellcheck headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
```

Expected: all pass. Confirm the test stubs, not the real Headroom installation,
received every install/remove command.

- [ ] **Step 2: Run all repository suites**

```bash
bash tests/install.sh
bash tests/repository-policy.sh
bash tests/wsl-toolchain-doctor.sh
bash tests/opencode-service.sh
bash tests/headroom-runtime.sh
bash models/routing/opencode/eval/run-tests.sh
```

Expected: all six suites pass.

- [ ] **Step 3: Run all syntax and ShellCheck commands**

```bash
bash -n environments/linux/install.sh
bash -n headroom-runtime/headroom-runtime.sh
bash -n tests/headroom-runtime.sh

shellcheck environments/linux/install.sh tests/install.sh \
  tests/repository-policy.sh repository-policy/validate.sh \
  wsl-toolchain-doctor/wsl-toolchain-doctor.sh \
  tests/wsl-toolchain-doctor.sh \
  opencode-service/opencode-startup-ready.sh \
  opencode-service/opencode-gateway-restart.sh \
  tests/opencode-service.sh \
  headroom-runtime/headroom-runtime.sh tests/headroom-runtime.sh
```

Expected: no syntax or ShellCheck findings.

- [ ] **Step 4: Run diff, secret, and live non-destructive checks**

```bash
git diff --check main...HEAD
git status --short
git diff --stat main...HEAD

! git grep -nE '(/home/previtalicl|Bearer [A-Za-z0-9]|-----BEGIN|sk-[A-Za-z0-9])' \
  -- ':!docs/superpowers/plans/2026-09-12-headroom-runtime.md'

if [[ -x "$HOME/.local/bin/headroom" && \
      -r "$HOME/.headroom/deploy/default/manifest.json" ]]; then
  before_opencode="$(systemctl --user show opencode.service -p MainPID --value)"
  before_headroom="$(systemctl --user show headroom-default.service -p MainPID --value)"
  ./headroom-runtime/headroom-runtime.sh audit --json | jq -e \
    '.status == "PASS" or .status == "WARN"'
  test "$(systemctl --user show opencode.service -p MainPID --value)" = "$before_opencode"
  test "$(systemctl --user show headroom-default.service -p MainPID --value)" = "$before_headroom"
else
  printf 'SKIP: validated live Headroom runtime is not present on this host\n'
fi
```

The conditional audit is the only live-machine component invocation. It is
non-destructive and must not modify or restart Headroom/OpenCode. Capture the
before/after OpenCode and Headroom PIDs only in transient command output; never
write them into committed evidence.

- [ ] **Step 5: Request independent code review**

Ask a reviewer to check:

- exact no-target install command;
- all mutations gated by `run`;
- dry-run and idempotency behavior;
- status/exit-code correctness;
- no secret values or environment dumps;
- OpenCode guards do not impose JSON/JSONC ownership;
- removal does not edit integration state;
- docs do not claim active OpenCode optimization;
- all user requirements and design invariants are covered.

- [ ] **Step 6: Address verified findings and rerun affected checks**

For each accepted finding, add or update a regression test first, observe its
failure, make the smallest implementation/documentation correction, then rerun
the focused and full checks that cover it.

- [ ] **Step 7: Commit any review corrections**

If review required changes, stage the explicit paths named in the accepted
findings and commit with:

```bash
git commit -m "fix(headroom): address runtime review findings"
```

Do not create an empty commit when no corrections were needed.

- [ ] **Step 8: Prepare PR metadata without pushing**

Inspect:

```bash
git status --short
git log --oneline main..HEAD
git diff --stat main...HEAD
git diff --check main...HEAD
```

Recommended PR title:

```text
feat: add validated Headroom runtime tooling
```

Recommended PR description:

```markdown
## Summary
- add an opt-in Headroom 0.37.0 runtime installer, auditor, and remover
- document the validated systemd/WSL lifecycle, rollback, upgrades, and findings
- keep OpenCode integration blocked and record the independent Telegram 409

## Validation
- all six repository suites
- Bash syntax and ShellCheck
- deterministic fixture tests for install, audit, dry-run, idempotency, and removal
- non-destructive live audit on the validated host

## Boundaries
- no Headroom OpenCode plugin or provider wiring
- no generated systemd/deployment artifacts committed
- no Telegram remediation
```

Do not push or create the PR unless explicitly requested.

- [ ] **Step 9: Commit this implementation plan if it is still uncommitted**

```bash
git add docs/superpowers/plans/2026-09-12-headroom-runtime.md
git commit -m "docs: plan Headroom runtime capability"
```

If the plan was committed before execution began, verify it is tracked and skip
this commit rather than creating an empty one.
