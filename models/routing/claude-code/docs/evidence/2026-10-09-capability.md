# Claude Code Routing Capability Evidence — 2026-10-09

Claude Code 2.1.295, 2026-10-09. The 2026-10-06 evidence was taken on 2.1.291,
so the mechanism probes the bundle depends on were repeated before any model
change. Method as in [`2026-10-06-capability.md`](2026-10-06-capability.md):
`claude -p` in a scratch project whose `.claude/` held probe copies of the
agents, each probe agent on a different model from its session, read through
`modelUsage` in the JSON output.

One difference: the routing bundle is now installed under `~/.claude`, and its
user-level hook would contaminate the no-hook control. Every probe therefore
ran with `--setting-sources project,local` and without the parent session's
`CLAUDE_*` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` variables, so no user setting,
hook or env applied. Nothing under `~/.claude` was changed.

## Mechanism probes, repeated

| Probe | Question | Setup | Observed | Verdict |
|---|---|---|---|---|
| P1 | Does a per-call `model` beat frontmatter? | Sonnet session; probe `reviewer` on Haiku 4.5; dispatch with `model: "sonnet"`; no hook | `modelUsage`: `claude-sonnet-5-5` only; reviewer answered `PONG` | `CONFIRMED` |
| P2 | Does the hook pin the frontmatter model? | Same as P1, with `pin-agent-model.sh` registered as a project `PreToolUse` hook on `Agent` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5`; reviewer answered `PONG` | `EFFECTIVE`, with no `permissionDecision` |
| P3 | Does a project `Explore.md` override the built-in? | Haiku 4.5 session; probe `Explore` on Sonnet; dispatch without `model` | `modelUsage`: `claude-haiku-4-5`, `claude-sonnet-5-5` | `OVERRIDES` |
| P4 | Does `--agent` apply the agent model to the main thread? | `claude -p --agent planner`, probe planner on Haiku 4.5, no `--model` | `modelUsage`: `claude-haiku-4-5` only; result `OK` | `APPLIES` |
| P5b | Is a plain `tools` allowlist enforced? | Probe reviewer `tools: Read, Grep, Glob`; session `--allowedTools Bash Write Edit`; reviewer asked to Write `written-probe` and `touch touched-probe` | Neither file created; reviewer reported only Read, Grep and Glob available | `ENFORCED` |

Every verdict matches 2.1.291. P5 was not repeated: its outcome only removed
`Bash(...)` patterns, and P5b covers the allowlist that replaced them.

## Successful-call capability

`claude -p --model <id> [--effort <level>] --output-format json 'Reply with exactly OK'`:

| Model | Effort | Role | is_error | result | modelUsage |
|---|---|---|---|---|---|
| `claude-haiku-5-5` | `medium` | Explore | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-haiku-5-5` | `low` | Scout | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-fable-5-1` | `xhigh` | Expert (proposed; the profile still runs Opus 5.5 `max`) | `False` | `'OK'` | `claude-fable-5-1` |

The Fable call that failed on 2026-10-06 with "Fable 5.1 requires usage
credits" now succeeds.

## Haiku slot

`ANTHROPIC_DEFAULT_HAIKU_MODEL` decides what the `haiku` alias resolves to,
which is the model Claude Code uses for background functionality. Calls with
`--model haiku`, no effort:

| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | is_error | result | modelUsage |
|---|---|---|---|
| `claude-haiku-5-5` | `False` | `'OK'` | `claude-haiku-5-5` |
| `claude-haiku-4-5` (control) | `False` | `'OK'` | `claude-haiku-4-5` |
| unset | `False` | `'OK'` | `claude-haiku-5-5` |

The control shows the variable is what selects the model. Unset, the alias
already resolves to Haiku 5.5 on the Anthropic API, as the model configuration
documentation states; the fragment pins it so the profile does not move with
Claude Code's default.

No background task was observed directly: a `-p` run gives no reliable trigger
for one. What is shown is that the slot resolves to the pinned model.

## Dispatch from a Build session

Build session `--model claude-opus-5-5 --effort high`, the hook registered,
probe copies of the agents as committed (`Explore`: `claude-haiku-5-5`,
`effort: medium`; `scout`: `claude-haiku-5-5`, `effort: low`). Each was
dispatched the way Superpowers does, with an explicit `model: "sonnet"`, and
logged with `--debug-file`. The session's haiku slot was set to
`claude-haiku-4-5`, so a background request or a built-in agent on the `haiku`
alias would show as Haiku 4.5, and `claude-haiku-5-5` can only come from the
agent's frontmatter.

