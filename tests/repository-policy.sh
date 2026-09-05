#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly VALIDATOR="$REPOSITORY_ROOT/repository-policy/validate.sh"
readonly SCHEMA="$REPOSITORY_ROOT/repository-policy/schema/repository-policy.v1.schema.json"
readonly EXAMPLES="$REPOSITORY_ROOT/repository-policy/examples"

cleanup() {
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT

# The helpers are duplicated from tests/install.sh rather than factored into a
# shared library. The root test directory has no such library today, and
# introducing one would mean rewriting the installer suite as well -- a change
# to existing tests that has nothing to do with this component.
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

# Writes a policy file and returns its path. Each caller names its own file so
# the cases stay independent inside the single temporary directory.
write_policy() {
  local name="$1"
  local content="$2"
  local path="$TEMP_DIR/$name"

  printf '%s' "$content" > "$path"
  printf '%s\n' "$path"
}

# Runs the validator without letting a non-zero exit abort the suite, and
# reports the status through a global so both status and output can be asserted.
run_validator() {
  VALIDATOR_OUTPUT="$( "$@" 2>&1 )" && VALIDATOR_STATUS=0 || VALIDATOR_STATUS=$?
}

assert_valid() {
  local path="$1"
  local message="$2"

  run_validator bash "$VALIDATOR" "$path"
  assert_equal "$VALIDATOR_STATUS" "0" "$message"
}

# Asserts the policy is rejected, and that the reason says so in words. A
# validator that exits 1 with an unrelated message is not actually testing the
# rule the case is named after.
assert_invalid() {
  local path="$1"
  local expected_fragment="$2"
  local message="$3"

  run_validator bash "$VALIDATOR" "$path"
  assert_equal "$VALIDATOR_STATUS" "1" "$message"
  [[ "$VALIDATOR_OUTPUT" == *"$expected_fragment"* ]] \
    || fail "$message: expected the reason to mention '$expected_fragment', got: $VALIDATOR_OUTPUT"
}

test_github_flow_with_pull_requests_is_valid() {
  local path
  path="$(write_policy github-flow.yaml 'version: 1

branching:
  workflow: github-flow
  stableBranch: main

integration:
  mode: pull-request
')"

  assert_valid "$path" "github-flow with pull-request integration must be accepted"
}

test_git_flow_with_pull_requests_is_valid() {
  local path
  path="$(write_policy git-flow.yaml 'version: 1

branching:
  workflow: git-flow
  stableBranch: main
  integrationBranch: develop

integration:
  mode: pull-request
')"

  assert_valid "$path" "git-flow with an integration branch must be accepted"
}

test_trunk_with_direct_commits_is_valid() {
  local path
  path="$(write_policy trunk-master.yaml 'version: 1

branching:
  workflow: trunk
  stableBranch: master

integration:
  mode: direct
')"

  assert_valid "$path" "trunk with direct commits must be accepted"
}

# The case that keeps a naming habit from becoming a rule. A stable branch
# called main with direct commits is a legitimate policy -- documentation
# repositories with one maintainer work exactly this way -- and a validator
# that rejected it would be encoding the convention rather than the format.
test_main_with_direct_commits_is_valid() {
  local path
  path="$(write_policy trunk-main.yaml 'version: 1

branching:
  workflow: trunk
  stableBranch: main

integration:
  mode: direct
')"

  assert_valid "$path" "a stable branch named main must be allowed to accept direct commits"
}

test_missing_required_fields_are_rejected() {
  local path
  path="$(write_policy missing.yaml 'version: 1

branching:
  workflow: trunk
  stableBranch: main
')"

  assert_invalid "$path" "missing required field 'integration'" \
    "a policy with no integration section must be rejected"
}

test_missing_stable_branch_is_rejected() {
  local path
  path="$(write_policy no-stable-branch.yaml 'version: 1

branching:
  workflow: trunk

integration:
  mode: direct
')"

  assert_invalid "$path" "missing required field 'stableBranch'" \
    "a policy with no stable branch must be rejected"
}

test_unsupported_workflow_is_rejected() {
  local path
  path="$(write_policy bad-workflow.yaml 'version: 1

branching:
  workflow: gitflow
  stableBranch: main

integration:
  mode: pull-request
')"

  assert_invalid "$path" "unsupported workflow" \
    "an unknown workflow must be rejected rather than passed through"
}

test_unsupported_integration_mode_is_rejected() {
  local path
  path="$(write_policy bad-mode.yaml 'version: 1

branching:
  workflow: trunk
  stableBranch: main

integration:
  mode: merge
')"

  assert_invalid "$path" "unsupported mode" \
    "an unknown integration mode must be rejected rather than passed through"
}

test_git_flow_without_an_integration_branch_is_rejected() {
  local path
  path="$(write_policy git-flow-bare.yaml 'version: 1

branching:
  workflow: git-flow
  stableBranch: main

integration:
  mode: pull-request
')"

  assert_invalid "$path" "requires 'branching.integrationBranch'" \
    "git-flow without an integration branch must be rejected"
}

# The converse of the rule above. Declaring a second long-lived branch under a
# workflow that has none is a contradiction, and reporting it is what keeps the
# workflow field meaningful rather than decorative.
test_integration_branch_outside_git_flow_is_rejected() {
  local path
  path="$(write_policy stray-integration-branch.yaml 'version: 1

branching:
  workflow: github-flow
  stableBranch: main
  integrationBranch: develop

integration:
  mode: pull-request
')"

  assert_invalid "$path" "only meaningful for workflow 'git-flow'" \
    "an integration branch declared outside git-flow must be reported"
}

test_unsupported_version_is_rejected() {
  local path
  path="$(write_policy bad-version.yaml 'version: 2

branching:
  workflow: trunk
  stableBranch: main

integration:
  mode: direct
')"

  assert_invalid "$path" "unsupported version" \
    "a policy written under a future version must be refused, not guessed at"
}

test_malformed_policy_is_rejected() {
  local path
  path="$(write_policy malformed.yaml 'version: 1

branching:
  - workflow: trunk
   stableBranch: main
')"

  assert_invalid "$path" "not valid YAML" \
    "a document that does not parse must be reported as a parse failure"
}

test_empty_policy_is_rejected() {
  local path
  path="$(write_policy empty.yaml '')"

  assert_invalid "$path" "empty" "an empty policy file must be rejected"
}

# A misspelled key would otherwise be silently ignored, leaving the field it was
# meant to set at its default and the policy quietly wrong.
test_unknown_field_is_rejected() {
  local path
  path="$(write_policy typo.yaml 'version: 1

branching:
  workflow: trunk
  stablebranch: main

integration:
  mode: direct
')"

  assert_invalid "$path" "unknown field 'stablebranch'" \
    "a misspelled field must be reported rather than ignored"
}

test_missing_file_is_rejected() {
  run_validator bash "$VALIDATOR" "$TEMP_DIR/does-not-exist.yaml"
  assert_equal "$VALIDATOR_STATUS" "1" "a missing policy file must fail the check"
  [[ "$VALIDATOR_OUTPUT" == *"no such file"* ]] \
    || fail "a missing policy file must say so, got: $VALIDATOR_OUTPUT"
}

# Exit 2 is reserved for "could not run", so a caller can tell a policy that is
# wrong from a check that never happened. Conflating the two would let a broken
# invocation read as a clean repository.
test_usage_error_exits_two() {
  run_validator bash "$VALIDATOR" --nonsense
  assert_equal "$VALIDATOR_STATUS" "2" "an unknown option must exit 2, not 1"
}

test_every_committed_example_is_valid() {
  local example
  local count=0

  for example in "$EXAMPLES"/*.yaml; do
    assert_valid "$example" "committed example $(basename "$example") must validate"
    count=$(( count + 1 ))
  done

  assert_equal "$count" "4" "the documented example set must stay complete"
}

# The validator reads its accepted values out of the schema, so the two cannot
# disagree. What this asserts is that the schema itself still says what the
# documentation and tests claim -- widening an enum there silently widens the
# format everywhere.
test_schema_declares_the_documented_vocabulary() {
  local workflows modes version

  workflows="$(python3 -c '
import json, sys
schema = json.load(open(sys.argv[1]))
print(",".join(sorted(schema["properties"]["branching"]["properties"]["workflow"]["enum"])))
' "$SCHEMA")"
  modes="$(python3 -c '
import json, sys
schema = json.load(open(sys.argv[1]))
print(",".join(sorted(schema["properties"]["integration"]["properties"]["mode"]["enum"])))
' "$SCHEMA")"
  version="$(python3 -c '
import json, sys
schema = json.load(open(sys.argv[1]))
print(schema["properties"]["version"]["const"])
' "$SCHEMA")"

  assert_equal "$workflows" "git-flow,github-flow,trunk" "the schema must declare exactly the documented workflows"
  assert_equal "$modes" "direct,pull-request" "the schema must declare exactly the documented integration modes"
  assert_equal "$version" "1" "the schema must describe version 1"
}

TEMP_DIR="$(mktemp -d)"
test_github_flow_with_pull_requests_is_valid
test_git_flow_with_pull_requests_is_valid
test_trunk_with_direct_commits_is_valid
test_main_with_direct_commits_is_valid
test_missing_required_fields_are_rejected
test_missing_stable_branch_is_rejected
test_unsupported_workflow_is_rejected
test_unsupported_integration_mode_is_rejected
test_git_flow_without_an_integration_branch_is_rejected
test_integration_branch_outside_git_flow_is_rejected
test_unsupported_version_is_rejected
test_malformed_policy_is_rejected
test_empty_policy_is_rejected
test_unknown_field_is_rejected
test_missing_file_is_rejected
test_usage_error_exits_two
test_every_committed_example_is_valid
test_schema_declares_the_documented_vocabulary

printf 'PASS: repository policy tests\n'
