#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Validates a repository policy file against the versioned schema.
#
#   bash repository-policy/validate.sh
#   bash repository-policy/validate.sh path/to/.repository-policy.yaml
#   bash repository-policy/validate.sh repository-policy/examples/*.yaml
#
# With no argument it validates ./.repository-policy.yaml, which is the case
# that matters from a clone. Exits 0 when every file is valid, 1 when any file
# is invalid, and 2 on a usage error or when the check cannot run at all.
#
# Makes no network calls, reads no hosting-platform configuration, and changes
# nothing. It answers "is this policy well-formed", never "is this policy
# enforced" -- enforcement lives in GitHub rulesets or GitLab protected
# branches, and comparing the two is deliberately out of scope for v1.

COMPONENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPONENT_ROOT
readonly SCHEMA="$COMPONENT_ROOT/schema/repository-policy.v1.schema.json"
readonly DEFAULT_POLICY_FILE=".repository-policy.yaml"

usage() {
  printf 'usage: %s [POLICY_FILE...]\n' "${BASH_SOURCE[0]}" >&2
  printf 'Validates %s in the current directory when no file is given.\n' "$DEFAULT_POLICY_FILE" >&2
}

# Resolves an interpreter that can actually import a YAML parser.
#
# The standard library has no YAML module, so unlike this repository's TOML and
# JSON checks this one cannot be dependency-free. Rather than hand-roll a parser
# that would disagree with every other reader of the same file, find an
# interpreter that works: bare python3 first, then the mise-managed one the
# workstation installer puts PyYAML into.
#
# When neither has it the script exits 2, never 0. A validator that degrades to
# a skip reports success for a document it never read, which is the failure mode
# the toolkit installs PyYAML to prevent in the first place.
resolve_python() {
  local candidate
  local -a candidates=("python3")
  local mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"

  if [[ -x "$mise_bin" ]]; then
    candidates+=("$mise_bin exec -- python")
  fi

  for candidate in "${candidates[@]}"; do
    # Word splitting is intended: the mise candidate is a command plus arguments.
    # shellcheck disable=SC2086
    if $candidate -c 'import yaml' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

main() {
  local -a policy_files=()
  local argument

  for argument in "$@"; do
    case "$argument" in
      -h|--help)
        usage
        exit 2
        ;;
      -*)
        printf 'unknown option: %s\n' "$argument" >&2
        usage
        exit 2
        ;;
      *)
        policy_files+=("$argument")
        ;;
    esac
  done

  if (( ${#policy_files[@]} == 0 )); then
    policy_files=("$DEFAULT_POLICY_FILE")
  fi

  if [[ ! -f "$SCHEMA" ]]; then
    printf 'cannot run: the schema is missing at %s\n' "$SCHEMA" >&2
    exit 2
  fi

  local python_command
  if ! python_command="$(resolve_python)"; then
    printf 'cannot run: no Python interpreter with a YAML parser was found.\n' >&2
    printf 'Install one with: mise exec -- python -m pip install pyyaml\n' >&2
    printf 'The workstation installer does this; see environments/linux/install.sh.\n' >&2
    exit 2
  fi

  # The accepted values are read out of the schema rather than repeated here, so
  # the schema stays the single definition of what v1 allows and the two cannot
  # drift apart. Only the conditional rule is expressed in code.
  # Word splitting is intended, as above.
  # shellcheck disable=SC2086
  SCHEMA_PATH="$SCHEMA" $python_command - "${policy_files[@]}" <<'PY'
import json
import os
import sys

import yaml


def load_schema(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def constraints(schema):
    """Derive the accepted shape from the schema document."""
    root = schema["properties"]
    branching = root["branching"]["properties"]
    integration = root["integration"]["properties"]
    return {
        "version": root["version"]["const"],
        "root_required": schema["required"],
        "root_allowed": set(root),
        "branching_required": schema["properties"]["branching"]["required"],
        "branching_allowed": set(branching),
        "workflows": branching["workflow"]["enum"],
        "integration_required": schema["properties"]["integration"]["required"],
        "integration_allowed": set(integration),
        "modes": integration["mode"]["enum"],
    }


def check_section(document, name, required, allowed, errors):
    """Validate one nested mapping, returning it when usable."""
    section = document.get(name)
    if not isinstance(section, dict):
        errors.append(
            "'%s' must be a mapping, got %s" % (name, type(section).__name__)
        )
        return None
    for key in required:
        if key not in section:
            errors.append("'%s' is missing required field '%s'" % (name, key))
    for key in sorted(set(section) - allowed):
        errors.append(
            "'%s' has unknown field '%s'; allowed: %s"
            % (name, key, ", ".join(sorted(allowed)))
        )
    return section


def check_choice(section, name, key, allowed, errors):
    value = section.get(key)
    if value is None:
        return None
    if value not in allowed:
        errors.append(
            "unsupported %s '%s'; expected one of: %s"
            % (key, value, ", ".join(sorted(allowed)))
        )
        return None
    return value


def check_branch_name(section, name, key, errors, required):
    value = section.get(key)
    if value is None:
        if required:
            errors.append("'%s' is missing required field '%s'" % (name, key))
        return
    if not isinstance(value, str) or not value.strip():
        errors.append("'%s.%s' must be a non-empty string" % (name, key))


def validate(path, rules):
    errors = []

    if not os.path.isfile(path):
        return ["no such file"]

    try:
        with open(path, "r", encoding="utf-8") as handle:
            document = yaml.safe_load(handle)
    except yaml.YAMLError as error:
        return ["not valid YAML: %s" % str(error).replace("\n", " ")]

    if document is None:
        return ["the policy file is empty"]
    if not isinstance(document, dict):
        return ["the policy must be a mapping, got %s" % type(document).__name__]

    for key in rules["root_required"]:
        if key not in document:
            errors.append("missing required field '%s'" % key)
    for key in sorted(set(document) - rules["root_allowed"]):
        errors.append(
            "unknown field '%s'; allowed: %s"
            % (key, ", ".join(sorted(rules["root_allowed"])))
        )

    # The version gate comes before any interpretation of the rest. A reader
    # that guessed at an unknown version would apply v1 meanings to a document
    # written under different ones.
    version = document.get("version")
    if version is not None and version != rules["version"]:
        errors.append(
            "unsupported version %r; this validator implements version %r"
            % (version, rules["version"])
        )

    branching = check_section(
        document,
        "branching",
        rules["branching_required"],
        rules["branching_allowed"],
        errors,
    )
    integration = check_section(
        document,
        "integration",
        rules["integration_required"],
        rules["integration_allowed"],
        errors,
    )

    workflow = None
    if branching is not None:
        workflow = check_choice(
            branching, "branching", "workflow", rules["workflows"], errors
        )
        check_branch_name(branching, "branching", "stableBranch", errors, required=False)

        # The one rule that is conditional rather than enumerable. A second
        # long-lived branch is what distinguishes git-flow from the other two
        # models, so its presence and the declared workflow must agree.
        has_integration_branch = "integrationBranch" in branching
        if workflow == "git-flow" and not has_integration_branch:
            errors.append(
                "workflow 'git-flow' requires 'branching.integrationBranch' "
                "(conventionally 'develop')"
            )
        elif workflow is not None and workflow != "git-flow" and has_integration_branch:
            errors.append(
                "'branching.integrationBranch' is only meaningful for workflow "
                "'git-flow'; workflow '%s' integrates into the stable branch" % workflow
            )
        if has_integration_branch:
            check_branch_name(
                branching, "branching", "integrationBranch", errors, required=False
            )

    if integration is not None:
        check_choice(integration, "integration", "mode", rules["modes"], errors)

    return errors


def main():
    rules = constraints(load_schema(os.environ["SCHEMA_PATH"]))
    failed = False

    for path in sys.argv[1:]:
        errors = validate(path, rules)
        if errors:
            failed = True
            for error in errors:
                print("FAIL: %s: %s" % (path, error), file=sys.stderr)
        else:
            print("OK: %s" % path)

    return 1 if failed else 0


sys.exit(main())
PY
}

main "$@"
