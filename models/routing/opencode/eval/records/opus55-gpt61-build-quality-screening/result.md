# Opus 5.5 vs GPT-6.1 Sol Build Quality Screening Result

## Result

**Invalid comparative result. No routing decision is unlocked.** All twelve
workload dispatches and both capability probes completed within budget. All six
coding patches applied, passed both frozen oracles, passed syntax and protected
scope checks, and produced behavioral mutation detections. The frozen verifier,
however, invalidated both the immutable and candidate suites for every attempt
at a shared TOML assertion. The suites reached that assertion after earlier
checks, including candidate PATH assertions, had run; roughly thirty later
assertions did not run, so the complete suite outcome is undetermined.

Post-run harness-only diagnosis reproduced a verification-environment cause:
`env -i` supplied a temporary HOME but retained a PATH where `python3` is a mise
shim. Mise rejected the host Azure Artifacts config as untrusted under that
HOME. The retained suite logs suppress python3 stderr and contain only the common
TOML assertion, so this cause is diagnostic rather than directly captured
evidence. Because the verifier is part of the approved hash
freeze and retries are forbidden, the attempts remain invalid rather than being
reclassified post hoc.

## Collected Evidence

| Model | Dispatches | Oracle/empty PATH | Syntax/scope | Mutation | Valid coding passes |
|---|---:|---:|---:|---:|---:|
| Claude Opus 5.5 high | 3/3 OK | 3/3 | 3/3 | 3 behavioral | 0 |
| GPT-6.1 Sol high | 3/3 OK | 3/3 | 3/3 | 3 behavioral | 0 |

The gate fixture descriptively favored current GPT-6.1 Sol:

| Model | Gate adherent |
|---|---:|
| Claude Opus 5.5 high | 0/3 |
| GPT-6.1 Sol high | 3/3 |

That gate result cannot override invalid coding evidence under the frozen
decision precedence.

## Cost And Time

| Model | Total observed credits | Median coding credits | Median coding time |
|---|---:|---:|---:|
| Claude Opus 5.5 high | 377.35638 | 116.01914 | 247.850 s |
| GPT-6.1 Sol high | 92.48945 | 25.05121 | 128.545 s |

Total observed spend was `469.84583` credits against the approved `630` ceiling.
Credits are runtime-reported completed-step accounting, not provider-billing
reconciliation.

## Routing

Routing remains unchanged. A future rerun requires a new freeze that resolves
the mise-shim verification environment before any dispatch; the retained
attempts are not reused as valid coding passes. It should include a positive
control of the reference solution under the exact verifier environment, a fixed
working directory and a python3 executable that bypasses the host mise shim.
