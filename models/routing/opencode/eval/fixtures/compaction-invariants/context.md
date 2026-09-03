# Synthetic Routing Conversation

The team compared editor themes and discussed whether logs should use colors.
Those details do not affect restoration. The runtime decision is `[INV-RUNTIME]
target_runtime=opencode-v1` and remains binding.

An early note suggested naming a helper "panic mode". That wording was dropped.
Breakglass access is fixed separately: `[INV-BREAKGLASS]
breakglass=primary-human-only`.

Several participants discussed how many routine evaluation calls might be useful.
The reserved recovery allocation is not part of that pool: `[INV-BUDGET]
phase-r-recovery-budget=250-credits-non-reclaimable`.

The meeting also covered README headings, temporary branches, and timestamps.
One state-machine rule must survive any summary: `[INV-FAILURE]
valid-controller-failure=remains-in-denominator`.

Repeated low-value scheduling details and superseded naming proposals may be
discarded by compaction.
