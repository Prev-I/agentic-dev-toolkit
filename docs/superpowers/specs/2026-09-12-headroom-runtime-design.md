# Headroom Runtime Capability Design

## Context

Headroom 0.37.0 has been validated on Ubuntu 24.04 under WSL2 as a
standalone, persistent `systemd --user` service. The accepted runtime uses an
isolated uv tool environment with CPython 3.13 and the `headroom-ai[proxy]`
extra. It listens on `127.0.0.1:8787`, recovers automatically after a full WSL
shutdown and restart, and has no traffic or lifecycle coupling to the existing
OpenCode service.

The validated installation deliberately does not integrate Headroom with
OpenCode. The `headroom-opencode` package is absent, OpenCode has no Headroom
configuration or environment, the Headroom manifest has no provider targets or
managed mutations, and neither user unit depends on the other.

The toolkit needs a reproducible, reviewable way to install, audit and remove
that accepted runtime without committing upstream-generated units or widening
the current claim into an untested OpenCode integration.

## Status

| Area | Status | Meaning |
|---|---|---|
| Headroom runtime | `TRIAL` | Operationally accepted with known non-blocking findings |
| WSL lifecycle | `TRIAL` | Automatic recovery accepted with known non-blocking findings |
| OpenCode plugin | `HOLD` | Blocked for the current centralized OpenCode/Gateway architecture |
| MCP integration | `NOT_EVALUATED` | No capability or compatibility conclusion |
| Explicit sidecar/compression API | `NOT_EVALUATED` | No capability or compatibility conclusion |
| Current OpenCode optimization | `NONE` | No Headroom integration is enabled |

`TRIAL` means the standalone runtime is fit for continued controlled use, not
that every optional compression backend or OpenCode integration is accepted.

## Drivers

- Reproduce the exact runtime installation that passed machine and WSL
  lifecycle validation.
- Keep installation opt-in while the technology remains at `TRIAL`.
- Keep upstream's installer and deployment manifest authoritative for the
  generated service.
- Detect drift without modifying the machine during validation.
- Make dry-run behavior reliable and testable.
- Preserve OpenCode's ownership of providers, models and routing.
- Preserve complete lifecycle independence between OpenCode and Headroom.
- Distinguish component failures, integration regressions and unrelated
  adjacent-system failures.
- Document rollback and pinned upgrades without silently following latest.
- Keep all ordinary tests isolated from the real Headroom installation,
  systemd user manager, network and user configuration.

## Non-Goals

- Installing or enabling `headroom-opencode`.
- Adding Headroom configuration to OpenCode.
- Setting `HEADROOM_PROXY_URL` in the OpenCode process.
- Routing any model or provider through Headroom.
- Configuring Headroom MCP, Serena, memory or learn.
- Adding the optional `[ml]` dependencies.
- Repairing the independent Telegram duplicate-poller defect.
- Modifying Headroom's generated unit, scripts or deployment file modes.
- Adding Headroom to the default workstation installer.
- Depending on the in-progress software-catalog branch.

## Approaches Considered

### 1. Thin upstream orchestrator and auditor

Ship a standalone Bash CLI that owns the approved version, preflight policy,
dry-run, installation orchestration, non-destructive audit and manifest-aware
removal. Delegate package installation to uv and service generation to
Headroom's own installer.

Advantages:

- reproduces the validated path exactly;
- keeps generated artifacts owned by upstream;
- avoids service-template drift;
- supports deterministic fixture tests through command and path seams;
- stays independent from the main installer and software catalog.

Disadvantage: some upstream behavior, including generated permissions and stop
exit handling, remains observable rather than directly controlled.

### 2. Toolkit-owned systemd unit

Commit and install a custom unit and runner.

This would give the toolkit direct control over hardening, restart semantics and
readiness, but it would replace the validated upstream lifecycle with a second
implementation. It would also require the toolkit to track internal Headroom
CLI and manifest behavior across upgrades.

### 3. Documentation-first wrapper

Document manual installation and removal, and ship only a validator.

This minimizes code but does not provide a strong reproducibility boundary or
an executable dry-run contract.

## Decision

Use approach 1: a standalone, opt-in `headroom-runtime` component. Do not add it
to `environments/linux/install.sh` in this change.