| Agent | Hook in the debug log | Model dispatches in the debug log, in order | modelUsage | Result |
|---|---|---|---|---|
| `Explore` | `modified tool input keys: [description, prompt, subagent_type, run_in_background]` (`model` removed) | `claude-opus-5-5`, hook, `claude-haiku-5-5` ×2, `claude-opus-5-5` | `claude-haiku-5-5`, `claude-opus-5-5` | listed the directory |
| `scout` | same keys, `model` removed | `claude-opus-5-5`, hook, `claude-haiku-5-5`, `claude-opus-5-5` | `claude-haiku-5-5`, `claude-opus-5-5` | `PONG` |

**Model: `VERIFIED`.** The frontmatter model applies: `sonnet` never appears,
and neither does the slot's `claude-haiku-4-5`.

**Effort: `NOT_OBSERVABLE`**, as P6 was on 2.1.291. The debug log names each
request's model and no effort value. A repeat of the scout dispatch with
`ANTHROPIC_LOG=debug` shows the Haiku 5.5 request carrying an `output_config`
body field and the `effort-2025-11-24` beta, but the SDK log collapses the
field to `[Object ...]`, so the value cannot be read. The field is kept: it is
documented, and nothing reported it as unknown.

## Evidence boundary

Discovery and successful-call evidence only; no role-fixture evidence. Haiku
5.5's fitness for Explore and Scout, and Fable 5.1's for Expert, are not shown
here.

## Addendum — 2026-10-09 Expert dispatch on Fable 5.1

Recorded with the [Expert on Fable 5.1](../decisions/2026-10-09-expert-on-fable-5-1.md)
decision. Same setup as the Build-session dispatch above, with the probe
`expert` as committed (`claude-fable-5-1`, `effort: xhigh`, `maxTurns: 6`),
dispatched with `model: "sonnet"` and asked to reply `PONG`:

| Agent | Hook in the debug log | Model dispatches in the debug log, in order | modelUsage | Result |
|---|---|---|---|---|
| `expert` | `modified tool input keys: [description, prompt, subagent_type, run_in_background]` (`model` removed) | `claude-opus-5-5`, hook, `claude-fable-5-1`, `claude-opus-5-5` | `claude-fable-5-1`, `claude-opus-5-5` | `PONG` |

`-p` asks for no consent before billing usage credits, so this shows the route
works, not how an interactive session's consent prompt behaves on a subagent.

## Addendum — 2026-10-09 effort observed on the wire

The effort verdicts above are `NOT_OBSERVABLE` because neither the debug log
nor the SDK log shows `output_config`'s contents. A local pass-through proxy
makes them observable: Claude Code runs with
`ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`, and the proxy forwards every
request to `api.anthropic.com` unchanged, logging only each Messages request's
`model`, `output_config` and `thinking`. It never logs headers, so no
credential is written anywhere.

<details>
<summary>The proxy</summary>

```python
"""Local pass-through proxy to api.anthropic.com that logs, per Messages
request, only the path and the model, output_config and thinking fields of the
JSON body. Headers (and therefore credentials) are forwarded but never logged.

usage: python3 -I effort_proxy.py PORT LOGFILE
"""
import http.client
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "api.anthropic.com"
HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "te",
       "trailer", "upgrade", "host", "accept-encoding", "content-length"}
port, logfile = int(sys.argv[1]), sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _forward(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        if self.path.startswith("/v1/messages") and body:
            try:
                data = json.loads(body)
                record = {"path": self.path.split("?")[0], "model": data.get("model"),
                          "output_config": data.get("output_config"),
                          "thinking": data.get("thinking")}
            except ValueError:
                record = {"path": self.path, "unparsed": True}
            with open(logfile, "a") as fh:
                fh.write(json.dumps(record) + "\n")
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        headers["accept-encoding"] = "identity"
        conn = http.client.HTTPSConnection(UPSTREAM, timeout=600)
        conn.request(self.command, self.path, body=body or None, headers=headers)
        resp = conn.getresponse()
        self.send_response(resp.status, resp.reason)
        for k, v in resp.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.send_header("transfer-encoding", "chunked")
        self.end_headers()
        while True:
            chunk = resp.read1(65536)
            if not chunk:
                break
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        conn.close()

    do_POST = do_GET = do_PUT = do_DELETE = do_PATCH = _forward


ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
```

</details>

