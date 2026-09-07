# Pre-Approved Build Follow-Up

## Result

**INCONCLUSIVE: both models hit the budget stop before implementation.** The
explicit approval waiver worked for the observed portion of both runs: neither
asked for human approval. Neither produced a code change, so this follow-up
cannot rank coding quality or justify a routing change.

The user explicitly requested a follow-up in which approval-gate behavior would
not block implementation. Asked whether to use a new budget or the original
remainder, the user replied "proceed" without choosing. The operator explicitly
adopted the conservative interpretation: use only the original remaining
153.341875 credits, not another 300. That spending authorization supersedes the
earlier report's statement that its unused allowance was closed; the original
evidence and ledger remain unchanged.

## Protocol

The frozen `eval/records/astra-build-followup/protocol.json` and identical
`prompt.txt` record the follow-up. One larger, real historical task replaced the
suggested multi-task set to fit the remaining budget: the installer PATH guards
fixed by `55da937`, starting from `7605022`.

Both arms received the installer, original installer tests, and the adapter
required by those tests, without Git history or the known-good patch. Their
workspaces were separate, neutral-named directories outside any repository.
The evaluator retained the original tests and independently exercised exact
PATH membership, missing directories, spaces, existing duplicates, ordering,
dry-run behavior, backups, and repeated activation across all three PATH sites.

Before dispatch, the oracle failed on the historical base during repeated
activation and passed on the known-good fix. The original installer suite passed
on the historical base, as expected: it did not yet cover this regression.
The oracle is behavioral and does not require the historical helper names.

Prompt approval was explicit and symmetric:

> For this task only, skip any brainstorming/design-approval pause required by a
> skill; the user explicitly authorizes this exception. All other safety,
> testing, and scope rules still apply.

No skills were globally disabled, no model configuration was edited, and no
permission to install software or mutate the real HOME was given. Delegation
was prohibited for both arms. The historical fix was co-authored by Opus 5,
which is a selection-bias limitation, although no history was exposed to either
candidate.

## Observations

| Arm | Model / Variant | Completed Steps | Seconds to Stop | Recorded Credits | Changed Files |
|---|---|---:|---:|---:|---:|
| A | GPT-6 Astra / high | 5 | 39.477 | 72.248200 | 0 |
| B | Opus 5 / high | 6 | 125.570 | 73.751150 | 0 |

Astra loaded debugging/testing skills, read the two source files, and stated
its next action was to add behavioral regressions. Opus loaded the testing
skill, read both files, and created its test-first implementation plan. Neither
asked for approval or edited files. Byte comparisons confirm both retained
work products equal the starting snapshot.

The original dispatcher's `TIMEOUT` label is misleading here: both records have
exit 143, which that parser treats as a timeout. Each raw stream instead ends
with `EVAL_BUDGET_STOP`, emitted by the experiment-local cost wrapper. Both
elapsed times are far below the configured 480 seconds. Adjudication therefore
uses **BUDGET_STOP**, without rewriting the raw records.

Failed acceptance on the unchanged snapshots is not a coding-quality failure:
the controllers were forcibly stopped before they could implement. There is
no basis to call either faster at completing the task or to credit a functional
win. Candidate-authored test quality and mutation sensitivity are not applicable
because neither candidate authored tests.

## Budget Control

An experiment-local `capped-opencode.sh` wrapper sampled completed-step costs
once per second. At 65 credits per arm it terminated the process group. Equal
thresholds left 23.341875 credits beyond both thresholds as reporting-lag
reserve. A fake stream with two steps totaling 70 credits verified the wrapper
stopped with exit 143 before its trailing completion output.

Real costs arrived in large steps. Astra's last recorded step cost 46.0505
credits, bringing its total from 26.1977 to 72.2482; Opus's last step cost
36.655975, bringing its total from 37.095175 to 73.75115. The monitor cannot
stop at exactly 65 when the step reports its cost only after completion.

- Follow-up recorded dispatch spend: **145.999350 credits**.
- Previous screening recorded dispatch spend: **146.658125 credits**.
- Combined recorded dispatch spend: **292.657475 / 300 credits**.
- Remaining recorded allowance: **7.342525 credits**. No more paid runs.

These are raw `step_finish` cost sums times 100, not billing-UI reconciliation.
An interrupted in-flight request may have unreported costs, and parent
orchestration/review usage is not exposed in the dispatch ledger. Thus 292.66 is
the observed harness total, not a guarantee about total account billing.
Before dispatch, `ledger_admit` admitted a 130-credit pair projection and then
65 credits for each arm. These admission commands are recorded in the operator
session, not an independently retained orchestration log.

## Evidence and Verification

`eval/records/astra-build-followup/` retains the protocol, common prompt, oracle,
cost wrapper, ledger, adjudication, historical snapshot, both work products,
and unmodified raw dispatch streams. The original first-screening evidence is
untouched. The wrapper is experimental tooling, not a shared-runner change or
a provider-enforced budget cap.

The follow-up used the same installed OpenCode `1.18.29` and global Superpowers
`v6.3.0` for both models, with direct `--model` and `--variant high` overrides.
The existing dispatcher was invoked with `--timeout 480`, the respective
external `--workspace`, and `--ledger`/`--account followup`. `OPENCODE_BIN` pointed
to the stored cost wrapper. The wrapper resolves real `opencode` through PATH.
Preserved snapshots reproduce oracle checks without Git history. Global skills,
model system prompts, cache state, and provider billing remain external inputs.

Verification logs alongside the records cover snapshot equality, oracle
rejection of both unchanged products, and all four repository suites. The
original regression suite passes on the unchanged snapshot; no new tests exist
to score. Shell syntax and secret scanning are checked separately. No production
installer, shared evaluation runner, or routing profile was changed.

## Recommendation

Keep routing unchanged for lack of completed comparative evidence, **not because
Astra failed to code or asked for approval**. Treat explicit implementation
authorization as a necessary part of future unattended implementation prompts.
Preserve the prior single-shot outcome as evidence about that old protocol, not
as a general reason to reject GPT controllers.

This follow-up was under-budgeted for its context size: both models exhausted
their equal observed-cost thresholds while loading context and planning. A
future larger-task comparison needs a separately approved budget with meaningful
implementation headroom, or a smaller representative fixture. No further spend
or automatic retry is authorized by this result.