The component keeps a local Headroom version constant. Moving that pin into the
software catalog is a later change after the catalog branch is integrated and
the catalog's ownership of opt-in components is reviewed.

## Repository Layout

```text
headroom-runtime/
  headroom-runtime.sh       versioned install/audit/remove CLI
  README.md                 concise component usage and safety boundary
  docs/
    evidence/
      2026-09-12-runtime-trial.md
    decisions/
      2026-09-12-opencode-plugin-hold.md
docs/
  headroom-runtime.md       operational runbook and technology status
tests/
  headroom-runtime.sh       isolated fixture and command-stub suite
```

The component-local records keep a standalone runtime out of the OpenCode model
routing bundle. The runtime evidence includes the `NOT_EVALUATED` status of MCP
and the explicit sidecar/compression API. A separate file is not needed for
each untested alternative.

The independent Telegram 409 is mentioned in the runtime evidence as causal
evidence only. This change creates no repository-local backlog item and does
not repair the defect.

The root `README.md` and `AGENTS.md` gain the component entry and validation
commands. No consumer instruction template under `instructions/` changes.

## CLI Contract

The component entry point is:

```text
headroom-runtime.sh install [--dry-run]
headroom-runtime.sh audit [--json]
headroom-runtime.sh remove [--dry-run] [--uninstall-tool]
headroom-runtime.sh --version
headroom-runtime.sh --help
```

The script uses Bash strict mode:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

Every mutating operation passes through a `run` helper. `--dry-run` performs
the same bounded, read-only preflight and audit probes as a real install, then
prints only the mutation commands that the real run would execute. It never
performs a package, service or file mutation. Audit never mutates and accepts
no dry-run flag.

The initial script version is `0.1.0`. This component defines the local rule
that future behavior or output changes bump that version in the same commit:
patch for fixes, minor for additive interface changes and major for breaking
changes.

`--help` and `--version` exit 0. An unknown command, unknown flag or invalid
flag combination exits 2. Successful or idempotent `install` and `remove`
operations exit 0; a recognized policy refusal or failed upstream operation
exits 1; inability to inspect the state reliably exits 2.

### Path and test seams

Host-sensitive defaults are overridable for fixture tests. The names use an
`HRT_` prefix, for example:

- `HRT_HOME`
- `HRT_UV_BIN`
- `HRT_HEADROOM_BIN`
- `HRT_SYSTEMCTL_BIN`
- `HRT_CURL_BIN`
- `HRT_JQ_BIN`
- `HRT_SS_BIN`
- `HRT_PROC_ROOT`
- `HRT_OPENCODE_CONFIG_DIR`
- `HRT_SYSTEMD_USER_DIR`
- `HRT_HEADROOM_DEPLOY_ROOT`

The production defaults resolve under `$HOME` and normal system paths. Every
`HRT_*_BIN` override must be an absolute executable path, and resolved defaults
are converted to absolute paths before execution. This keeps test seams from
becoming an unvalidated production command-injection surface.

The remaining `HRT_*` seams are read-only path roots. They are never executed.

The script never sources or evaluates inspected configuration or manifest
content. JSON is read with `jq`; an unavailable required parser is an execution
error, not a skipped pass. The component therefore has explicit runtime
dependencies on Bash, jq, curl, systemctl and ss in addition to uv and
Headroom. The workstation installer already provisions the system
prerequisites, but the standalone component checks them rather than assuming
that installer was used.

## Version And Installation Specification

The component pins:

```text
HEADROOM_VERSION=0.37.0
HEADROOM_PYTHON=3.13
HEADROOM_PACKAGE=headroom-ai[proxy]==0.37.0
HEADROOM_PROFILE=default
HEADROOM_PORT=8787
```

The package specification is always expanded as one quoted argument so its
square brackets cannot be interpreted as a shell glob.

The package installation command is exactly:

```bash
uv tool install --python 3.13 'headroom-ai[proxy]==0.37.0'
```

The runtime installation command is exactly:

```bash
headroom install apply \
  --preset persistent-service \
  --runtime python \
  --scope provider \
  --providers manual \
  --profile default \
  --port 8787 \
  --mode cache \
  --no-telemetry \
  --env HEADROOM_BEACON=off \
  --env HEADROOM_UPDATE_CHECK=off
```