Sanity check: `--model claude-haiku-5-5 --effort low` logged
`{"model": "claude-haiku-5-5", "output_config": {"effort": "low"}}`.

### E1 — frontmatter effort on dispatch

Same setup as the Build-session dispatch above (Opus 5.5 `--effort high`, hook
registered, `model: "sonnet"` on each dispatch), through the proxy:

| Agent | Frontmatter | Requests logged, in order | Verdict |
|---|---|---|---|
| `scout` | `claude-haiku-5-5`, `low` | Opus 5.5 `high`; Haiku 5.5 `low`; Opus 5.5 `high` | `VERIFIED` |
| `Explore` | `claude-haiku-5-5`, `medium` | Opus 5.5 `high`; Haiku 5.5 `medium`; Opus 5.5 `high` | `VERIFIED` |
| `expert` | `claude-fable-5-1`, `xhigh` | Opus 5.5 `high`; Fable 5.1 `xhigh`; Opus 5.5 `high` | `VERIFIED` |
| `expert`, user settings loaded¹ | `claude-fable-5-1`, `xhigh` | Opus 5.5 `high`; Fable 5.1 `xhigh`; Opus 5.5 `high` | `VERIFIED` |

¹ `--setting-sources user,project,local`, no `--effort`, no `model` on the
dispatch. The real `~/.claude/settings.json`, read only, holds a top-level
`"effortLevel": "high"`, which the settings reference says still applies to
Fable 5.1; the frontmatter's `xhigh` wins over it.

Frontmatter `effort` is applied, and the session's `high` does not leak into
the subagent. This supersedes the `NOT_OBSERVABLE` effort verdict above.

### E3 — a top-level `effortLevel` in user settings

`claude -p 'Reply with exactly OK'` with no `--effort`. "User settings" is the
real `~/.claude/settings.json`, read only: it holds a top-level
`"effortLevel": "high"` and `modelSettings.claude-opus-5-5.effortLevel: "high"`.

| Setting sources | Model | Effort sent |
|---|---|---|
| user | `claude-opus-5-5` | `high` (from `modelSettings`) |
| user | `claude-sonnet-5-5` | `medium` |
| user | `claude-haiku-5-5` | `medium` |
| project only | `claude-opus-5-5` | `medium` |
| project, `--settings '{"effortLevel":"high"}'` | `claude-opus-5-5` | `high` |
| project, `--settings '{"effortLevel":"high"}'` | `claude-haiku-5-5` | `high` |
| project, `--settings '{"effortLevel":"high"}'` | `claude-sonnet-5-5` | `high` |

In user settings the top-level key reached neither 5.5 model that had no
`modelSettings` entry, while the same key passed with `--settings` reached
all three 5.5 models. Opus 5.5 with no settings runs `medium`. This matches
the settings reference: in `~/.claude/settings.json` the key "keeps applying
where it applied before, on Opus 5, Fable 5.1, and earlier models. Opus 5.5 and
models released after it ignore it".
(<https://code.claude.com/docs/en/settings-reference#effortlevel>) The
fragment's top-level `effortLevel` therefore left Build at `medium` wherever the
user had not saved a level for Opus 5.5. The Opus 5.5 row cannot isolate the
top-level key, because the file also holds a `modelSettings` entry, and
changing `~/.claude` was out of bounds.

## Addendum — 2026-10-09 E2, a per-call `effort` against the hook

Recorded with [The Hook Pins Effort](../decisions/2026-10-09-hook-pins-effort.md),
after E1 and E3 above. Same setup as E1, `scout` dispatched with
`model: "sonnet"` and `effort: "max"`. In the second run a logging hook,
registered before the pin hook on the same matcher, recorded the Agent call's
input as the hooks saw it.

| Hook | Agent call input | Hook output keys | Scout request |
|---|---|---|---|
| as it stood before that decision, stripping `model` only | not recorded; `effort` was present, since the hook's output keys include it | `[description, prompt, subagent_type, effort, run_in_background]` | Haiku 5.5 `max` |
| `model` and `effort` | `{"subagent_type": "scout", "model": "sonnet", "effort": "max", …}` (abridged) | `[description, prompt, subagent_type, run_in_background]` | Haiku 5.5 `low` |

A per-call `effort` beats the frontmatter, as the subagents documentation
states (<https://code.claude.com/docs/en/subagents>), and stripping it in the
hook restores the frontmatter's `low`. `CONFIRMED` and `EFFECTIVE`.
