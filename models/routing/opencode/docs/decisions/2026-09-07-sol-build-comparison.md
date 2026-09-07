# Sol High Build Comparison

## Result

**Sol completed the pre-approved real Build task, but its patch has an
empty-PATH preservation defect.** It is a viable contender, not a review-clean
replacement for Opus or an established winner over Astra. Routing is unchanged.

The user approved the same budget as the last evaluation: a new independent
500-credit ceiling. One fresh `github-copilot/gpt-5.6-sol` / `high` dispatch used
**98.645680 credits** and **216.400 seconds**. No approval pause, delegation,
timeout, or cost stop occurred. The 401.354320 unused credits are closed rather
than spent on unsolicited retries.

## Common Task

Sol received byte-identical `astra-build-followup/prompt.txt` and the three-file
historical snapshot from commit `7605022`, in a new external workspace without
Git history. The task explicitly authorizes implementation without another
design-approval pause and asks for guarded managed PATH prepends at bootstrap,
in the generated Bash block, and on current-process refresh, plus focused tests.

OpenCode remained `1.18.29`; the filtered resolved global configuration confirmed
Superpowers `v6.3.0`, global Build Opus 5/high, and no configured MCP servers in
the sandbox. A direct model override selected Sol; no routing or permission
configuration was modified. Model discovery listed Sol. The successful role
dispatch establishes capability without an additional trivial paid probe.

The saved Astra and Opus attempts supply historical comparison, not freshly
rerun controls. Sol had one uninterrupted attempt, a 400-reported-credit stop
threshold with 100 reserved for reporting lag, and the same 480-second timeout.
Astra and Opus had lower stops and were interrupted/resumed. This intentionally
avoids repeating budget exhaustion, but is **not an equal-budget three-way trial**.

## Verification

Sol changed only the two permitted files. Production uses one small helper for
bootstrap/refresh and a self-contained loop in the generated block. It added
behavioral tests while retaining existing test calls.

| Check | Sol Result |
|---|---|
| Frozen five-scenario oracle, all three PATH sites | PASS |
| Untouched original test suite against submitted installer | PASS |
| Candidate-authored suite | PASS |
| Candidate tests against historical broken installer | FAIL as expected |
| Syntax checks | PASS |
| Review-discovered entirely empty PATH case | FAIL at all three sites |

The mutation failure specifically detects nonexistent directories and duplicate
exact entries. Raw evidence shows a red test before production edits, followed
by corrections to its test fixtures so necessary utilities remain resolvable.
These corrections did not introduce Astra's suite-wide WSL override.

## Review Findings

**Important: entirely empty PATH loses its existing empty entry.** Candidate
`environments/linux/install.sh:68` uses:

```bash
PATH="$managed_dir${PATH:+:$PATH}"
```

When PATH is empty, the conditional expansion drops the colon. The former
empty/current-directory component is no longer preserved. The generated block
repeats this at line 412; the helper serves both bootstrap and refresh. That
violates the stated requirement not to remove existing entries. Nonempty PATHs
with embedded empty components do not suffer this specific defect.

The independent reviewer identified this gap in both the candidate tests and
the frozen oracle. The evaluator then added `empty-path-check.sh` as an explicitly
**post-review diagnostic**, without changing the original oracle or candidate.
It fails at all three sites on Sol and passes on saved Astra and the historical
known-good fix. For the refresh case, narrowly scoped absolute-path utility
wrappers allow real temporary-HOME configuration I/O with PATH empty; they do
not change or stub the PATH logic being tested. The submission was not repaired.

**Minor: generated shell block clobbers `_adt_path_dir`.** Its top-level loop
uses and unsets that variable rather than preserving an existing same-named user
variable. The prefixed name reduces collision likelihood, but it is a residual
shell-state side effect.

Unlike Astra, Sol did **not** add a suite-wide `ADT_FORCE_WSL=0`. The existing
scoped credential-test overrides and teardown remain intact. Review found no
analogous weakening of WSL verification coverage. This does not make its suite
complete: the empty-PATH defect was missed.

## Three-Model View

| Model at High | PATH-Task Credits | Active Seconds | Observed Result |
|---|---:|---:|---|
| GPT-5.6 Sol | 98.645680 | 216.400 | Completed; empty-PATH contract defect |
| GPT-6 Astra | 157.695250 | 165.966 | Completed; WSL test-coverage regression |
| Opus 5 | 169.517375 | 208.883 | Budget-stopped before production implementation |

Astra/Opus totals include their initial PATH run and continuation, not idle time
or the earlier tiny-fixture screening. Sol used less recorded cost than those
saved task totals, but took longer than Astra's summed active dispatch time.
These are observations only: differing interruptions, cache state, context,
ceilings, and run order prevent a controlled efficiency ranking.

The substantive comparison is mixed. Astra preserves the reviewed empty-PATH
behavior but weakens an unrelated test branch. Sol retains that test setup but
introduces a real edge-case behavior change. Opus supplied no completed production
patch and must not be called a coding failure on that basis. One historical Bash
task cannot establish a generally superior main Build agent. The historical fix
was co-authored by Opus, and prior exposure cannot be excluded even though neither
its patch nor history was supplied to candidates.

**Recommendation:** keep Sol and Astra in contention under explicit implementation
authorization. Neither should be rejected because older prompts caused approval
stops. Neither submission is ready for unchanged adoption. Keep routing unchanged
until broader completed evidence and a controller/reviewer family-separation
decision support a replacement.

## Provenance

Everything for this extension is under `eval/records/sol-build/`: pre-dispatch
protocol, exact prompt, cost wrapper, ledger, raw stream, final work product,
test logs, post-review diagnostic, and machine-readable adjudication. Previous
evidence is untouched. No commit or PR was requested.

The runner invocation sourced the existing `dispatch-fixture.sh`, admitted a
400-credit projection with `ledger_admit`, and set `OPENCODE_BIN` to the stored
wrapper. Arguments were `--label sol-path-guards`, the saved `--prompt-file`,
`--model github-copilot/gpt-5.6-sol --variant high`,
`--workspace /tmp/opencode/path-eval-c --timeout 480`, and the new ledger with
`--account sol_build`. The wrapper was checked with a fake two-step 410-credit
stream and stopped before its trailing completion output. It preserves raw
output on exit; it is experiment-local, not a shared runner change.

Raw evidence contains 18 completed steps, no error events, and session
`ses_f843c26f4ffeeo7u4WIspfE171`. Their costs independently sum to 98.645680
credits under the existing USD-times-100 convention. No cost normalization or
aggregate token accounting is claimed. The figure is not reconciled against the
billing UI and excludes parent orchestration/review usage, which the ledger does
not expose. Cost monitoring is post-step, not a provider-enforced hard cap.

All four repository suites are rerun with logs retained as `verification-*.log`.
Candidate syntax and scope checks, secret scanning, JSON validation, and absence
of production/routing diffs are checked separately. The new empty-PATH diagnostic
is evidence about a submitted patch, not a production fix.
