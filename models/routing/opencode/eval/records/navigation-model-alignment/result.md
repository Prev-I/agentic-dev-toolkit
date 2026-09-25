# Navigation Model Alignment Result

Explore reuses the valid GPT-6 Luna medium dependency-chain result from the
role-specific screening. Scout GPT-6 Luna low returned `CAPABILITY_OK` with exit
0, no provider error, and no retry.

| Role | Target | Evidence | Status |
|---|---|---|---|
| Explore | `github-copilot/gpt-6-luna` `medium` | Dependency-chain fixture | PASS |
| Scout | `github-copilot/gpt-6-luna` `low` | Capability call | PASS |

The Scout dispatch record's concrete target and variant establish identity; its
historical routing-profile stamp is a known shared-runner metadata limitation.
