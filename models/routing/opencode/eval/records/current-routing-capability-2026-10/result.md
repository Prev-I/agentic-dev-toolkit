# Current routing capability — 2026-10-04

## Result and stop boundary

This is successful-call capability evidence, not a quality screening or role
fixture. Routing and global configuration are unchanged. Every executed probe
used the existing dispatcher, the exact active model/variant captured in
`resolved/`, and expected response `CAPABILITY_OK`. There were no retries.

Model/variant values are active-resolution and request-level evidence: the
dispatcher echoes the requested variant; provider streams do not independently
attest the applied reasoning effort. Debug inventories were reduced with
`reduce-inventory.py` to model/variant/mode, tools.task and ordered Task rules;
unrelated prompts and host external-directory paths were omitted.

| Role | Model | Variant | Successful inference | Budget accounting |
|---|---|---|---|---|
| plan | `github-copilot/claude-opus-5.5` | xhigh | PASS | 1.3711 credits |
| general | `github-copilot/gpt-6.1-sol` | medium | PASS | 0.1888 credits |
| compaction | `github-copilot/claude-sonnet-5.5` | low | PASS | 0.68655 credits |
| title | `github-copilot/gpt-6-luna` | low | PASS | 0.00942 credits |
| summary | `github-copilot/gpt-6-luna` | low | PASS | 0.00942 credits |
| expert | `openai/gpt-6-astra` | xhigh | PASS | Unavailable; stop |
| breakglass | `openai/gpt-6.1-sol` | max | NOT_RUN | Prior accounting stop |

The five Copilot probes total **2.26529 observed credits** against the authorized
150-credit ceiling, with `ledger_admit(..., 20)` before each call. Expert used
direct OpenAI and returned the exact response, but the dispatcher intentionally
returns `derived_credits: null` for non-Copilot providers. OpenAI runtime reports
`observed_cost: 0`; that is not billing reconciliation or proof of free usage.
The unknown/accounting-unavailable cost stop condition therefore fired, and
Breakglass was not dispatched. No overall reconciled credit total can be claimed
for the six paid/provider calls from this accounting mechanism.
The 20-credit admission of the Expert probe checked the Copilot ledger only;
it could not bound direct-OpenAI usage. This accounting limitation was identified
before dispatch, so the stop at Expert was predictable and Breakglass could not
be reached under the chosen strict stop contract.

## Breakglass boundary

`check-breakglass.sh` uses the existing `capture_agent_permissions` helper and
the ordered fnmatch rule mechanism from `capture_breakglass_non_exposure`,
adapted to the current model instead of the historical GPT-5.6 pin. It captures
actual build/plan/general/Breakglass rules and inventory using debug commands,
not Task or a model call. The current primary remains direct OpenAI Sol 6.1 max
and cannot be delegated to via Task. This is boundary evidence, not successful
inference for Breakglass.
The resolved-rule check covers build, plan, general and Breakglass itself, not
every installed agent; other agent boundaries were not freshly checked here.

## Remaining gap

Breakglass successful-call evidence remains missing. Completion requires an
explicitly agreed direct-OpenAI accounting convention before another probe;
changing provider to Copilot, treating null as zero, or reusing unused credits
silently would violate the approved boundary. All six completed probes establish
only model inference capability; role fitness is still unverified.
