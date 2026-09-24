# GPT-6 Role-Specific Screening Result

## Result

**Keep the current routing for Build, Explore, and General.** All three GPT-6
targets are usable, but the valid role-specific evidence does not meet the
replacement bar. Routing and the user-global OpenCode configuration were not
changed; the user-global statement is an operator attestation because that file
is outside the repository evidence tree.

2026-09-24 addendum: the later user cost-management decision in
`../../../docs/decisions/2026-09-24-cost-optimized-routing.md` deliberately changes
Build and General despite this screening's `KEEP_INCUMBENT` verdicts. This
experiment itself changed no routing, and its adjudication remains unchanged.

| Role | Valid result | Decision |
|---|---|---|
| Build | Both Sol versions stopped for approval on feature and passed bugfix | Keep GPT-5.6 Sol high |
| Explore | Both Luna versions returned the exact chain; 5.6 was faster and 6 was cheaper | Keep GPT-5.6 Luna medium |
| General | Both stopped for approval on feature and passed bugfix; Luna 6 had a favorable bugfix efficiency signal | Keep GPT-5.6 Terra high |

## Build

| Workload | Model | Oracle | Regression | Seconds | Credits |
|---|---|---|---|---:|---:|
| Feature | GPT-5.6 Sol high | FAIL, approval stop | PASS | 47.051 | 19.332720 |
| Feature | GPT-6 Sol high | FAIL, approval stop | PASS | 33.345 | 9.525150 |
| Bugfix | GPT-6 Sol high | PASS | PASS | 36.924 | 10.583880 |
| Bugfix | GPT-5.6 Sol high | PASS | PASS | 61.510 | 25.967000 |

On the completed bugfix, GPT-6 Sol used 59.2% fewer credits and was 40.0%
faster. That is a useful efficiency signal, but the protocol makes functional
correctness primary and forbids savings from offsetting a functional regression.
The feature failures reflect the current unattended execution contract: both
models obeyed the loaded brainstorming approval gate and therefore did not edit.

## Explore

| Model | Gate | Seconds | Credits |
|---|---|---:|---:|
| GPT-5.6 Luna medium | PASS | 13.370 | 0.686128 |
| GPT-6 Luna medium | PASS | 18.010 | 0.355114 |

Both direct-model recovery responses exactly matched the dependency-chain
oracle. GPT-6 Luna took 34.7% longer but used 48.2% fewer observed credits. The
mixed result on one small fixture is enough to withhold promotion, not enough to
claim either model is generally superior.

## General

| Workload | Model | Oracle | Regression | Seconds | Credits |
|---|---|---|---|---:|---:|
| Feature | GPT-5.6 Terra high | FAIL, approval stop | PASS | 22.587 | 9.796830 |
| Feature | GPT-6 Luna high | FAIL, approval stop | PASS | 33.306 | 0.540634 |
| Bugfix | GPT-6 Luna high | PASS | PASS | 37.612 | 0.628468 |
| Bugfix | GPT-5.6 Terra high | PASS | PASS | 39.299 | 13.231910 |

Both successful bugfix patches were the same scoped one-character boundary
correction and passed the unchanged oracle and regression suite. GPT-6 Luna was
4.3% faster and used 95.3% fewer observed credits on that workload. This is a
credible efficiency signal for Luna 6 high, but not a replacement case because
both candidates failed to complete the feature workload under the unattended
approval contract.

General was tested by direct model dispatch rather than `--agent general`.
OpenCode 1.18.31 cannot run a subagent directly, and the current `general` agent
has no role-specific prompt, so the direct calls preserve the model, variant,
workspace, global instructions, and implementation workload relevant to this
screening.

## Invalidated Calls

The first attempted Explore and General runs are excluded. OpenCode rejected the
named subagents, emitted `Falling back to default agent`, and ran the default
Build agent while exiting 0. Independent review caught the fallback before any
result was reported. The six invalid calls consumed 111.4949 credits and remain
retained as incident evidence; none contributes to the tables above.

## Budget And Scope

- Approved cap: 400 credits.
- Observed total spend: 205.639885 credits.
- Valid capability and workload evidence: 94.144985 credits.
- Invalid fallback calls: 111.4949 credits.
- Unused allowance, now closed: 194.360115 credits.
- Valid calls: 3 capability probes, 4 Build calls, and 6 approved recovery calls.
- Retries and additional workloads: none.
- Initial runtime/commit: OpenCode 1.18.31 at `93c666a80030c4ed3512940c8df840ed2135f474`.
- Recovery runtime/commit: OpenCode 1.18.31 at `d22c8d81aa5e7360f305a3347cb940d35d7fe06a`.

Credits are runtime-reported USD multiplied by 100. They vary materially with
cache state, are not normalized, and are not reconciled with the GitHub billing
interface. Parent orchestration and review usage is not in the experiment ledger.

Every dispatch record carries `routing_profile_id: v1-restored-2026-09` because
the shared runner stamps that historical constant. This is stale metadata: the
screened incumbents match `current-routing-targets.json`, and every valid call's
concrete `dispatch_target` and `variant` establish model identity. The stale
profile ID does not affect direct-model execution or adjudication.

## Limits

One attempt per arm is screening evidence, not a reliability estimate. The
original Build runner deletes final sandboxes after scoring and its checks are
silent, so its verdicts rest on retained machine-readable attempt records rather
than independently rerunnable work products. Recovery General workspaces and
explicit verification exit records are retained.

The feature fixture is not a clean discriminator of coding quality with the
loaded Superpowers workflow: all implementation candidates correctly stopped at
its mandatory human approval gate. A future comparison should revisit it only
under an explicitly pre-approved execution contract compatible with the skill
policy.
