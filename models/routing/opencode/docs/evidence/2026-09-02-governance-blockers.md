# OpenCode V1 Governance Decisions - 2026-09-02

This record originally surfaced unresolved governance blockers. The following
decisions were supplied by the accountable human owner and close the local
routing-governance blockers. No ownership is inferred from repository metadata.

## LOCAL_ROUTING_GOVERNANCE

### Operational ownership

Status: `RESOLVED`

- Operational owner: repository owner / toolkit maintainer / assigned user.
- Responsibilities: agent configuration, routing implementation, migration
  execution, and local operational decisions.

This ownership does not imply additional enterprise responsibilities.

### OpenCode V2 RFC ownership

Status: `RESOLVED`

- RFC owner: repository owner / routing-toolkit maintainer.

The RFC owner opens the separate OpenCode V2 migration RFC when either approved
trigger occurs:

1. Upstream promotes V2/2.x to stable/default and V1 enters maintenance or deprecation.
2. Remaining on V1 blocks a required capability or security remediation.

This is ownership of the future RFC trigger only; it is not approval to begin
an OpenCode V2 migration.

### GitHub Copilot spend governance

Status: `RESOLVED`

- Spend owner: responsible corporate manager.
- Agent operational owner: repository/toolkit owner.
- Paid/overage usage: `ALLOWED`.
- Authorized consumption guardrail: approximately 4x the current standard
  GitHub Copilot Business allowance per billing cycle.
- Guardrail nature: organizational/billing governance constraint, not an
  OpenCode-native enforcement mechanism.
- Behavior at guardrail or allowance exhaustion: stop and escalate to the
  spend owner; no automatic fallback to a cheaper model.

Historical observation, not a forecast:

```text
OBSERVATION: 331 AI credits consumed on 2026-09-01
```

The actual GitHub billing configuration remains an external organizational
control. This organization-level guardrail is distinct from the project eval
budget and the Phase-R bisection/recovery budget; neither budget is established
by this record.

### Direct OpenAI spend and operational governance

Status: `RESOLVED`

- Spend owner: responsible corporate manager.
- Agent operational owner: repository/toolkit owner.
- Credential rotation/revocation authority: corporate information systems / IT.
- Approved usage boundary: this R&D workload is permitted; no additional
  workload-specific restriction has been identified.
- Revocation/escalation path: corporate information systems / IT for
  credentials; responsible corporate manager for spend.

This is sufficient local routing governance for this project. No account
identifiers, credentials, contract material, or other sensitive governance data
is recorded in this repository.

## EXTERNAL_ORGANIZATIONAL_CONTROLS

Status: `EXTERNAL_ORGANIZATIONAL_CONTROL`

The following controls remain owned outside this repository and are not local
routing-governance blockers:

- enterprise contractual/DPA coverage;
- enterprise retention and data-use policy;
- enterprise-wide AI and data-governance policy;
- technical enforcement in the GitHub billing system.

## Phase-0 status

The local governance blockers recorded by this document are resolved. Phase 0
remains incomplete because the approved decision requires additional technical
and governance-gate work outside this record. This document does not authorize
Phase R.
