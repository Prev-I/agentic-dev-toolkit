#!/usr/bin/env bash
# Exit 77 means a named prerequisite is absent, not a passing test.
require_command() {
  command -v "$1" >/dev/null 2>&1 || { printf 'SKIP: required command %s is absent\n' "$1"; exit 77; }
}
require_system_python() {
  [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c 'import tomllib' >/dev/null 2>&1 || {
    printf 'SKIP: /usr/bin/python3 with tomllib is required\n'; exit 77;
  }
}
require_wsl() {
  [[ -r /proc/version ]] && grep -qi microsoft /proc/version || {
    printf 'SKIP: historical installer verification requires WSL\n'; exit 77;
  }
}
