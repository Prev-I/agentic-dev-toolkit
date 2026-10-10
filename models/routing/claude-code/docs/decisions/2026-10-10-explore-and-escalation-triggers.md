# Explore and Escalation Triggers

## Decision

`model-routing.md` gains two triggers. No model, effort or agent file changes.

1. **Dispatch rule 5.** "If you can dispatch subagents, a codebase search
   goes to `Explore` whenever you do not yet know which file holds the answer,
   including when a skill tells you to explore the code: dispatch it before
   your own first Grep, Glob or search command. Search yourself only inside
   files you have already located. Producing the history file rule 4 asks for
   is not such a search."
2. **Escalation by framing.** Conditions 2 (security-sensitive design) and 5
   (public API surface changes) also hold when the human presents a decision
   that way, even if Build judges it is not. Build escalates instead of
   settling it, gives its own view beside the expert's, and says where it
   disagrees with the framing. "A human who tells you not to escalate has
   opted out."

Dispatch rule 3 gains one exception, for the framing paragraph only: "Do not
send work to `expert` that `reviewer` or Build can settle, unless the human's
framing requires it". The ten conditions keep their relation to rule 3 as
before; only the framing extends 2 and 5.

## Rationale

- **Smoke tests 1 and 4 failed on the installed profile.** Evidence S1: asked
  where `DRIFT` is computed, Build searched with four shell commands and never
  dispatched `Explore`. Presented with an open security decision on the pin
  hook's failure mode, Build recommended fail-open itself; `expert` ran only
  when the human asked for a second opinion. Both answers were reasonable, and
  the expert consultation then found an issue Build had not: the hook's
  `python3 -c` imported modules from the session's directory, fixed by
  [The Hook Runs Python Isolated](2026-10-10-hook-runs-python-isolated.md).
- **Why Build settled the escalation itself.** It judged the hook not to be a
  security control, so condition 2 did not hold in its view, and rule 3 told
  it not to send `expert` work it could settle. The human's framing carried no
  weight. Making the framing sufficient keeps the decision with the person
  who asked, and the cost bounded: an escalation is one `expert` run, capped at
  six turns.
- **Why the Explore rule names the moment.** A first wording, "Send a codebase
  search to `Explore` unless you already know which file holds the answer and
  one or two lookups settle it", changed nothing: three runs out of three
  searched directly, one of them with four lookups (evidence D1). Naming the
  moment, before the first search command, moved three runs out of three to
  `Explore`, while a control naming the file stayed direct in three out of
  three. The moment is not honoured literally: in every such run Build first
  grepped the one file it expected to hold the answer, found nothing, and
  only then dispatched. One lookup in an expected file is accepted here; a
  stricter "located" risks dispatching for files Build can name outright.
- **Who the rule binds.** The policy is loaded by subagents too, and rule 5 is
  the first rule about the reader's own tool use. Opening it with "If you can
  dispatch subagents" keeps `Explore`, `scout`, `reviewer` and `expert`, which
  cannot, from being told to wait for a dispatch they cannot make.
- **The opt-out is explicit.** An earlier draft let "a human who asks for your
  view without an escalation" opt out, which any request for a recommendation
  would satisfy, including the one in smoke test 4. Only an explicit
  instruction not to escalate opts out.
- **Search stays with Build once the file is located.** Reading or grepping a
  known file is cheaper than a dispatch, and Build still checks what `Explore`
  reports: in every D1 run of the committed rule on test 1, it read the cited
  lines itself before answering.

## Consequences

- More `Explore` dispatches during exploratory work, each a Haiku 5.5 run, and
  more `expert` runs on decisions the human frames as security or public API,
  each a Fable 5.1 run billed to usage credits on this account. The README's
  deviation 8 records both, since the OpenCode policy states neither.
- The triggers are prompt rules, not mechanisms. D1 is two or three runs per
  case on one prompt each, in `claude -p` with project and local settings
  only; it shows the wording moves the decision, not that it always will.
- No `general-purpose` run under rule 5 was observed. A subagent that can
  dispatch would follow it like Build.
- An installed profile needs the policy re-copied; until then the alignment
  check reports it as `STALE`.

## Evidence boundary

Evidence S1 and D1 in
[`../evidence/2026-10-10-dispatch-triggers.md`](../evidence/2026-10-10-dispatch-triggers.md),
on Claude Code 2.1.296. No documentation claim is made here: both triggers
are policy, observed in use.

Later corrections are appended as dated addenda, never edited in place.