The absence of `--target` is intentional and load-bearing. `--scope provider`
plus `--providers manual` with no targets is the validated service-only route:
it avoids both the shell startup mutations of user scope and provider-specific
configuration mutations.

The component must never substitute:

- `--scope user`;
- `--providers auto`;
- `--target opencode` or any other target;
- `headroom deploy`;
- `headroom wrap opencode`;
- `headroom-ai[all]` or `headroom-ai[ml]`.

### Installation preflight

Before mutation, `install` verifies:

- Linux is running and `systemctl --user` is usable;
- an absolute executable uv path is available;
- port 8787 is free or belongs to a conforming existing Headroom deployment;
- no conflicting Headroom profile/unit is present;
- every present global OpenCode config candidate (`opencode.json`,
  `opencode.jsonc`, and an explicit `OPENCODE_CONFIG` path) contains no
  Headroom integration reference;
- no `headroom-opencode` package exists;
- the OpenCode service environment contains no `HEADROOM_PROXY_URL` or other
  Headroom integration variable;
- the Headroom and OpenCode units have no dependency edge.

The OpenCode checks are guards, not ownership claims. Either JSON or JSONC may
be a legitimate reviewed configuration: the toolkit's existing installer uses
JSON, while the validated host uses JSONC. The Headroom component checks for
integration content rather than imposing one filename. A Headroom conflict
causes a clear refusal; the component does not edit or reconcile OpenCode.
Project-local OpenCode configuration is outside this host-runtime guard because
the centralized server may legitimately load different project configuration
per request; the audit checks global/service integration surfaces only.

### Idempotency

If audit establishes `PASS` or `WARN` for the exact package and deployment,
`install` reports the existing accepted state and performs no uv or Headroom
mutation. Non-blocking Kompress and permissions warnings therefore remain
idempotent steady states. `FAIL` or `ERROR` on a present deployment never
triggers an implicit repair; applying an absent deployment after the exact
package was installed is completion of installation, not repair.

The install state matrix is explicit:

| Package | Default deployment | Action |
|---|---|---|
| absent | absent | install package, then apply deployment |
| exact 0.37.0 | absent | apply deployment; this resumes an interrupted first install |
| exact 0.37.0 | conforming `PASS` or `WARN` | success, no mutation |
| exact 0.37.0 | valid deployment, service stopped or disabled | refuse and name the explicit upstream start/enable action; install does not silently change an operator-stopped service |
| absent | present | refuse: deployment points at a missing/unknown runtime |
| wrong version | any | refuse: upgrades are reviewed, never implicit |
| exact version | malformed or nonconforming deployment | refuse and report the violated invariant |
| any | conflicting profile or port owner | refuse without guessing ownership |

An occupied 8787 listener whose owner cannot be attributed is an inspection
error and exits 2, not a recognized conflict refusal. A positively identified
conflicting owner exits 1.

It does not silently upgrade, remove or replace a profile. Upgrades are an
explicit reviewed procedure.

### Supply-chain boundary

The version pin constrains the top-level package but does not provide a wheel
digest or lock every transitive dependency. uv resolves the dependency closure
from its configured package index at install time. This is a known `TRIAL`
supply-chain limit, not byte-for-byte reproducibility. The command remains the
exact upstream-supported path that was validated. A future hardening phase may
evaluate a locked requirements artifact and hashes, but must revalidate the
resulting installation path rather than silently changing this one.

## Generated Artifact Ownership

These remain generated runtime artifacts:

```text
$HOME/.config/systemd/user/headroom-default.service
$HOME/.headroom/deploy/default/manifest.json
$HOME/.headroom/deploy/default/run-headroom.sh
$HOME/.headroom/deploy/default/ensure-headroom.sh
$HOME/.headroom/deploy/default/runner.log
$HOME/.headroom/deploy/default/runner.pid
```

They are not committed as installation source. Documentation may show a
clearly labelled expected snapshot, but upstream `headroom install apply` is
authoritative.

## Audit Contract

`audit` is non-destructive. It renders one overall status and a list of
structured findings.

