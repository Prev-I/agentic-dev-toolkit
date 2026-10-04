# POST_RUN_DIAGNOSTIC — verifier v2

These offline results are diagnostic only: they are **not valid coding passes**,
do not adjudicate, and have no effect on the preserved `INVALID_OR_INCOMPLETE`
decision, attempts, freeze manifest, or original verification logs.

`v2/summary.json` records the completed diagnostic. `/usr/bin/python3` resolves
to `/usr/bin/python3.12`; child processes use a controlled PATH, fixed candidate
workspace cwd, fresh HOME per command, and separate stdout/stderr logs. A Python
wrapper delegates only to that explicit executable and retains stderr even when
the historical tests suppress it. A headless credential-wrapper stub in each
temporary HOME satisfies the unrelated verify-only prerequisite without
disabling WSL checks or accessing credentials.

More precisely, the WSL branch executes but its headless-wrapper assertion is
satisfied by construction by the stub. This is not credential-wrapper quality
evidence. These checks ran on the WSL host; host/WSL metadata and the executed
verifier digest were not captured in the summaries. The final verifier and
input files remain available, but their association with execution is not an
independently timestamped digest proof.

Before any retained patch is evaluated, the reference from `55da937` must pass
both PATH oracles, immutable and reference-authored suites, and separate syntax
checks. The same reference-authored suite must reject the broken `7605022`
installer through a PATH behavioral assertion. Both controls passed in the
completed v2 diagnostic.

| Model | Immutable suite | Candidate suite | Mutation suite |
|---|---|---|---|
| Opus 5.5 high | 3/3 pass | 3/3 pass | 3/3 behavioral rejection |
| GPT-6.1 Sol high | 3/3 pass | 3/3 pass | 3/3 behavioral rejection |

The arms are **tied on these diagnostic coding checks**. This does not establish
general equivalence, exclude defects outside the checks, or repair the original
experiment. There is no coding-quality signal here to justify a new Build freeze
on the same workload. The preserved gate results (Opus 0/3, Sol 3/3), cost and
latency further argue against that expenditure.

The initial `summary.json`/`reference-control/` and `control-check-2/` preserve
failed preflight diagnostics. Neither evaluated a retained candidate patch.
The first exposed the missing headless credential wrapper; the second used a
relative output path that prevented the stderr wrapper from opening its log.
Those checks motivated the final absolute output paths and isolated prerequisite.
All files here are POST_RUN_DIAGNOSTIC, including these unsuccessful preflights.

The failed preflights also used an earlier verifier/classifier version that was
not separately retained: the current classifier reads stdout plus stderr and
would classify their PATH rejection as behavioral rather than HARNESS_ERROR.
Their original summaries remain readable as produced, not recomputed.
Both syntax commands recorded their statuses, but their logs shared the filename
`install-syntax.log`, so the tests-file syntax log overwrote the installer log.
Python stderr `.tmp` files are retained wrapper scratch alongside the final
stderr logs; they are diagnostic byproducts, not separate verification results.
