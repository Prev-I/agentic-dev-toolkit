# Hold Native OpenCode Plugin

## Decision

`HOLD` the native Headroom OpenCode plugin. Do not install it or add Headroom
configuration to OpenCode.

## Rationale

The native plugin uses process-global HTTP transport interception. In the current
centralized architecture, provider traffic and Gateway channel behavior share an
OpenCode process. A process-global interceptor can affect non-inference Gateway
traffic and violates that boundary. The plugin also fails closed when its proxy
is unavailable.

Compression effectiveness is not evaluated. It remains a required criterion for
future integration work, not a benefit this runtime currently claims.

## Future Evaluation Matrix

| Option | Boundary isolation | Proxy outage behavior | Compression effectiveness | Provider compatibility | Operational risk |
|---|---|---|---|---|---|
| A. Native plugin | Evaluate process-global interception | Evaluate fail-closed behavior | Measure | Verify | Evaluate |
| B. MCP | Evaluate tool and transport boundary | Evaluate | Measure | Verify | Evaluate |
| C. Explicit API | Evaluate sidecar call boundary | Evaluate | Measure | Verify | Evaluate |
| D. No integration | Preserve current isolation | Not applicable | No claim | Preserved | Baseline |

Each option must also evaluate Gateway isolation, cache behavior, latency, token
savings, correctness, upgrade behavior, and operational complexity.

## Promotion Criteria

Move from `HOLD` to `TRIAL` only after an isolated evaluation proves that
non-inference Gateway traffic is unaffected, proxy outages have acceptable
behavior, providers remain compatible, correctness is preserved, compression
benefit is measured, and the rollback and upgrade paths are reviewed. Until
then, the current OpenCode optimization remains `NONE`.
