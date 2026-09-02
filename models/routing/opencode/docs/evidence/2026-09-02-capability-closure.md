# OpenCode V1 Capability Closure - 2026-09-02

## Environment

- Repository commit: `27cef470f28160fdd497aeacc5dde6a90d9f3111`
- OpenCode version: `1.18.26`
- Runtime environment: WSL2 Linux (`6.18.33.2-microsoft-standard-WSL2`, `x86_64`)
- Probe timestamps: `2026-09-02T11:55:10+02:00` to `2026-09-02T11:56:58+02:00`
- Current routing profile: the repository bundle's `opencode.jsonc` remains the published profile at the repository commit above. The probes supplied an explicit `--model` and therefore did not depend on that profile.

## Discovery

`opencode models` was run with OpenCode `1.18.26` before the direct probes.

- `github-copilot/claude-opus-4.6` was absent from the listing.
- `github-copilot/claude-sonnet-4.6` was absent from the listing.
- `github-copilot/gpt-5.3-codex` was present in the listing.

These are discovery/resolution signals, not capability proof.

The supported fresh noninteractive mechanism was determined from `opencode --help` and `opencode run --help`:

```bash
opencode run --model <provider/model> <message>
```

## Direct probes

The probe request for every attempt was:

```text
Reply with exactly: CAPABILITY_OK
```

### github-copilot/claude-opus-4.6

- Initial timestamp: `2026-09-02T11:55:10+02:00`
- OpenCode version: `1.18.26`
- Invocation: `opencode run --model "github-copilot/claude-opus-4.6" "Reply with exactly: CAPABILITY_OK"`
- Exit status: non-zero; the invoking tool did not expose a numeric exit status.
- Result: `Unexpected server error` with reference `err_bfe466cd`.
- Classification: `AMBIGUOUS_FAILURE`
- Capability conclusion: no conclusion from this attempt.

The ambiguous first attempt was retried once with OpenCode logging enabled.

- Retry timestamp: `2026-09-02T11:56:01+02:00`
- OpenCode version: `1.18.26`
- Invocation: `opencode --print-logs run --model "github-copilot/claude-opus-4.6" "Reply with exactly: CAPABILITY_OK"`
- Exit status: non-zero; the invoking tool did not expose a numeric exit status.
- Result: `ProviderModelNotFoundError: Model not found: github-copilot/claude-opus-4.6. Did you mean: claude-opus-4.7, claude-opus-4.7-fast, claude-opus-4.8?`
- Error reference: `err_02f353e6`
- Classification: `MODEL_UNRESOLVABLE`
- Capability conclusion: the explicit model ID was not resolvable in this runtime at the recorded timestamp.

### github-copilot/claude-sonnet-4.6

- Timestamp: `2026-09-02T11:56:35+02:00`
- OpenCode version: `1.18.26`
- Invocation: `opencode --print-logs run --model "github-copilot/claude-sonnet-4.6" "Reply with exactly: CAPABILITY_OK"`
- Exit status: non-zero; the invoking tool did not expose a numeric exit status.
- Result: `ProviderModelNotFoundError: Model not found: github-copilot/claude-sonnet-4.6. Did you mean: claude-sonnet-5, claude-haiku-4.5, claude-opus-4.7?`
- Error reference: `err_aa65ee7d`
- Classification: `MODEL_UNRESOLVABLE`
- Capability conclusion: the explicit model ID was not resolvable in this runtime at the recorded timestamp.

## Codex status

- `github-copilot/gpt-5.3-codex` was present in `opencode models` at the recorded capability check.
- No direct Codex call was run for this closure, so this record does not claim successful execution.
- The decision not to use Codex as a staged migration dependency remains a `RISK_DECISION`, not a capability conclusion.

## Conclusions

### Capability facts

- Both old Claude IDs were absent from `opencode models` and failed explicit direct probes with `MODEL_UNRESOLVABLE` errors.
- GPT-5.3-Codex was listed by `opencode models` at the recorded capability check.

### Policy facts

- No organization policy state was inspected or inferred by this record.

### Risk decisions

- The approved decision treats Codex as an elevated disappearance and reproducibility risk for staged migration even though it resolves in discovery.

### Unresolved evidence

- This closure does not establish Codex successful execution, variant syntax, role fitness, or any model's suitability for routing.
