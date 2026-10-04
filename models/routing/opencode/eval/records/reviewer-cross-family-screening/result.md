# Reviewer Cross-Family Quality Screening Result

## Result

**No challenger passes the frozen quality threshold.** Both GPT-family
challengers reproduced the historical Opus 5.5 attribution of three detected,
one missed and one ambiguous seeded defect. Astra preserved clean-zero; GPT-6.1
Sol produced one material finding on the clean control.

That clean-control finding is substantively correct: `clean/counter.sh` does not
check a failed read before overwriting the counter. The frozen clean-zero
contract still counts it against the Sol arm. This is a fixture/criterion
limitation, not evidence that the finding was hallucinated; rescoring is
forbidden, and Sol also remains below the seeded threshold.

| Model | Seeded attribution | Clean material | Gate |
|---|---|---:|---|
| Historical Opus 5.5 high | 3 detected, 1 missed, 1 ambiguous | 0 | BLOCK |
| GPT-6 Astra xhigh | 3 detected, 1 missed, 1 ambiguous | 0 | BLOCK |
| GPT-6.1 Sol high | 3 detected, 1 missed, 1 ambiguous | 1 | BLOCK |

Neither challenger is a credible candidate under the preregistered rule because
neither improves beyond the historical three detections. No Reviewer routing
decision is unlocked, and routing remains unchanged.

## Cost And Time

| Model | Workload credits | Workload wall clock |
|---|---:|---:|
| GPT-6 Astra xhigh | 59.89065 | 356.922 s |
| GPT-6.1 Sol high | 11.32015 | 130.512 s |

Observed total spend including both capability probes was `74.9994` credits
against the approved `805` ceiling. Efficiency is descriptive only because
functional quality blocked both arms.

## Limitations

The historical reference used OpenCode 1.18.31 and a different runner/plugin
context. One dispatch per case does not establish reliability. R-CONCURRENCY
remains fail-closed ambiguous and R-BOUNDARY remains missed. Credits are
runtime-reported completed-step accounting, not provider-billing reconciliation.
Reviewer workload model attribution rests on the retained resolved-config
snapshots because agent-dispatch ledger rows do not carry a provider or concrete
variant.
