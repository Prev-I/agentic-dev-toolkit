# Repository Policy

A small, vendor-neutral way for a repository to declare how work reaches its
stable branch, in a file both people and coding agents can read.

Git has no portable, repository-level way to state that a project uses GitHub
Flow rather than Git Flow, or that changes arrive by pull request rather than by
direct commit. Hosting products can enforce those rules, but that configuration
is vendor-specific and an agent working from a plain clone may not be able to
see it at all.

This component is the declaration, and only the declaration. The architectural
reasoning behind it lives in the
[agentic-engineering](https://github.com/Prev-I/agentic-engineering) repository:

- [ADR-0005: Declare Repository Workflow as Machine-Readable Policy](https://github.com/Prev-I/agentic-engineering/blob/main/decisions/0005-declare-repository-workflow-as-machine-readable-policy.md)
- [Repository Workflow Contract](https://github.com/Prev-I/agentic-engineering/blob/main/patterns/repository-workflow-contract.md)

## The file

Place `.repository-policy.yaml` at the root of the repository it describes.

```yaml
version: 1

branching:
  workflow: github-flow
  stableBranch: main

integration:
  mode: pull-request
```

| Field | Required | Values |
|---|---|---|
| `version` | yes | `1` |
| `branching.workflow` | yes | `github-flow`, `git-flow`, `trunk` |
| `branching.stableBranch` | yes | any branch name |
| `branching.integrationBranch` | only for `git-flow` | any branch name |
| `integration.mode` | yes | `pull-request`, `direct` |

Unknown fields are rejected. A misspelled key is a policy that quietly does not
say what its author meant, so it fails rather than being ignored.

### Why branching and integration are separate

The workflow and the integration mechanism are independent dimensions, and the
format keeps them that way. Every combination below is expressible, because all
of them occur:

| Workflow | Integration | Reads as |
|---|---|---|
| `github-flow` | `pull-request` | short-lived branches, reviewed before merge |
| `git-flow` | `pull-request` | `main` + `develop`, reviewed before merge |
| `trunk` | `direct` | commit straight to the stable branch |
| `trunk` | `direct`, `stableBranch: main` | the same, on a branch named `main` |

**Branch names carry no integration semantics.** A branch called `main` does not
imply pull requests, and one called `master` does not imply direct commits.
Those pairings are conventions in some environments, not rules of Git, and the
format does not encode them — `examples/trunk-direct-main.yaml` exists to keep
it that way, and a test asserts it stays valid.

The `integrationBranch` field is required for `git-flow` and rejected for the
other two. A second long-lived branch is what distinguishes Git Flow from the
rest, so its presence and the declared workflow have to agree.

## Validating

```bash
bash repository-policy/validate.sh                      # ./.repository-policy.yaml
bash repository-policy/validate.sh path/to/policy.yaml
bash repository-policy/validate.sh repository-policy/examples/*.yaml
```

| Exit code | Meaning |
|---|---|
| `0` | every file checked is valid |
| `1` | a file is invalid; the reason is printed to stderr |
| `2` | usage error, or the check could not run |

The validator makes no network calls, reads no hosting-platform configuration,
and changes nothing.

Exit `2` is kept distinct on purpose: it separates "this policy is wrong" from
"this check never happened". The second must never be mistaken for success.

### The one dependency

Validation needs a YAML parser, which the Python standard library does not
provide. The validator looks for one — `python3` first, then the mise-managed
interpreter the workstation installer puts PyYAML into — and **exits 2 with
instructions if neither has it**. It never skips.

That is a deliberate departure from the dependency-free rule the rest of this
repository follows. The alternative was hand-rolling a parser for a format
users write by hand, which would accept documents real YAML rejects and reject
documents it accepts. A validator that disagrees with every other reader of the
same file is worse than no validator.

## Examples

| File | Case |
|---|---|
| `examples/github-flow-pull-request.yaml` | GitHub Flow, reviewed integration |
| `examples/git-flow-pull-request.yaml` | Git Flow with `main` + `develop` |
| `examples/trunk-direct.yaml` | trunk-based, direct commits to `master` |
| `examples/trunk-direct-main.yaml` | direct commits to a branch named `main` |

## How an agent should use it

Before creating a branch, committing, merging, rebasing, or preparing an
integration change, read the policy if one is present.

```
.repository-policy.yaml present
        |
        v
   use what it declares

           absent
        |
        v
   fall back to the repository's own instructions, or ask
```

**An explicit policy always wins.** Inference from branch names is a fallback
for repositories that have not declared one, never an override.

Where inference is unavoidable, these are heuristics and should be treated as
guesses to confirm rather than facts to act on:

| Observation | Weak signal, not a rule |
|---|---|
| a `develop` branch exists | possibly Git Flow |
| the stable branch is `main` | possibly a pull-request convention |
| the stable branch is `master` | possibly an older or direct-commit convention |

In a workspace holding several repositories, **each repository's own policy
governs work inside it**. A parent workspace's policy does not cascade into a
child repository, which means a workspace on GitHub Flow can legitimately
contain a child on Git Flow and another taking direct commits.

Suggested wording for a consuming project's `AGENTS.md`:

> Before creating branches, committing, merging, rebasing or preparing
> integration changes, inspect `.repository-policy.yaml` when present. The
> explicit repository policy takes precedence over inferring a workflow from
> branch names.

## What this is not

This file declares intent. It does not enforce it.

| Concern | Where it lives |
|---|---|
| what the workflow is | `.repository-policy.yaml` |
| why, for a human | `CONTRIBUTING.md` |
| how an agent should behave | `AGENTS.md` |
| what is actually enforced | GitHub rulesets, GitLab protected branches |

Required reviewers, CODEOWNERS, signed commits, merge queues, squash-versus-merge
rules, required status checks and branch deletion are all enforcement concerns,
and none of them belong here. Re-implementing branch protection in YAML would
produce a second, weaker copy of a system that already exists and cannot
actually stop anything.

Keeping that boundary is a design constraint, not an oversight.

## Deferred

Not in version 1, and each would need its own argument before being added:

- `detect`, to infer a policy from an existing repository
- `init`, to write a starting policy file
- comparing a declared policy against GitHub or GitLab configuration
- any command that creates branches, opens pull requests, or changes repository
  state
