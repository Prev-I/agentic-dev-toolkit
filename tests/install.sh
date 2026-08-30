#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly INSTALLER="$REPOSITORY_ROOT/environments/linux/install.sh"
readonly CLAUDE_TEMPLATE="$REPOSITORY_ROOT/instructions/adapters/claude-code/CLAUDE.md"

cleanup() {
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT

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

test_claude_template_resolves_after_copying_to_project_root() {
  local project_root="$TEMP_DIR/project"
  local import_path

  mkdir -p "$project_root"
  touch "$project_root/AGENTS.md"
  cp "$CLAUDE_TEMPLATE" "$project_root/CLAUDE.md"
  import_path="$(<"$project_root/CLAUDE.md")"
  [[ "$import_path" == @* ]] || fail "copied Claude adapter must use Claude's @ import syntax"
  import_path="${import_path#@}"

  [[ -f "$project_root/$import_path" ]] || fail "copied Claude adapter must resolve the root AGENTS.md"
}

load_installer_functions() {
  local -a installer_lines
  local last_line

  mapfile -t installer_lines < "$INSTALLER"
  last_line="${installer_lines[-1]}"
  [[ "$last_line" == 'main "$@"' ]] || fail "installer entry point must remain the final line"
  unset 'installer_lines[-1]'
  printf '%s\n' "${installer_lines[@]}" > "$TEMP_DIR/install-functions.sh"

  # The production script performs work through main; tests load only its functions.
  # shellcheck disable=SC1091
  source "$TEMP_DIR/install-functions.sh"
}

test_lttng_selector_prefers_time64_package_when_available() {
  # shellcheck disable=SC2329
  apt-cache() {
    [[ "$1" == "show" && "$2" == "liblttng-ust1t64" ]]
  }

  assert_equal "$(select_lttng_package)" "liblttng-ust1t64" "time64 package selection"
}

test_lttng_selector_falls_back_to_legacy_package() {
  # shellcheck disable=SC2329
  apt-cache() {
    [[ "$1" == "show" && "$2" == "liblttng-ust1" ]]
  }

  assert_equal "$(select_lttng_package)" "liblttng-ust1" "legacy package fallback"
}

test_dry_run_does_not_probe_apt_package_metadata() {
  # The dynamically sourced installer reads this global.
  # shellcheck disable=SC2034
  DRY_RUN=1
  apt-cache() {
    fail "dry-run must not query APT package metadata"
  }
  run_sudo() {
    quote_command sudo "$@"
  }
  dpkg-query() {
    return 1
  }

  local output
  output="$(install_system_packages)"
  [[ "$output" == *"Dry-run leaves the distro-specific LTTng package unresolved"* ]] || fail "dry-run must explain the unresolved LTTng package"
}

test_mise_configuration_includes_quality_tools_by_default() {
  # The dynamically sourced installer reads these globals.
  # shellcheck disable=SC2034
  { SKIP_QUALITY_TOOLS=0; SHELLCHECK_VERSION="0.11.0"; GITLEAKS_VERSION="8.30.1"; }

  local config
  config="$(render_mise_configuration)"
  [[ "$config" == *'shellcheck = "0.11.0"'* ]] || fail "mise config must pin the requested shellcheck version"
  [[ "$config" == *'gitleaks = "8.30.1"'* ]] || fail "mise config must pin the requested gitleaks version"
  [[ "$config" == *"[tools]"* ]] || fail "mise config must remain a single [tools] table"
  assert_equal "$(grep -c '^\[tools\]$' <<<"$config")" "1" "quality tools must extend the existing table, not open a second one"
}

test_mise_configuration_omits_quality_tools_when_skipped() {
  # shellcheck disable=SC2034
  SKIP_QUALITY_TOOLS=1

  local config
  config="$(render_mise_configuration)"
  [[ "$config" != *"shellcheck"* ]] || fail "--skip-quality-tools must not install shellcheck"
  [[ "$config" != *"gitleaks"* ]] || fail "--skip-quality-tools must not install gitleaks"
  [[ "$config" == *"python = "* ]] || fail "--skip-quality-tools must leave the runtimes alone"
}

test_python_libraries_are_skipped_without_runtimes() {
  # The interpreter they install into is the one --skip-runtimes declines to
  # provide, so the step has nothing to install into.
  # The dynamically sourced installer reads these globals.
  # shellcheck disable=SC2034
  { SKIP_RUNTIMES=1; SKIP_QUALITY_TOOLS=0; DRY_RUN=1; }

  local output
  output="$(install_python_quality_libraries)"
  assert_equal "$output" "" "install_python_quality_libraries must be a no-op without runtimes"
}

TEMP_DIR="$(mktemp -d)"
test_claude_template_resolves_after_copying_to_project_root
load_installer_functions
test_lttng_selector_prefers_time64_package_when_available
test_lttng_selector_falls_back_to_legacy_package
test_dry_run_does_not_probe_apt_package_metadata
test_mise_configuration_includes_quality_tools_by_default
test_mise_configuration_omits_quality_tools_when_skipped
test_python_libraries_are_skipped_without_runtimes

printf 'PASS: installer compatibility tests\n'
