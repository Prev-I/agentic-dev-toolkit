# GPT-6 Role-Specific Screening

Approved in chat on 2026-09-23: a 400-credit allowance for three independent
routing hypotheses. No automatic retries, replacement pairs, extra workloads,
routing changes, commits, or pull requests are authorized.

## Frozen Protocol

- Provider: GitHub Copilot for every arm.
- Build: `gpt-5.6-sol` high versus `gpt-6-sol` high on `build-feature` and
  `build-bugfix`.
- Explore: `gpt-5.6-luna` medium versus `gpt-6-luna` medium on
  `explore-dependency-chain`.
- General: `gpt-5.6-terra` high versus `gpt-6-luna` high on `build-feature`
  and `build-bugfix`, dispatched through the `general` agent.
- Capability probes cover the three new candidate targets only: GPT-6 Sol high,
  GPT-6 Luna medium, and GPT-6 Luna high. The active incumbents already have
  retained capability evidence and are exercised by their workload arms.
- Capability prompt: `Reply with exactly: CAPABILITY_OK`. Require the exact
  response, successful exit, no provider error, and known cost before workloads.
- Workload order alternates arms: Build feature incumbent/challenger, Build
  bugfix challenger/incumbent; Explore incumbent/challenger; General feature
  incumbent/challenger, General bugfix challenger/incumbent.
- Build uses the unchanged Phase-3 runner, snapshots, task prompts, acceptance
  oracles, and regression tests.
- Explore uses the unchanged dependency-chain prompt, snapshot, and scorer.
- General reuses the unchanged Build fixtures as delegated implementation
  workloads but invokes the configured `general` agent in isolated configs.
- Every arm receives a fresh isolated workspace. Workload timeout is 480 seconds.
- Candidate capability admission projection: 10 credits per call. Workload
  admission projection: 35 credits per call. Reconcile after every call and stop
  if cost is missing, a provider/environment failure occurs, or admission fails.
- The allowance is observed harness accounting, not a provider-enforced hard
  cap. A running request may exceed its projection and reported cost can lag.
- Functional correctness, regression preservation, output contract, and scope
  adherence take precedence over timing and cost. Savings cannot offset a
  functional regression.
- Each role is adjudicated independently. Passing one role does not support a
  replacement in another role.
- This is one attempt per model per workload, not a reliability estimate.
- Routing remains unchanged regardless of result.

## Provenance

- Initial repository commit: `93c666a80030c4ed3512940c8df840ed2135f474`
- Recovery repository commit: `d22c8d81aa5e7360f305a3347cb940d35d7fe06a`
- OpenCode runtime: `1.18.31`
- Execution date: `2026-09-23`

## Execution Status Addendum

Initial execution entered `INVALID_PARTIAL` and was suspended pending explicit
authorization for replacement calls. The four direct-model Build calls were
valid. The two Explore and four General calls were invalid because OpenCode
1.18.31 rejected the named subagent as a direct CLI target, emitted `Falling
back to default agent`, and ran the default Build agent instead. The dispatcher
returned exit 0 and classified those calls as `OK`, so the protocol's
environment-failure stop was not applied until independent evidence review found
the warning.

No invalid call may support a routing decision. Corrected replacement calls are
outside the frozen authorization above and required the separately approved
amendment below.

## Approved Recovery Amendment

Approved in chat on 2026-09-23 after disclosure of the fallback defect:

- Authorize exactly six corrected replacement calls within the original
  400-credit cap: two Explore calls and four General implementation calls.
- Use direct `--model` and `--variant` overrides; do not use `--agent`.
- Explore keeps the unchanged dependency-chain snapshot, prompt, parser, and
  scorer.
- General keeps the unchanged feature and bugfix snapshots, prompts, oracles,
  and regression suites. The direct model comparison measures raw delegated
  implementation fitness because `general` has no role-specific prompt and
  cannot be invoked directly by OpenCode 1.18.31.
- Retain final workspaces and explicit oracle/regression exit records for all
  four General replacement arms.
- Reject any replacement call whose raw stream contains a fallback warning.
- No retries, additional workloads, routing changes, commits, or pull requests
  are authorized.

Recovery completed under this amendment. Final status is
`COMPLETE_WITH_INVALIDATED_CALLS`; the six invalid calls remain excluded.

## Metadata Caveat

`dispatch-fixture.sh` stamps every call with the historical constant
`v1-restored-2026-09`, even though the active routing profile is
`v1-user-selected-2026-09-07`. This is a pre-existing runner metadata defect.
It does not affect these comparisons because every valid workload and capability
call names its model and variant directly. The screened incumbents match the
current routing manifest, not the stale stamp.
