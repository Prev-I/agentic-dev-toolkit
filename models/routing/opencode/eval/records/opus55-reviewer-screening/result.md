# Claude Opus 5.5 vs Opus 5 Reviewer Screening Result

## Result

**Keep Claude Opus 5 high for Reviewer.** Neither model cleared the frozen
quality threshold, so Opus 5.5 cannot replace the incumbent from this evidence.
Routing and the live OpenCode configuration were not changed.

2026-09-24 addendum: the later user cost-management decision in
`../../../docs/decisions/2026-09-24-cost-optimized-routing.md` deliberately changes
Reviewer despite this screening's `KEEP_OPUS_5` verdict. This experiment itself
changed no routing, and its adjudication remains unchanged.

This is a status-quo decision, not evidence that the incumbent is adequate:
Opus 5 also blocked on the benchmark.

| Model | Seeded attribution | Clean material findings | Gate |
|---|---|---:|---|
| Claude Opus 5 high | 3 detected, 1 missed, 1 ambiguous | 0 | BLOCK |
| Claude Opus 5.5 high | 3 detected, 1 missed, 1 ambiguous | 0 | BLOCK |

Both models produced the same deterministic attribution:

| Case | Opus 5 | Opus 5.5 |
|---|---|---|
| R-API | Detected | Detected |
| R-AUTH | Detected | Detected |
| R-BOUNDARY | Missed | Missed |
| R-CONCURRENCY | Ambiguous | Ambiguous |
| R-ERROR | Detected | Detected |
| Clean control | No material finding | No material finding |

R-CONCURRENCY is ambiguous because each model reported two material findings
against `counter.sh`. That case has no witness substring, and the frozen scorer
fails closed when more than one material finding can be attributed to the same
override file. Both models described the second `counter.sh` concern as a
suggestion in other cases but escalated it to material in R-CONCURRENCY.
R-BOUNDARY received no findings from either model.

## Efficiency

Efficiency is secondary because both models blocked functionally.

| Model | Six-call wall clock | Workload credits | Aggregate final tokens |
|---|---:|---:|---:|
| Claude Opus 5 high | 356.017 s | 186.201975 | 189,325 |
| Claude Opus 5.5 high | 203.634 s | 118.533320 | 175,981 |

Opus 5.5 was 42.8% faster and used 36.3% fewer observed workload credits across
the six cases. The challenger capability probe used another 13.277600 credits.
This is a favorable efficiency signal, but the protocol does not allow it to
override failure to clear the Reviewer quality gate.

The efficiency figures are confounded. Opus 5.5's catalog rates are lower, and
aggregate final tokens were only 7.0% lower, so most of the credit reduction was
known pricing rather than measured token efficiency. Opus 5 emitted prose before
the requested JSON in all six responses; Opus 5.5 returned bare JSON in five of
six. The wall-clock difference therefore includes stronger prompt compliance and
lower output verbosity, not just inference speed.

## Execution Integrity

- Opus 5.5 high returned the exact capability response.
- All 12 workload dispatches completed with exit 0, classification `OK`, known
  cost, no provider error, and parseable findings JSON.
- No subagent fallback warning occurred.
- Calls ran in the frozen alternating order.
- The experiment used primary-mode copies of the Reviewer prompt and read-only
  permissions because OpenCode 1.18.31 cannot directly execute a subagent.
- Sanitized resolved configurations are retained under `config/resolved-*.json`;
  model, variant, mode, prompt, and permissions are verbatim, while unrelated
  user identity and absolute or user-identifying paths are removed.
- Fixture integrity passed before dispatch; the runner enforces this under
  `set -e`, although this invocation has no separate retained preflight log.
- The unchanged witness-attribution scorer produced both gate verdicts.

The shared dispatcher stamps the stale historical profile ID
`v1-restored-2026-09`; this is a pre-existing metadata defect. Concrete agent
targets plus the retained resolved configurations establish model identity.

## Budget

- Approved ceiling: 500 credits.
- Observed spend: 318.012895 credits.
- Unused allowance, now closed: 181.987105 credits.
- Calls: 1 capability probe and 12 workload dispatches.
- Retries, replacements, and extra workloads: none.

Credits are runtime-reported USD multiplied by 100. They are not normalized for
cache state or reconciled with the GitHub billing interface. Parent orchestration
and independent audit usage is not included.

## Limits

One run per case is screening evidence, not a reliability estimate. The result
does not establish that Opus 5 and Opus 5.5 are generally equal reviewers; it
establishes that neither met this repository's current deterministic Reviewer
replacement gate on this run. Opus 5.5 remains a credible efficiency-oriented
challenger if a future material trigger justifies a different or strengthened
quality benchmark.
