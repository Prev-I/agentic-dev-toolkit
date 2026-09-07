# GPT-6 Astra Build Screening

## Decision

**KEEP_OPUS under the existing single-shot Build contract.** This is not a
general verdict on Astra's coding ability or suitability for interactive work.
Production routing is unchanged.

The user approved a new 300-credit ceiling before live dispatches. The frozen
protocol is `eval/manifests/astra-build-preflight.json`; machine-readable results
and unmodified raw dispatch evidence are under `eval/records/astra-build/`.

## Results

Both models used GitHub Copilot, variant `high`, OpenCode `1.18.29`, and the same
installed Superpowers `v6.3.0`. Both capability probes returned `CAPABILITY_OK`.
The existing feature and bugfix fixtures were reused without modifications.

| Workload | Model | Acceptance Oracle | Regression | Seconds | Credits |
|---|---|---|---|---:|---:|
| Feature | Opus 5 high | PASS | PASS | 54.965 | 24.876775 |
| Feature | GPT-6 Astra high | FAIL: approval stop | PASS | 42.497 | 31.504350 |
| Bugfix | GPT-6 Astra high | PASS | PASS | 84.613 | 45.105850 |
| Bugfix | Opus 5 high | PASS | PASS | 37.020 | 22.313175 |

All four dispatches were runtime-healthy (`OK`, exit 0), with acceptance failing
before each attempt. No environment failures, timeouts, or replacement pairs
occurred. No human follow-up response or second turn was supplied to either
model. Runtime health is not task success.

Astra's feature response ended:

> I'll run both existing tests and check empty strings, spaces, and embedded
> newlines. Approve this approach?

The raw tool trace confirms it loaded `brainstorming`, inspected the fixture,
and made no edits. The unchanged snapshot fails because `reverse` is absent.
This is retained as `VALID_CONTROLLER_FAILURE`, per the inherited single-shot
taxonomy, rather than discarded as an environment problem.

Both bugfix arms made the same one-character `>= 0` to `> 0` change and passed
the oracle and regression suite. Opus also implemented the feature and passed
both suites. The oracle checks test-file and README integrity; raw edit traces
show the existing helper functions were left untouched.

The earliest criterion, correctness/task success, decides the result. Timing
and cost are observational, not compensation for the feature non-completion.
The inherited 0.378885 relative-range timing threshold is not needed here.

## Interpretation

**This result exposes an approval-protocol mismatch, not demonstrated inability
to write the feature.** Astra followed the installed brainstorming skill's
approval gate; the non-interactive harness cannot answer it. Opus completed the
task without invoking that skill. Its task-completion advantage must not be
reported as superior instruction compliance. The same distinction mattered in
the prior Sol experiment.

The honest conclusion is that Astra is not a drop-in winner for this exact
unattended setup. Its suitability as an interactive main Build agent remains
unresolved. A useful next experiment would explicitly pre-approve implementation
for both arms, or supply an identical interactive approval protocol, before
testing larger representative work. That would be a separate experiment, not a
replacement of this retained failure. No such follow-up was run here.

## Budget

- Workload dispatches: **123.800150 credits**.
- Capability checks: **22.857975 credits**.
- Total recorded evaluation dispatches: **146.658125 / 300 credits**.
- Unused allowance: **153.341875 credits**, closed, not silently reused.

Amounts are reconstructed by summing every `step_finish.part.cost` in each raw
stream and multiplying USD by 100, as the existing dispatcher does. They are
harness-derived observations, not a reconciliation with GitHub's billing UI.
Parent orchestration and independent review session usage is not exposed by
this ledger and is excluded from these figures.

Before each capability check, `ledger_admit` checked a 20-credit projection;
before each workload, it checked 75 credits. Spend was reconciled after each
sequential dispatch. Those projections are admission controls, not provider-side
hard caps; a request's cost is known only after a completed model step. All
observed dispatch costs stayed below their projections.
The admission calls are recorded in the operator session, not a retained
orchestration log; the stored ledger independently proves completed spend only,
not execution of the pre-dispatch checks.

## Reproduction

Source revision: `eca1f81ee689cead79a2a6d140a9eab3b417f27b`. The manifest was
written before any capability or workload calls; it was not committed or
externally timestamped before execution. No commits or PRs were requested.

The runner was sourced from the repository root. For each entry of the manifest's
ordered `sequence`, the invocation was:

```bash
source models/routing/opencode/eval/runtime/opencode-v1-adapter/run-phase3-build-fixture.sh
ledger_admit "$ledger" astra_build 75
run_phase3_build_fixture \
  --outdir "$run_root/$fixture/$label" \
  --fixture "$fixture" --model "$model" --variant high \
  --label "$label" --timeout 480 \
  --ledger "$ledger" --account astra_build
ledger_spent "$ledger" astra_build
```

Here `run_root` was `/tmp/opencode/astra-build-20260907`, and `ledger` was its
`ledger.json`. Each admission check had to succeed before dispatch. Capability
checks used `dispatch_fixture` directly, `--workspace /tmp/opencode`, the stored
`capability.txt`, `--timeout 120`, and the corresponding model at `high`.

Fresh per-arm workspaces were outside all Git repositories. Opus's feature
`git diff` reported that it was not in a Git repository, rather than discovering
the evaluation repository upward. Global configuration and skills were still
inherited; this was not an OS security sandbox or a fully hermetic environment.
Directory names exposed model labels and the evaluation framing, so this was
not a blinded experiment. No trace shows either model reading sibling results.
The runner deletes each sandbox after scoring; edit payloads and test output
survive in raw transcripts, but standalone final work products do not.

The dispatcher records a fixed historical `routing_profile_id`; this is not
proof of a byte-identical historical profile. A filtered `opencode debug config`
check confirmed global Build Opus 5/high and Superpowers v6.3.0, with no configured
MCP servers in the external workspaces. Direct model overrides selected the arms.
The debug skill-list output could not be parsed as complete JSON, so no full
installed-skill inventory is claimed. Loaded skill contents are in raw traces.

## Limitations

- Two tiny Bash fixtures, one attempt per model per workload: screening only.
- `high` is a provider-specific label, not a matched compute budget.
- Cache state, model-specific system prompts, and latency were not controlled.
- Token fields in dispatch metadata are inherited from the existing parser;
  only multi-step cost was independently recomputed, not aggregate token usage.
- No reviewer-role or controller/reviewer family-separation experiment was run.
- No active profile, routing bundle, fixture, or shared runner was changed.

## Verification

All four repository suites passed during this evaluation. Fresh verification
logs are retained under `eval/records/astra-build/verification-*.log`:

```text
bash tests/install.sh                         PASS
bash tests/repository-policy.sh               PASS
bash tests/wsl-toolchain-doctor.sh             148 passed, 0 failed
bash models/routing/opencode/eval/run-tests.sh PASS
```

Raw streams independently reproduce all four per-workload credit totals and
show 9/8/10/8 completed model steps in manifest order. Capability responses,
attempt records, oracle logs, regression logs, and the six-entry ledger are
preserved beside `adjudication.json`.