### Status vocabulary

Use the repository's existing doctor vocabulary:

| Status | Exit | Meaning |
|---|---:|---|
| `PASS` | 0 | Required runtime and isolation checks pass, no warnings |
| `WARN` | 0 | Required checks pass with non-blocking findings |
| `FAIL` | 1 | A Headroom runtime or isolation policy violation exists |
| `ERROR` | 2 | The audit cannot determine the state reliably |

`WARN` is the repository-native equivalent of the validation report's
`PASS_WITH_FINDINGS`. It must not be collapsed into failure.

Human output prints one line per finding and a final status. JSON output follows
the doctor-style shape:

```json
{
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "action": "audit",
  "status": "WARN",
  "findings": [
    {
      "severity": "WARN",
      "code": "HEADROOM_KOMPRESS_OPTIONAL_DEGRADED",
      "subject": "http://127.0.0.1:8787/readyz",
      "message": "Optional Kompress is degraded; the required runtime is ready."
    }
  ]
}
```

JSON is deterministic: no timestamps, PIDs, usernames, machine identifiers,
credentials or raw environment dumps. Findings use stable order and JSON-safe
escaping.

### Required checks

Audit fails when any of these invariants is violated:

- `headroom --version` is exactly 0.37.0;
- `headroom-default.service` is enabled and active/running;
- `http://127.0.0.1:8787/readyz` succeeds, reports ready and version 0.37.0;
- port 8787 listens only on `127.0.0.1` and belongs to the Headroom process;
- manifest profile is `default`;
- manifest targets and managed mutations are empty;
- manifest memory and telemetry are disabled;
- manifest environment sets `HEADROOM_BEACON=off` and
  `HEADROOM_UPDATE_CHECK=off`;
- every present effective/global OpenCode config candidate has no Headroom
  integration reference;
- `headroom-opencode` is absent;
- the OpenCode process has no `HEADROOM_PROXY_URL` or equivalent integration
  environment;
- neither unit depends on the other.

An unreadable manifest, unavailable required command, malformed JSON, or an
ambiguous listener/process owner is `ERROR`, because the check did not establish
a result. Curl uses a five-second connect/request bound. The audit makes one
bounded readiness request; it does not wait indefinitely or turn a transiently
slow endpoint into an ambiguous pass.

Listener ownership absent from `ss` output is ambiguous, not evidence that a
port is free. This includes listeners owned by another user when process
attribution is unavailable.

OpenCode may legitimately be stopped or not installed. In that state the
process-environment coupling check is satisfied and reported informationally;
it is not an `ERROR`. If OpenCode is running, the validator discovers the main
PID from the user unit and inspects only the names of selected Headroom-related
environment variables in `/proc/<pid>/environ`. It never emits values or dumps
the complete environment. If that procfs file is unreadable, the audit is
`ERROR`. Static unit dependencies and present configuration files are checked
whether or not the process runs.

### Non-blocking findings

Audit warns rather than fails for:

- optional Kompress degraded/not-ready while overall readiness is true;
- generated directory/file modes that are broader than the observed
  `0600` manifest boundary;
- a recorded or observed upstream lifecycle exit-241 symptom that does not
  prevent recovery.

The generic audit does not query Telegram. Adjacent subsystem health can be
useful causal evidence in a dedicated integration evaluation, but a Telegram
409 cannot prove a Headroom runtime failure. The runtime evidence documents the
known independent defect and the stopped-Headroom causal test.

## Removal Contract

Default removal runs only:

```bash
headroom install remove --profile default
```

With `--uninstall-tool`, it then runs:

```bash
uv tool uninstall headroom-ai
```

Before removal the command verifies that the profile is the expected Headroom
profile. Unknown or conflicting Headroom ownership is refused rather than
guessed. Removing an already absent deployment succeeds as a no-op;
`--uninstall-tool` can still remove an exact recognized uv tool.

Detected OpenCode integration is a warning during removal, not a blocker:
removing the runtime is the safer direction. The command states explicitly that
it does not remove or repair OpenCode configuration, so the operator must use
the separately reviewed integration rollback before expecting OpenCode to work.

