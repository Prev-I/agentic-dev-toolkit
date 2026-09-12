# Headroom Runtime Trial Evidence

## Status

| Area | Status |
|---|---|
| Headroom runtime | `TRIAL` |
| WSL lifecycle | `TRIAL` |
| OpenCode plugin | `HOLD` |
| MCP integration | `NOT_EVALUATED` |
| Explicit API integration | `NOT_EVALUATED` |
| Current OpenCode optimization | `NONE` |

The standalone Headroom `0.37.0` runtime, installed with Python `3.13` and the
proxy extra, is operationally accepted for controlled trial use on the validated
Linux-under-WSL2 architecture. It runs as an independent persistent user service
on `127.0.0.1:8787`. It recovers when WSL starts after a full shutdown; this is
recovery after restart, not availability while WSL is stopped.

## Accepted Runtime Boundary

The runtime uses profile `default` with `targets=[]` and `mutations=[]`. Memory
and telemetry are disabled; `HEADROOM_BEACON`, `HEADROOM_UPDATE_CHECK`, and
`HEADROOM_TELEMETRY` are opted out. Readiness reports the required runtime
version. Headroom and OpenCode have no configuration, environment, or user-unit
dependency edge, and no OpenCode traffic is currently optimized.

The trial includes generic service, readiness, loopback-network, generated
configuration, outage/restart, and WSL-recovery validation. It does not claim
host-specific measurements. OpenCode and its Gateway behavior remain separate
from the Headroom runtime lifecycle.

## Findings

- Optional Kompress may be degraded while required readiness remains successful.
- Upstream lifecycle exit `241` can be recorded during explicit stop/restart
  despite successful process termination and recovery.
- Upstream-generated operational files can have broader permissions than the
  owner-only manifest boundary.

These are non-blocking warnings under the component audit contract.

## Independent Telegram Result

Telegram duplicate polling is classified as:

```text
KNOWN_PREEXISTING_GATEWAY_FAILURE
Headroom causal involvement: NONE
```

The causal test stopped Headroom and left port `8787` absent; the Telegram
failure continued while Gateway/OpenCode behavior remained otherwise separate.
This evidence does not add Telegram checks or remediation to Headroom tooling.
