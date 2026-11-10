# Expert on Fable 5.2

## Decision

The user moved Expert from `claude-fable-5-1` to `claude-fable-5-2`, keeping
`xhigh`. `maxTurns: 6`, `tools` and `disallowedTools` are unchanged. No other
role changes. This supersedes the model choice in
[Expert on Fable 5.1](2026-10-09-expert-on-fable-5-1.md). The structure of that
record's rationale and risks still applies; its prices, its effort-documentation
quote and its usage-credit observation are 5.1's and were not re-read for 5.2.

## Rationale

- **The user chose the newer Fable release.** The Expert role is meant to sit
  on the most capable tier; no release notes or model documentation were read
  for this record.
- **The pair works on this account.** `claude-fable-5-2` at `xhigh` returned
  `OK` on Claude Code 2.1.322, with `modelUsage` showing `claude-fable-5-2`
  ([2026-11-10 evidence](../evidence/2026-11-10-capability.md)).
- **`xhigh` is kept.** No reason to change effort came with the model change.
  `max` remains the lever if Expert's recommendations fall short.

## Known risks

- **Usage credits.** On this account Fable bills to pay-as-you-go usage
  credits, as recorded for 5.1. That 5.2 bills the same way is inferred from
  the seat tier, not observed: a `-p` call bills without asking, so it shows
  nothing about billing. Every escalation remains a direct cost.
- **Pricing not re-checked.** The 5.1 record's list prices were not re-read
  for 5.2. The cost-tier argument, Expert on a scarcer tier than Build, Plan
  and Reviewer, is assumed to hold.
- **No dispatch evidence for 5.2.** Only the direct `-p` call was made. That a
  Build session's dispatch of `expert` lands on Fable 5.2 rests on the same
  frontmatter-and-hook mechanism observed for 5.1 on 2026-10-09, not on a new
  observation.

## Consequences

`agents/expert.md` and `profile-test.sh` pin `claude-fable-5-2` `xhigh`. The
README's model map, selection-rationale links, deviations 1 and 2, effort
note and verification status reflect Fable 5.2. An installed profile needs
`agents/expert.md` re-copied.

## Evidence boundary

Live capability evidence is in
[`../evidence/2026-11-10-capability.md`](../evidence/2026-11-10-capability.md).
No role-fixture evidence exists.

Later corrections are appended as dated addenda, never edited in place.