A corrupt or unreadable manifest blocks automated profile removal because the
upstream remover cannot prove what it owns. The runbook documents the manual
evidence-preserving fallback: archive the profile directory and generated unit,
inspect their ownership, then use upstream/systemd commands deliberately. The
standalone CLI has no force mode that guesses through corrupt state.

Dry-run prints both commands as applicable and changes nothing. Removal never
edits OpenCode, Gateway, `.bashrc`, `.profile`, `.zshrc`, or other provider
configuration. The toolkit code itself writes no removal artifact; it delegates
only the exact recognized upstream and uv commands. Post-removal verification
checks that the service/profile is absent and port 8787 is free. An ambiguous
port owner is an error. Protected-boundary violations are reported but never
repaired.

## WSL Lifecycle Guidance

The runbook records the validated sequence:

```powershell
wsl.exe --shutdown
```

After the distribution starts again:

- `systemd --user` recovers with linger enabled;
- Headroom auto-starts and becomes ready on `127.0.0.1:8787`;
- OpenCode auto-starts and becomes healthy on `127.0.0.1:4096`;
- a fresh TUI attach succeeds;
- centralized inference succeeds;
- neither service needs a manual start or shell initialization.

WSL shutdown necessarily stops Linux processes. The accepted property is
automatic recovery when the distribution starts again, not availability while
WSL is stopped.

## Known Findings

### Optional Kompress

With `[proxy]`, optional Kompress reports degraded/not-ready while the overall
Headroom runtime is ready and the Rust core is loaded. This is non-blocking.
The component does not add `[ml]` without a separate size, security, runtime and
benefit evaluation.

### Lifecycle exit 241

Explicit stop/restart testing observed `status=241/CONFIGURATION_DIRECTORY`
despite process termination and successful recovery. It did not recur as a WSL
boot failure. The toolkit records the finding and does not add a speculative
`SuccessExitStatus` override to the generated unit.

### Generated permissions

Observed generated state used approximately:

- directories `0775`;
- operational files and logs `0664`;
- manifest `0600`;
- runner scripts `0755`.

No credentials were present. The audit reports broader operational-file modes
as a hardening warning. This change does not alter upstream-generated files.

### Telegram duplicate poller

Telegram long polling returns HTTP 409 when more than one `getUpdates` consumer
uses the bot. The defect predates Headroom. During causal validation, the 409
continued with Headroom stopped and port 8787 absent while Gateway/OpenCode,
TUI attach and centralized inference remained healthy.

Classification:

```text
KNOWN_PREEXISTING_GATEWAY_FAILURE
Headroom causal involvement: NONE
```

The issue is mentioned as evidence only, per the selected repository handling.
It is not encoded into the generic Headroom audit and is not repaired here.

## OpenCode Plugin Hold

The native Headroom OpenCode plugin remains blocked. In Headroom 0.37.0 it
patches process-global HTTP transports, so it can intercept non-inference
outbound traffic from the same centralized process, including Gateway channel
traffic. It is also fail-closed when the proxy is unavailable.

The current architecture hosts OpenCode provider traffic and Gateway behavior
in the same process. A process-global interceptor violates that boundary.

The plugin decision record requires a separate future evaluation comparing:

1. native OpenCode transport plugin;
2. MCP-based integration;
3. explicit sidecar/compression API integration;
4. no Headroom integration.

The comparison must evaluate interception boundary, Gateway isolation,
fail-open/fail-closed behavior, compression effectiveness, provider
compatibility, cache behavior, latency, token savings, correctness,
operational complexity and upgrade risk.

Until that evaluation passes, documentation must not claim that Headroom
optimizes OpenCode traffic.

## Upgrade Strategy

Headroom remains pinned. The component never tracks latest implicitly.

A future upgrade requires:

1. inspect the new Headroom release;
2. review OpenCode integration changes even while the plugin remains disabled;
3. review persistent-service installer and generated unit changes;
4. review security, telemetry and update-check behavior;
5. update the standalone version and package pin;
6. explicitly upgrade/reinstall the isolated uv tool;
7. re-apply the persistent deployment if upstream requires it;
8. rerun the component audit and fixture suite;
9. rerun live runtime validation;
10. rerun WSL lifecycle validation when service behavior changes.

