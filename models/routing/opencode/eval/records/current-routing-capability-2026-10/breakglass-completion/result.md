# Breakglass successful-call completion

Date: 2026-10-04. Result: **PASS**.

One request to the experiment-only primary `breakglass-capability-only` returned
exactly `CAPABILITY_OK`. Its resolved target was `openai/gpt-6.1-sol`, requested
variant `max`. Its explicit edit/bash/task denies, last action per pattern,
tools map and ordered Task rules matched active Breakglass before dispatch. The
comparison does not prove order equivalence between different overlapping
external-directory patterns. No Task
invocation, routing change or global configuration write occurred.

The preflight found OpenAI OAuth access/refresh metadata and an account ID;
no API-key credential field, OPENAI_API_KEY environment variable or resolved
OpenAI provider options were present. Credential values and account identifiers
were not retained. This identifies the active subscription connection, not
independent billing reconciliation. The historical Expert dispatch was not
independently authenticated at its original dispatch time; its retrospective
classification follows the user's explicit subscription-account instruction.

## Accounting

`ledger.json.subscription_account` is separate from Copilot credits:

- unit: `calls`, defined as **primary probe dispatches**, not every provider request;
- basis: **subscription quota, not metered consumption spend**;
- historical Expert usage: one call, excluded from the new allowance;
- new Breakglass allowance: one call, consumed 1/1;
- total retained primary subscription probe dispatches: two;
- `derived_credits: null` allowed only under this explicit subscription account.

The call was reserved in the ledger before dispatch. Existing `started.json`
or dispatch output refuses a second request, including after interruption.
The preceding permissions preflight stopped without reservation or dispatch
because independently discovered skill path rules had a different ordering;
the final comparison retained effective per-pattern values and exact ordered
Task rules. This was not a model retry.

Runtime token snapshot: total 9650, input 9589, output 9, reasoning 52, cache
read/write 0. Expert's unchanged historical snapshot reports total 927, input
905, output 9, reasoning 13. These are metadata as reported by the runtime,
not a billing measure or a claim of cumulative per-session token attribution.
Runtime cost 0 is not proof of free use, and no conversion to Copilot credits
was made. Ledger-observed Copilot spend remains 2.26529 credits; one auxiliary
Copilot title request from the Breakglass session is unmetered by this ledger.

### Auxiliary provider requests — POST_RUN_DIAGNOSTIC

Sanitized operational-log excerpts in `auxiliary-request-evidence.json` show
that OpenCode generated a session title in addition to each main probe stream:
the historical Expert session used OpenAI GPT-6 Astra for its title, while the
Breakglass session used Copilot GPT-6 Luna. These requests have no cost or token
metadata in the retained dispatcher outputs. Thus there are three observed
OpenAI provider requests across the two sessions (two historical Expert streams,
one new Breakglass stream), plus one new auxiliary Copilot title stream. The
new OpenAI allowance was consumed by exactly one new primary request; the
historical auxiliary OpenAI request is excluded along with historical Expert
usage. The ledger is not an exhaustive provider-request or billing ledger.

## Evidence boundary

The successful-call gap is closed for the active Breakglass model with the
requested variant and equivalent primary permissions. The provider stream does
not independently attest reasoning-effort application. This is not role fitness,
a recovery exercise, or a quality promotion. Historical stopped-run summaries
remain unchanged; this completion supplements them. Existing Task non-exposure
evidence still covers build, plan, general and Breakglass itself.

The experimental agent has a separate identity/prompt context; it is not the
entire production agent. Model override/variant arguments recorded by the shared
dispatcher are request metadata: in its agent path the actual target comes from
the resolved experiment config. The operational log confirms OpenAI Sol 6.1
served the primary stream, but does not attest applied reasoning effort.
Quota classification recognizes error events/status 429, not every possible
stderr-only quota message or timeout. No such error occurred. Harness retries
are forbidden; OpenCode's own provider retry behavior is not independently
controlled by this script.
