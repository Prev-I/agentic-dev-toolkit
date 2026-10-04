# Reviewer fixture v2 — POST_RUN_DIAGNOSTIC

This new fixture is a post-run diagnostic repair and design input for future
screenings. It does not adjudicate or rescore any historical v1 finding.

V2 is a different benchmark, not a comparable rerun of v1: both visible contracts
are new (`pagination_contract.sh` and `counter_contract.sh`), zero is explicitly
named as invalid, and the concurrency seed changes from absent Bash locking to
premature Python unlocking. Detection rates across versions are not comparable.
The added pagination context addresses an observability gap; it tests a future
hypothesis and does not prove that missing context caused the historical misses.

## Clean counter proof

The v1 clean implementation ignores a failed read. The non-root permission test
creates a counter containing `41`, sets mode `0200` (writable, not readable), and
invokes the unchanged v1 function. It returns success, emits a read error, and
replaces the counter with `1`. The v2 clean and seeded functions both return an
error and preserve `41` under the same conditions. They also reject invalid
ASCII-decimal contents without writing them. Python integer parsing avoids Bash
arithmetic expression evaluation and overflow ambiguity.

This does not prove the clean control free of every material defect. Its
`write_text` truncates before writing; a partial write failure can lose data even
though the error is reported. Atomic replacement is not implemented. The clean
proof is bounded to read failures, invalid contents and the existing known
detectors, with this residual exposed for future fixture design.

## Shared missed case

The preserved attribution records for Opus 5, Opus 5.5, GPT-6 Astra, and GPT-6.1
Sol all show `R-BOUNDARY: missed`. The hidden v1 ground truth specifies 1..100,
but the visible sandbox contains no pagination contract stating that zero is
invalid. This is insufficient context to classify the miss as a pure model
limit. V2 adds `pagination_contract.sh` to every clean/case sandbox, like the
existing public API contract. The behavioral proof rejects zero in clean and
accepts it in the boundary seed. No historical response is evaluated on v2.

## Concurrency attribution

The v2 counter checks read/write errors and input validity in both variants.
Only the concurrency variant releases its exclusive lock before the complete
read-modify-write. Its witness is `fcntl.flock(lock, fcntl.LOCK_UN)`, present in
the override and absent from clean. This exposes the unsafe synchronization
boundary without using an incidental helper name as evidence.

The v2 scorer keeps witness matching and the 5/5 plus clean-zero threshold.
Unrelated same-file findings do not match this witness. Zero matching findings
is missed; one is detected; multiple matching findings remain ambiguous. A quote
containing the witness for an unrelated semantic claim is still a residual risk
of exact-snippet attribution, not proof of semantic correctness. The static
lock-boundary check is not a proof of linearizability or filesystem safety.
There is also a false-negative risk: a correct race finding quoting just
`fcntl.LOCK_UN` or the read line, rather than the full witness call, scores as
missed under the exact snippet contract. Fail-closed attribution remains strict;
decidability applies to findings that actually include the frozen witness.

Proof: `bash models/routing/opencode/eval/tests/reviewer-fixture-v2-test.sh`.
The v1 fixture, scorer and historical adjudications are unchanged.
