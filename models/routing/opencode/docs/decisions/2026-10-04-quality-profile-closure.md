# Quality Profile Closure

Status: **ACCEPTED**

Accepted: **2026-10-04**, by explicit user instruction. The bounded coding
diagnostic is tied, the preserved gate evidence favors current Sol, and v1
Reviewer scoring does not establish a GPT-family replacement. These facts do
not support adopting or spending further on the proposed quality profile.

## Accepted decision

Do not adopt the proposed quality profile. Current routing remains unchanged;
the target manifest is not updated.

- Build on Opus 5.5 is not supported by the collected evidence. The frozen Build
  result remains `INVALID_OR_INCOMPLETE`. In separate **POST_RUN_DIAGNOSTIC**
  verifier-v2 checks, both arms pass the same oracles and suites, and both
  candidate suites reject the broken installer through behavioral assertions.
  They are tied on these bounded coding checks. Preserved gate adherence is
  Opus 0/3 versus Sol 3/3. Opus coding median cost is 116.01914 credits versus
  25.05121, and median latency 247.850 seconds versus 128.545 seconds. Diagnostic
  parity does not repair the invalid adjudication or establish broad equivalence.
- A GPT-family Reviewer is not promoted. V1 gives all four models the same
  seeded attribution (3 detected, 1 missed, 1 ambiguous), with a real clean
  counter defect penalizing Sol. The benchmark does not discriminate seeded
  quality adequately; no rescoring is authorized.
- Prepare future screening infrastructure rather than repeat the same Build
  comparison. Verifier v2 requires positive and negative controls. Reviewer v2
  repairs the clean counter, supplies the missing pagination contract and makes
  concurrency attribution witness-bearing under strict fail-closed matching.
  Shorter correct evidence can still fail to match; the clean counter's partial
  write failure remains a disclosed limitation. V2 is a different benchmark and
  cannot establish why a historical model missed the v1 seed.

## Evidence boundaries

Preserved records: `eval/records/reviewer-cross-family-screening/` and
`eval/records/opus55-gpt61-build-quality-screening/`. Diagnostics are only in the
latter's `post-run-diagnostic/`. All new retrospective observations are
**POST_RUN_DIAGNOSTIC**, never valid coding passes or adjudication amendments.
The fixture-v2 design is also post-run diagnostic input for a future protocol,
not a basis for reinterpreting v1 findings.
The diagnostic HOME stub satisfies a WSL prerequisite assertion by construction,
not by validating a real credential wrapper. Earlier failed preflight verifier
versions and executed verifier digests were not separately anchored; diagnostic
conclusions are bounded to retained logs and status outputs.

General screening is **DEFERRED**. The PATH workload no longer discriminates
the two coding arms under the complete verifier-v2 diagnostic, and no new
observational trigger justifies another screening. This is not a claim that
the untested General challengers are equivalent. The freeze in
`eval/records/general-path-screening/` remains an unexecuted design in
`AWAITING_APPROVAL`, not execution authorization. A future screening requires
an observational trigger and a discriminating workload, followed by a new
executable freeze and budget approval.