Plugin qualification remains a separate gate from runtime upgrades.

## Test Design

`tests/headroom-runtime.sh` uses repository-standard Bash assertions, temporary
fixture roots and executable command stubs. It never invokes the real uv,
Headroom, systemd user manager, OpenCode server or network.

The suite controls all paths through `HRT_*` seams and records command calls so
it can prove both positive actions and prohibited non-actions.

### Installation tests

- exact uv package/Python command;
- exact persistent-service command;
- no `--target` argument;
- no user scope, auto providers, deploy, wrap, `[all]` or `[ml]`;
- dry-run performs bounded read-only probes but invokes no stubbed mutation;
- dry-run prints no mutation for an already conforming `PASS` or `WARN` state;
- conforming state is a no-op;
- conforming `WARN` state is also a no-op;
- exact package plus missing deployment resumes by applying the deployment;
- valid but stopped/disabled deployment is refused without starting it;
- absent package plus present deployment is refused;
- conflicting version/profile/listener/OpenCode integration fails before
  mutation;
- installed CLI version is checked before service apply.

### Audit tests

- fully conforming state is `PASS`, exit 0;
- optional Kompress degradation is `WARN`, exit 0;
- permission hardening observations are `WARN`, exit 0;
- wrong version, inactive/disabled service, unhealthy readiness, unsafe bind,
  non-empty targets/mutations, enabled memory/telemetry, missing opt-outs or
  OpenCode coupling are `FAIL`, exit 1;
- unavailable commands, malformed manifest, ambiguous listener ownership and
  unreadable inputs are `ERROR`, exit 2;
- audit never invokes Telegram or any unrelated channel command;
- human and JSON output agree;
- JSON is deterministic and contains no fixture secrets.

### Removal tests

- manifest-aware removal uses profile `default`;
- tool uninstall occurs only with `--uninstall-tool`;
- dry-run is non-mutating;
- unknown/conflicting profiles are refused;
- already absent deployment is an idempotent success;
- corrupt manifest is refused and points to the documented manual fallback;
- detected OpenCode integration warns but does not block recognized runtime removal;
- OpenCode and shell files are never written;
- no toolkit-owned removal file is written outside the controlled fixture;
- post-removal checks distinguish absent service/profile and occupied port.

### Quality checks

The complete repository verification remains explicit and becomes six suites:

```bash
bash tests/install.sh
bash tests/repository-policy.sh
bash tests/wsl-toolchain-doctor.sh
bash tests/opencode-service.sh
bash tests/headroom-runtime.sh
bash models/routing/opencode/eval/run-tests.sh

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

git diff --check
```

`headroom-runtime/headroom-runtime.sh` is tracked executable (`100755`);
`tests/headroom-runtime.sh` is `100644` and invoked with Bash. `AGENTS.md` must
update its repository layout, change “five suites” to “six suites”, and include
the new scripts in syntax and ShellCheck commands. It also gains a short
`## The Headroom runtime` section recording the load-bearing no-target command,
the provider/manual scope rationale, the generated-artifact boundary, and the
fact that OpenCode checks guard against Headroom coupling without imposing a
JSON-versus-JSONC ownership policy.

A secret scan checks the changed files and diff; it does not embed host paths,
tokens, credentials, PIDs, timestamps, usernames or machine identifiers.

## Documentation And Evidence

`docs/headroom-runtime.md` is the operational source for install, audit,
generated-artifact ownership, WSL recovery, rollback, upgrades and known
findings.

The component-local dated runtime evidence records observed facts in generic
form without machine-specific identifiers. It preserves the accepted
classifications and the causal Telegram result.

The plugin decision records the `HOLD`, why the current architecture makes the
plugin unsafe, and the exact evidence required to reconsider it.

The root README says only that the toolkit offers an opt-in Headroom runtime
component. It does not imply default installation or current OpenCode traffic
optimization.

## Git And Delivery

Work is performed on `feat/headroom-runtime`, based on clean `main`, in an
isolated worktree. The dirty `feat/software-catalog` checkout is not modified.

The repository uses GitHub Flow and pull-request integration. The completed
change is prepared as focused commits and a PR-quality diff. It is not pushed
or merged without an explicit request.
