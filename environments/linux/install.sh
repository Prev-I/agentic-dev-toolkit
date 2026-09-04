#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly MISE_INSTALL_URL="https://mise.run"
readonly OPENCODE_INSTALL_URL="https://opencode.ai/install"
readonly CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
readonly SUPERPOWERS_PLUGIN_BASE='superpowers@git+https://github.com/obra/superpowers.git'
readonly KARPATHY_RAW_BASE='https://raw.githubusercontent.com/multica-ai/andrej-karpathy-skills'
readonly KARPATHY_SKILL_PATH='skills/karpathy-guidelines/SKILL.md'
readonly KARPATHY_DEFAULT_REF='2c606141936f1eeef17fa3043a72095b4765b9c2'
readonly KARPATHY_DEFAULT_SHA256='6e22cc54cb02a5e98ae42d06d9d7292db0c1b43894831b32879beb0166b2aea7'

DRY_RUN=0
UPGRADE=0
VERIFY_ONLY=0
SKIP_PLATFORM_CHECK=0
REMOVE_APT_NODE=0
REPAIR_CODEX=0
PROJECT_PATH=""

SKIP_RUNTIMES=0
SKIP_OPENCODE=0
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_OPENSPEC=0
SKIP_SUPERPOWERS=0
SKIP_KARPATHY=0
SKIP_QUALITY_TOOLS=0

JAVA_21_VERSION="${ADT_JAVA_21_VERSION:-temurin-21}"
JAVA_17_VERSION="${ADT_JAVA_17_VERSION:-temurin-17}"
DOTNET_10_VERSION="${ADT_DOTNET_10_VERSION:-10}"
DOTNET_8_VERSION="${ADT_DOTNET_8_VERSION:-8}"
PYTHON_VERSION="${ADT_PYTHON_VERSION:-3.14}"
NODE_VERSION="${ADT_NODE_VERSION:-24}"
UV_VERSION="${ADT_UV_VERSION:-latest}"
OPENSPEC_VERSION="${ADT_OPENSPEC_VERSION:-1.9.0}"
SUPERPOWERS_REF="${ADT_SUPERPOWERS_REF:-v6.3.0}"
KARPATHY_REF="${ADT_KARPATHY_REF:-$KARPATHY_DEFAULT_REF}"
KARPATHY_SHA256="${ADT_KARPATHY_SHA256:-}"
OPENSPEC_TOOLS="${ADT_OPENSPEC_TOOLS:-opencode,claude,codex}"
SHELLCHECK_VERSION="${ADT_SHELLCHECK_VERSION:-latest}"
GITLEAKS_VERSION="${ADT_GITLEAKS_VERSION:-latest}"
PYYAML_VERSION="${ADT_PYYAML_VERSION:-latest}"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME%/}"
MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
MISE_TOOLCHAIN_CONFIG="${MISE_TOOLCHAIN_CONFIG:-$XDG_CONFIG_HOME/mise/conf.d/agentic-dev-toolkit.toml}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$XDG_CONFIG_HOME/opencode/opencode.json}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_STANDALONE_ROOT="$CODEX_HOME/packages/standalone"

export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$PATH"

TEMP_PATHS=()
DOWNLOADED_INSTALLER=""

log() {
  printf '\n==> %s\n' "$*"
}

info() {
  printf '    %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

quote_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  quote_command "$@"
  if (( DRY_RUN == 0 )); then
    "$@"
  fi
}

run_sudo() {
  quote_command sudo "$@"
  if (( DRY_RUN == 0 )); then
    sudo "$@"
  fi
}

cleanup() {
  local path
  for path in "${TEMP_PATHS[@]:-}"; do
    [[ -n "$path" ]] && rm -f -- "$path" 2>/dev/null || true
  done
}

on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]:-unknown}"
  printf '\nERROR: setup failed near line %s (exit code %s).\n' "$line_no" "$exit_code" >&2
  exit "$exit_code"
}

trap cleanup EXIT
trap on_error ERR

usage() {
  cat <<EOF_USAGE
Usage: $SCRIPT_NAME [options]

Provision a Debian/Ubuntu development workstation with direnv, mise-managed
runtimes, OpenCode, Claude Code, Codex CLI, OpenSpec, Superpowers, and the
Karpathy guidelines skill.

General options:
  --dry-run                    Print actions without changing the system.
  --upgrade                    Upgrade mutable components and runtime patches.
  --verify-only                Verify the current workstation without installing.
  --project PATH               Initialize or refresh OpenSpec and create a safe
                               direnv configuration in a Git repository.
  --skip-platform-check        Skip the distribution family check (unsupported distributions only).
  --remove-apt-node            Remove APT-managed nodejs/npm before mise Node.
  --repair-codex               Remove recognized Codex install conflicts and
                               reinstall the official standalone Codex CLI.

Selective installation:
  --skip-runtimes              Skip mise and language runtime installation.
  --skip-opencode              Skip OpenCode installation/update.
  --skip-claude                Skip Claude Code installation/update.
  --skip-codex                 Skip Codex CLI installation/update.
  --skip-openspec              Skip OpenSpec installation/update.
  --skip-superpowers           Do not modify the OpenCode Superpowers config.
  --skip-karpathy              Do not install the Karpathy guidelines skill.
  --skip-quality-tools         Skip shellcheck, gitleaks, and PyYAML.
                               Implied by --skip-runtimes, which are what
                               installs them.

Version overrides:
  --node-version VERSION       Node.js version (default: $NODE_VERSION).
  --python-version VERSION     Python version (default: $PYTHON_VERSION).
  --uv-version VERSION         uv version (default: $UV_VERSION).
  --java-17-version VERSION    Java 17 distribution/version (default: $JAVA_17_VERSION).
  --java-21-version VERSION    Java 21 distribution/version (default: $JAVA_21_VERSION).
  --dotnet-8-version VERSION   .NET 8 SDK version (default: $DOTNET_8_VERSION).
  --dotnet-10-version VERSION  .NET 10 SDK version (default: $DOTNET_10_VERSION).
  --openspec-version VERSION   OpenSpec version (default: $OPENSPEC_VERSION).
  --superpowers-ref REF        Superpowers Git ref (default: $SUPERPOWERS_REF).
  --karpathy-ref REF           Karpathy skill Git ref (default: the pinned commit).
  --karpathy-sha256 DIGEST     Expected SHA-256 of the Karpathy skill. Required to
                               verify a --karpathy-ref other than the pinned one;
                               without it such a ref installs unverified.
  --shellcheck-version VERSION shellcheck version (default: $SHELLCHECK_VERSION).
  --gitleaks-version VERSION   gitleaks version (default: $GITLEAKS_VERSION).
  --pyyaml-version VERSION     PyYAML version (default: $PYYAML_VERSION).
  -h, --help                   Show this help.

Environment variables provide the same defaults:
  ADT_NODE_VERSION, ADT_PYTHON_VERSION, ADT_UV_VERSION,
  ADT_JAVA_17_VERSION, ADT_JAVA_21_VERSION,
  ADT_DOTNET_8_VERSION, ADT_DOTNET_10_VERSION,
  ADT_OPENSPEC_VERSION, ADT_SUPERPOWERS_REF, ADT_OPENSPEC_TOOLS,
  ADT_KARPATHY_REF, ADT_KARPATHY_SHA256,
  ADT_SHELLCHECK_VERSION, ADT_GITLEAKS_VERSION, ADT_PYYAML_VERSION

Examples:
  ./$SCRIPT_NAME --dry-run
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --upgrade
  ./$SCRIPT_NAME --project ~/code/my-project
  ./$SCRIPT_NAME --verify-only
  ./$SCRIPT_NAME --repair-codex
EOF_USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || die "$option requires a value"
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --upgrade) UPGRADE=1 ;;
      --verify-only) VERIFY_ONLY=1 ;;
      --skip-platform-check) SKIP_PLATFORM_CHECK=1 ;;
      --remove-apt-node) REMOVE_APT_NODE=1 ;;
      --repair-codex) REPAIR_CODEX=1 ;;
      --skip-runtimes) SKIP_RUNTIMES=1 ;;
      --skip-opencode) SKIP_OPENCODE=1 ;;
      --skip-claude) SKIP_CLAUDE=1 ;;
      --skip-codex) SKIP_CODEX=1 ;;
      --skip-openspec) SKIP_OPENSPEC=1 ;;
      --skip-superpowers) SKIP_SUPERPOWERS=1 ;;
      --skip-karpathy) SKIP_KARPATHY=1 ;;
      --skip-quality-tools) SKIP_QUALITY_TOOLS=1 ;;
      --project)
        require_value "$1" "${2:-}"
        PROJECT_PATH="$2"
        shift
        ;;
      --project=*) PROJECT_PATH="${1#*=}" ;;
      --node-version)
        require_value "$1" "${2:-}"; NODE_VERSION="$2"; shift ;;
      --node-version=*) NODE_VERSION="${1#*=}" ;;
      --python-version)
        require_value "$1" "${2:-}"; PYTHON_VERSION="$2"; shift ;;
      --python-version=*) PYTHON_VERSION="${1#*=}" ;;
      --uv-version)
        require_value "$1" "${2:-}"; UV_VERSION="$2"; shift ;;
      --uv-version=*) UV_VERSION="${1#*=}" ;;
      --java-17-version)
        require_value "$1" "${2:-}"; JAVA_17_VERSION="$2"; shift ;;
      --java-17-version=*) JAVA_17_VERSION="${1#*=}" ;;
      --java-21-version)
        require_value "$1" "${2:-}"; JAVA_21_VERSION="$2"; shift ;;
      --java-21-version=*) JAVA_21_VERSION="${1#*=}" ;;
      --dotnet-8-version)
        require_value "$1" "${2:-}"; DOTNET_8_VERSION="$2"; shift ;;
      --dotnet-8-version=*) DOTNET_8_VERSION="${1#*=}" ;;
      --dotnet-10-version)
        require_value "$1" "${2:-}"; DOTNET_10_VERSION="$2"; shift ;;
      --dotnet-10-version=*) DOTNET_10_VERSION="${1#*=}" ;;
      --openspec-version)
        require_value "$1" "${2:-}"; OPENSPEC_VERSION="$2"; shift ;;
      --openspec-version=*) OPENSPEC_VERSION="${1#*=}" ;;
      --superpowers-ref)
        require_value "$1" "${2:-}"; SUPERPOWERS_REF="$2"; shift ;;
      --superpowers-ref=*) SUPERPOWERS_REF="${1#*=}" ;;
      --karpathy-ref)
        require_value "$1" "${2:-}"; KARPATHY_REF="$2"; shift ;;
      --karpathy-ref=*) KARPATHY_REF="${1#*=}" ;;
      --karpathy-sha256)
        require_value "$1" "${2:-}"; KARPATHY_SHA256="$2"; shift ;;
      --karpathy-sha256=*) KARPATHY_SHA256="${1#*=}" ;;
      --shellcheck-version)
        require_value "$1" "${2:-}"; SHELLCHECK_VERSION="$2"; shift ;;
      --shellcheck-version=*) SHELLCHECK_VERSION="${1#*=}" ;;
      --gitleaks-version)
        require_value "$1" "${2:-}"; GITLEAKS_VERSION="$2"; shift ;;
      --gitleaks-version=*) GITLEAKS_VERSION="${1#*=}" ;;
      --pyyaml-version)
        require_value "$1" "${2:-}"; PYYAML_VERSION="$2"; shift ;;
      --pyyaml-version=*) PYYAML_VERSION="${1#*=}" ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  (( REPAIR_CODEX == 0 || SKIP_CODEX == 0 )) || die "--repair-codex cannot be combined with --skip-codex"
}

validate_environment() {
  if [[ "${ADT_SETUP_ALLOW_ROOT_FOR_TESTS:-0}" != "1" ]]; then
    [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run this script as your normal user, not as root."
  fi

  if (( SKIP_PLATFORM_CHECK == 0 )); then
    [[ -r /etc/os-release ]] || die "/etc/os-release is not available"
    # shellcheck disable=SC1091
    . /etc/os-release

    local is_debian_family=0
    if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" ]]; then
      is_debian_family=1
    elif [[ "${ID_LIKE:-}" == *debian* || "${ID_LIKE:-}" == *ubuntu* ]]; then
      is_debian_family=1
    fi

    if (( is_debian_family == 0 )); then
      die "Unsupported distribution: ${ID:-unknown} ${VERSION_ID:-unknown}. Only Debian/Ubuntu family distributions are currently supported. Use --skip-platform-check at your own risk."
    fi
  fi

  if (( VERIFY_ONLY == 0 && DRY_RUN == 0 )); then
    command -v apt-get >/dev/null 2>&1 || die "apt-get is required"
    command -v sudo >/dev/null 2>&1 || die "sudo is required"
  fi
}

select_lttng_package() {
  if apt-cache show liblttng-ust1t64 >/dev/null 2>&1; then
    printf '%s\n' "liblttng-ust1t64"
  elif apt-cache show liblttng-ust1 >/dev/null 2>&1; then
    printf '%s\n' "liblttng-ust1"
  else
    die "Neither liblttng-ust1t64 nor liblttng-ust1 is available from configured APT sources."
  fi
}

install_system_packages() {
  local packages=(
    bash-completion build-essential ca-certificates curl direnv gawk git gnupg jq
    openssh-client pkg-config ripgrep tar unzip xz-utils zip
    libbz2-dev libffi-dev libicu-dev libkrb5-3 liblzma-dev libncursesw5-dev
    libreadline-dev libsqlite3-dev libssl-dev tk-dev uuid-dev
    zlib1g-dev
  )
  local lttng_package

  log "Installing Debian/Ubuntu prerequisites"
  run_sudo apt-get update
  if (( DRY_RUN == 1 )); then
    info "Dry-run leaves the distro-specific LTTng package unresolved: liblttng-ust1t64 or liblttng-ust1."
    lttng_package="<liblttng-ust1t64-or-liblttng-ust1>"
  else
    lttng_package="$(select_lttng_package)"
  fi
  packages+=("$lttng_package")
  run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

  if dpkg-query -W -f='${Status}\n' nodejs 2>/dev/null | grep -q 'install ok installed'; then
    if (( REMOVE_APT_NODE == 1 )); then
      log "Removing APT-managed Node.js/npm"
      run_sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y nodejs npm
      info "Automatic apt autoremove is intentionally not run."
    else
      warn "APT-managed nodejs is installed. mise Node will take precedence in managed shells."
      warn "Re-run with --remove-apt-node if you want to remove only the APT nodejs/npm packages."
    fi
  fi
}

download_installer() {
  local url="$1"
  DOWNLOADED_INSTALLER="$(mktemp)"
  TEMP_PATHS+=("$DOWNLOADED_INSTALLER")
  curl -fsSL "$url" -o "$DOWNLOADED_INSTALLER"
}

ensure_shell_configuration() {
  local bashrc="$HOME/.bashrc"
  local start_marker='# >>> agentic-dev-toolkit >>>'
  local end_marker='# <<< agentic-dev-toolkit <<<'
  local temp_file backup_file

  log "Configuring Bash PATH, mise, and direnv activation"

  if (( DRY_RUN == 1 )); then
    info "Would update $bashrc with a managed PATH/mise/direnv block."
    return
  fi

  mkdir -p "$HOME/.local/bin"
  touch "$bashrc"
  temp_file="$(mktemp)"
  TEMP_PATHS+=("$temp_file")

  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { skipping = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
  ' "$bashrc" > "$temp_file"

  cat >> "$temp_file" <<'EOF_BASHRC'

# >>> agentic-dev-toolkit >>>
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$PATH"
export OPENCODE_ENABLE_EXA=true
if [[ -x "$HOME/.local/bin/mise" ]]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
fi
eval "$(direnv hook bash)"
# <<< agentic-dev-toolkit <<<
EOF_BASHRC

  if ! cmp -s "$bashrc" "$temp_file"; then
    backup_file="$bashrc.pre-agentic-dev-toolkit"
    [[ -e "$backup_file" ]] || cp "$bashrc" "$backup_file"
    mv "$temp_file" "$bashrc"
  else
    rm -f "$temp_file"
  fi

  export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.opencode/bin:$PATH"
}

install_mise() {
  if (( SKIP_RUNTIMES == 1 )); then
    log "Skipping mise and runtime installation"
    return
  fi

  if [[ ! -x "$MISE_BIN" ]]; then
    log "Installing mise with the official installer"
    if (( DRY_RUN == 1 )); then
      info "Would install mise from $MISE_INSTALL_URL into $HOME/.local/bin."
    else
      local installer
      download_installer "$MISE_INSTALL_URL"
      installer="$DOWNLOADED_INSTALLER"
      sh "$installer"
      [[ -x "$MISE_BIN" ]] || die "mise was not installed at $MISE_BIN"
    fi
  elif (( UPGRADE == 1 )); then
    log "Updating mise with mise self-update"
    if (( DRY_RUN == 1 )); then
      quote_command "$MISE_BIN" self-update -y --no-plugins
    elif ! "$MISE_BIN" self-update -y --no-plugins; then
      warn "mise self-update failed. This command is unavailable for package-manager installations."
      warn "The existing mise installation was left unchanged."
    fi
  else
    log "mise is already installed: $MISE_BIN"
  fi
}

render_mise_configuration() {
  cat <<EOF_MISE
[tools]
java = ["${JAVA_21_VERSION}", "${JAVA_17_VERSION}"]
dotnet = ["${DOTNET_10_VERSION}", "${DOTNET_8_VERSION}"]
python = "${PYTHON_VERSION}"
node = "${NODE_VERSION}"
uv = "${UV_VERSION}"
EOF_MISE

  # The two linters below go through mise rather than APT on purpose. Both are
  # in Debian/Ubuntu, but the packaged versions trail upstream by years — 0.9.0
  # against 0.11.0 upstream at the time of writing. A linter that silently
  # lacks the check you are relying on is worse than no linter, and a secret
  # scanner that predates a rule is worse still.
  #
  # Do not begin a comment line here with the linter's own name followed by a
  # space: it is read as a directive, fails to parse, and takes the rest of
  # this function's analysis with it.
  if (( SKIP_QUALITY_TOOLS == 0 )); then
    cat <<EOF_MISE_QUALITY
shellcheck = "${SHELLCHECK_VERSION}"
gitleaks = "${GITLEAKS_VERSION}"
EOF_MISE_QUALITY
  fi
}

write_managed_file() {
  local target="$1"
  local content="$2"
  local target_dir temp_file

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  temp_file="$(mktemp)"
  TEMP_PATHS+=("$temp_file")
  printf '%s\n' "$content" > "$temp_file"

  if [[ -f "$target" ]] && cmp -s "$target" "$temp_file"; then
    rm -f "$temp_file"
    return
  fi

  mv "$temp_file" "$target"
}

configure_runtimes() {
  if (( SKIP_RUNTIMES == 1 )); then
    return
  fi

  local config
  config="$(render_mise_configuration)"
  log "Configuring mise runtimes in $MISE_TOOLCHAIN_CONFIG"

  if (( DRY_RUN == 1 )); then
    printf '%s\n' "$config"
    quote_command "$MISE_BIN" install
    (( UPGRADE == 0 )) || quote_command "$MISE_BIN" upgrade
    return
  fi

  write_managed_file "$MISE_TOOLCHAIN_CONFIG" "$config"
  MISE_YES=1 "$MISE_BIN" install
  if (( UPGRADE == 1 )); then
    MISE_YES=1 "$MISE_BIN" upgrade
  fi

  eval "$("$MISE_BIN" activate bash)"
}

install_python_quality_libraries() {
  if (( SKIP_RUNTIMES == 1 || SKIP_QUALITY_TOOLS == 1 )); then
    return
  fi

  # PyYAML is installed into the mise-managed interpreter, not a virtualenv,
  # because what needs it is `python3 -c "import yaml"` run by somebody else's
  # test suite. A test runner that degrades to a skip when a parser is missing
  # exits 0 with its strongest check silent: the suite reports success and the
  # thing it was meant to prove was never evaluated. Making the import succeed
  # by default is what closes that, and it cannot be closed from inside the
  # repository that suffers from it.
  local specifier="pyyaml"
  if [[ "$PYYAML_VERSION" != "latest" ]]; then
    specifier="pyyaml==$PYYAML_VERSION"
  fi

  log "Installing Python libraries for repository tooling"

  if (( DRY_RUN == 1 )); then
    quote_command "$MISE_BIN" exec -- python -m pip install --upgrade "$specifier"
    return
  fi

  local -a pip_command=("$MISE_BIN" exec -- python -m pip install "$specifier")
  if (( UPGRADE == 1 )) || [[ "$PYYAML_VERSION" == "latest" ]]; then
    pip_command=("$MISE_BIN" exec -- python -m pip install --upgrade "$specifier")
  fi

  if ! "${pip_command[@]}"; then
    # Not fatal. A workstation whose interpreter refuses this one library is
    # still a usable workstation, and failing the whole provisioning run here
    # would be out of proportion to what was lost.
    warn "Could not install $specifier into the mise-managed Python."
    warn "Test suites that skip when PyYAML is absent will keep skipping."
  fi
}

install_opencode() {
  if (( SKIP_OPENCODE == 1 )); then
    log "Skipping OpenCode installation"
    return
  fi

  if command -v opencode >/dev/null 2>&1 && (( UPGRADE == 0 )); then
    log "OpenCode is already installed: $(command -v opencode)"
    return
  fi

  log "Installing or updating OpenCode with the official installer"
  if (( DRY_RUN == 1 )); then
    info "Would install OpenCode into $HOME/.local/bin from $OPENCODE_INSTALL_URL."
    return
  fi

  local installer
  download_installer "$OPENCODE_INSTALL_URL"
  installer="$DOWNLOADED_INSTALLER"
  mkdir -p "$HOME/.local/bin"
  XDG_BIN_DIR="$HOME/.local/bin" bash "$installer" --no-modify-path
  hash -r
  command -v opencode >/dev/null 2>&1 || die "OpenCode installation completed but 'opencode' is not on PATH"
}

install_claude() {
  if (( SKIP_CLAUDE == 1 )); then
    log "Skipping Claude Code installation"
    return
  fi

  if command -v claude >/dev/null 2>&1 && (( UPGRADE == 0 )); then
    log "Claude Code is already installed: $(command -v claude)"
    return
  fi

  log "Installing or updating Claude Code with the official npm package"
  if (( DRY_RUN == 1 )); then
    quote_command npm install -g @anthropic-ai/claude-code@latest
    return
  fi

  command -v npm >/dev/null 2>&1 || die "npm is required to install Claude Code; install runtimes or remove --skip-runtimes"
  npm install -g @anthropic-ai/claude-code@latest
  hash -r
  command -v claude >/dev/null 2>&1 || die "Claude Code installation completed but 'claude' is not on PATH"
}

codex_visible_path() {
  command -v codex 2>/dev/null || true
}

codex_npm_binary_for_path() {
  local path="$1"
  local prefix=""
  local candidate=""
  local resolved=""
  local npm_prefix=""

  [[ -n "$path" ]] || return 1
  resolved="$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")"

  if [[ "$path" == */bin/codex ]]; then
    prefix="${path%/bin/codex}"
    candidate="$prefix/bin/npm"

    if [[ -x "$candidate" ]]; then
      if "$candidate" ls -g --depth=0 @openai/codex >/dev/null 2>&1 || \
         [[ "$resolved" == "$prefix/lib/node_modules/@openai/codex/"* ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

  if command -v npm >/dev/null 2>&1; then
    npm_prefix="$(npm prefix -g 2>/dev/null || true)"
    if [[ -n "$npm_prefix" && "$path" == "$npm_prefix/bin/"* ]] && \
       npm ls -g --depth=0 @openai/codex >/dev/null 2>&1; then
      command -v npm
      return 0
    fi
  fi

  return 1
}

codex_install_kind() {
  local path="$1"
  local resolved=""

  [[ -n "$path" ]] || { printf 'none\n'; return; }
  resolved="$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")"

  if [[ "$resolved" == "$CODEX_STANDALONE_ROOT/"* ]]; then
    printf 'standalone\n'
    return
  fi

  if codex_npm_binary_for_path "$path" >/dev/null 2>&1; then
    printf 'npm\n'
    return
  fi

  if command -v bun >/dev/null 2>&1 && [[ "$path" == *"/.bun/"* ]]; then
    printf 'bun\n'
    return
  fi

  printf 'unknown\n'
}

repair_codex_installations() {
  local attempts=0 path kind

  log "Repairing Codex CLI installation state"

  while (( attempts < 4 )); do
    hash -r
    path="$(codex_visible_path)"
    kind="$(codex_install_kind "$path")"

    case "$kind" in
      none)
        return
        ;;
      standalone)
        info "Removing installer-owned standalone Codex files while preserving $CODEX_HOME configuration and credentials."
        run rm -f "$HOME/.local/bin/codex" "$HOME/.local/bin/codex-code-mode-host"
        run rm -rf "$CODEX_STANDALONE_ROOT"
        ;;
      npm)
        local npm_bin
        npm_bin="$(codex_npm_binary_for_path "$path")" || \
          die "Codex at '$path' looks npm-managed, but the owning npm executable could not be resolved."
        info "Removing npm-managed @openai/codex at $path using $npm_bin."
        if (( DRY_RUN == 1 )); then
          quote_command "$npm_bin" uninstall -g @openai/codex
        else
          "$npm_bin" uninstall -g @openai/codex
        fi
        ;;
      bun)
        info "Removing bun-managed @openai/codex at $path."
        if (( DRY_RUN == 1 )); then
          quote_command bun remove -g @openai/codex
        else
          bun remove -g @openai/codex
        fi
        ;;
      unknown)
        die "Codex is available at '$path', but its install method is not recognized. Remove it manually or adjust PATH before using --repair-codex."
        ;;
    esac

    (( attempts += 1 ))
    if (( DRY_RUN == 1 )); then
      return
    fi
  done

  die "Codex repair could not reach a clean installation state"
}

install_codex() {
  if (( SKIP_CODEX == 1 )); then
    log "Skipping Codex CLI installation"
    return
  fi

  local path kind installer
  path="$(codex_visible_path)"
  kind="$(codex_install_kind "$path")"

  if (( REPAIR_CODEX == 1 )); then
    repair_codex_installations
    path=""
    kind="none"
  elif [[ "$kind" == "npm" || "$kind" == "bun" || "$kind" == "unknown" ]]; then
    die "A non-standalone Codex installation is active at '$path'. Re-run with --repair-codex to migrate recognized npm/bun installations safely."
  fi

  if [[ "$kind" == "standalone" && $UPGRADE -eq 0 ]]; then
    log "Codex standalone is already installed: $path"
    return
  fi

  log "Installing or updating Codex CLI with the official standalone installer"
  if (( DRY_RUN == 1 )); then
    info "Would install Codex into $HOME/.local/bin from $CODEX_INSTALL_URL."
    return
  fi

  download_installer "$CODEX_INSTALL_URL"
  installer="$DOWNLOADED_INSTALLER"
  mkdir -p "$HOME/.local/bin"
  CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DIR="$HOME/.local/bin" sh "$installer"
  hash -r

  path="$(codex_visible_path)"
  kind="$(codex_install_kind "$path")"
  [[ "$kind" == "standalone" ]] || die "Codex installation did not resolve to the expected standalone layout"
}

install_openspec() {
  if (( SKIP_OPENSPEC == 1 )); then
    log "Skipping OpenSpec installation"
    return
  fi

  local current=""
  if command -v openspec >/dev/null 2>&1; then
    current="$(openspec --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  fi

  if [[ "$current" == "$OPENSPEC_VERSION" ]]; then
    log "OpenSpec $OPENSPEC_VERSION is already installed"
    return
  fi

  log "Installing pinned OpenSpec $OPENSPEC_VERSION"
  if (( DRY_RUN == 1 )); then
    quote_command npm install -g "@fission-ai/openspec@$OPENSPEC_VERSION"
    return
  fi

  command -v npm >/dev/null 2>&1 || die "npm is required to install OpenSpec; install runtimes or remove --skip-runtimes"
  npm install -g "@fission-ai/openspec@$OPENSPEC_VERSION"
  hash -r

  current="$(openspec --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  [[ "$current" == "$OPENSPEC_VERSION" ]] || die "Expected OpenSpec $OPENSPEC_VERSION after installation; detected '${current:-unknown}'"
}

configure_opencode_superpowers() {
  if (( SKIP_SUPERPOWERS == 1 )); then
    log "Skipping OpenCode Superpowers configuration"
    return
  fi

  local plugin="$SUPERPOWERS_PLUGIN_BASE#$SUPERPOWERS_REF"
  local config_dir temp_file backup_file
  config_dir="$(dirname "$OPENCODE_CONFIG")"

  log "Configuring Superpowers $SUPERPOWERS_REF for OpenCode"

  if (( DRY_RUN == 1 )); then
    info "Would ensure '$plugin' is the only Superpowers entry in $OPENCODE_CONFIG."
    return
  fi

  mkdir -p "$config_dir"

  if [[ ! -s "$OPENCODE_CONFIG" ]]; then
    jq -n --arg plugin "$plugin" '{
      "$schema": "https://opencode.ai/config.json",
      "plugin": [$plugin]
    }' > "$OPENCODE_CONFIG"
    return
  fi

  if ! jq empty "$OPENCODE_CONFIG" >/dev/null 2>&1; then
    warn "$OPENCODE_CONFIG is not strict JSON and was not modified automatically."
    warn "Add this plugin manually: $plugin"
    return
  fi

  backup_file="$OPENCODE_CONFIG.pre-agentic-dev-toolkit"
  [[ -e "$backup_file" ]] || cp "$OPENCODE_CONFIG" "$backup_file"

  temp_file="$(mktemp)"
  TEMP_PATHS+=("$temp_file")

  if jq --arg plugin "$plugin" --arg base "$SUPERPOWERS_PLUGIN_BASE" '
      .["$schema"] = (.["$schema"] // "https://opencode.ai/config.json") |
      if .plugin == null then
        .plugin = [$plugin]
      elif (.plugin | type) == "array" then
        .plugin = ([.plugin[] | select((type != "string") or (startswith($base) | not))] + [$plugin])
      else
        error("the existing .plugin value is not an array")
      end
    ' "$OPENCODE_CONFIG" > "$temp_file"; then
    if ! cmp -s "$OPENCODE_CONFIG" "$temp_file"; then
      mv "$temp_file" "$OPENCODE_CONFIG"
    else
      rm -f "$temp_file"
    fi
  else
    rm -f "$temp_file"
    warn "Could not update the plugin array in $OPENCODE_CONFIG; the file was left unchanged."
  fi
}

install_karpathy_skill() {
  if (( SKIP_KARPATHY == 1 )); then
    log "Skipping the Karpathy guidelines skill"
    return
  fi

  # Two destinations cover three harnesses. Claude Code reads ~/.claude/skills
  # and Codex reads $CODEX_HOME/skills; OpenCode reads BOTH of those in addition
  # to its own directory, so a third copy under ~/.config/opencode/skills would
  # be dead weight. The absence is deliberate — do not "fix" it.
  #
  # Only the skill file is installed. Upstream also ships AGENTS.md, CLAUDE.md
  # and editor rule-file adapters carrying the same text; those would collide
  # with instruction files a project already owns, and a skill is loaded on
  # demand rather than occupying every prompt.
  #
  # Deliberately independent of --skip-claude and --skip-codex: those decline to
  # install a harness, not to configure one, and the Claude Code directory
  # serves OpenCode whether or not Claude Code is present.
  local claude_skill="$HOME/.claude/skills/karpathy-guidelines/SKILL.md"
  local codex_skill="$CODEX_HOME/skills/karpathy-guidelines/SKILL.md"
  local url="$KARPATHY_RAW_BASE/$KARPATHY_REF/$KARPATHY_SKILL_PATH"

  log "Installing the Karpathy guidelines skill ($KARPATHY_REF)"

  if (( DRY_RUN == 1 )); then
    info "Would download $url and write it to:"
    info "  $claude_skill (Claude Code and OpenCode)"
    info "  $codex_skill (Codex)"
    return
  fi

  local expected_sha
  if [[ "$KARPATHY_REF" == "$KARPATHY_DEFAULT_REF" ]]; then
    # The pin is authoritative for the pinned ref. Honouring a caller-supplied
    # digest here would let --karpathy-sha256 authorise different content at the
    # pinned commit, which is the one thing the pin exists to prevent.
    [[ -z "$KARPATHY_SHA256" || "${KARPATHY_SHA256,,}" == "$KARPATHY_DEFAULT_SHA256" ]] || \
      die "--karpathy-sha256 conflicts with the digest pinned for the default ref; pass --karpathy-ref too if you mean to install different content"
    expected_sha="$KARPATHY_DEFAULT_SHA256"
  else
    # A custom ref has content the built-in digest cannot describe. This file
    # becomes standing instructions to every coding agent on the machine, so it
    # is not installed on trust alone.
    [[ -n "$KARPATHY_SHA256" ]] || \
      die "--karpathy-ref '$KARPATHY_REF' also requires --karpathy-sha256; refusing to install unverified agent instructions"
    expected_sha="${KARPATHY_SHA256,,}"
  fi

  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die "Not a SHA-256 digest: $expected_sha"

  local temp_file actual_sha target staged
  temp_file="$(mktemp)"
  TEMP_PATHS+=("$temp_file")

  # --url marks the URL explicitly. curl treats a bare `--` as "every remaining
  # argument is a URL", which would silently swallow -o and print to stdout.
  curl -fsSL --proto '=https' --proto-redir '=https' -o "$temp_file" --url "$url" || \
    die "Could not download the Karpathy skill from $url"

  actual_sha="$(sha256sum -- "$temp_file" | cut -d' ' -f1)"
  [[ "$actual_sha" == "$expected_sha" ]] || \
    die "Karpathy skill checksum mismatch: expected $expected_sha, got $actual_sha"

  # Every harness resolves a skill by the name in its frontmatter, which must
  # equal the containing directory. A file that fails this is silently ignored
  # at load time, so it is worth catching here instead.
  [[ "$(sed -n 's/^name: //p' "$temp_file" | head -n1)" == "karpathy-guidelines" ]] || \
    die "The downloaded skill does not declare 'name: karpathy-guidelines'"

  # The verified file is copied byte for byte rather than round-tripped through
  # a shell string, which would strip its trailing newline and install content
  # the digest above never covered.
  #
  # Staging beside the target and moving into place keeps the replacement
  # atomic, so an interrupted run cannot leave a truncated skill behind, and
  # replaces a symlink rather than writing through it to whatever it points at.
  # mktemp creates its file 0600, so the mode is always set explicitly.
  for target in "$claude_skill" "$codex_skill"; do
    mkdir -p -- "$(dirname -- "$target")"
    if [[ -f "$target" && ! -L "$target" ]] && cmp -s -- "$target" "$temp_file"; then
      chmod 644 -- "$target"
      continue
    fi
    staged="$target.adt-staged.$$"
    TEMP_PATHS+=("$staged")
    cp -- "$temp_file" "$staged"
    chmod 644 -- "$staged"
    # -T refuses to descend into a directory standing where the file belongs.
    mv -Tf -- "$staged" "$target"
  done
}

configure_project() {
  [[ -n "$PROJECT_PATH" ]] || return 0

  local project
  project="$(realpath -m "$PROJECT_PATH")"

  [[ -d "$project" ]] || die "Project directory does not exist: $project"
  [[ -d "$project/.git" || -f "$project/.git" ]] || die "Project is not a Git repository: $project"

  if (( DRY_RUN == 0 )); then
    command -v openspec >/dev/null 2>&1 || die "OpenSpec is required for --project. Install it first or remove --skip-openspec."
  fi

  if [[ -e "$project/.envrc" ]]; then
    info "Preserving existing direnv configuration: $project/.envrc"
  else
    log "Creating direnv configuration in $project/.envrc"
    if (( DRY_RUN == 1 )); then
      printf '%s\n' 'dotenv_if_exists .env.local'
    else
      printf '%s\n' 'dotenv_if_exists .env.local' > "$project/.envrc"
    fi
    info "Review $project/.envrc, then run: cd $project && direnv allow"
  fi

  log "Initializing or refreshing OpenSpec in $project"
  if (( DRY_RUN == 1 )); then
    printf '+ cd %q\n' "$project"
    quote_command openspec init --force --tools "$OPENSPEC_TOOLS" --profile core
    quote_command openspec update
    return
  fi

  (
    cd "$project"
    openspec init --force --tools "$OPENSPEC_TOOLS" --profile core
    openspec update
  )
}

verify_installation() {
  log "Verifying workstation"

  if (( DRY_RUN == 1 )); then
    info "Dry-run verification: commands are listed but not executed."
  fi

  if (( SKIP_RUNTIMES == 0 )); then
    if (( DRY_RUN == 1 )); then
      quote_command "$MISE_BIN" --version
      quote_command "$MISE_BIN" doctor
      quote_command "$MISE_BIN" ls
      quote_command "$MISE_BIN" exec -- node --version
      quote_command "$MISE_BIN" exec -- python --version
      quote_command "$MISE_BIN" exec -- uv --version
      quote_command "$MISE_BIN" exec -- dotnet --list-sdks
      quote_command "$MISE_BIN" exec "java@$JAVA_21_VERSION" -- java -version
      quote_command "$MISE_BIN" exec "java@$JAVA_17_VERSION" -- java -version
    else
      [[ -x "$MISE_BIN" ]] || die "mise is missing at $MISE_BIN"
      "$MISE_BIN" --version
      "$MISE_BIN" doctor
      "$MISE_BIN" ls
      "$MISE_BIN" exec -- node --version
      "$MISE_BIN" exec -- python --version
      "$MISE_BIN" exec -- uv --version
      "$MISE_BIN" exec -- dotnet --list-sdks
      "$MISE_BIN" exec "java@$JAVA_21_VERSION" -- java -version
      "$MISE_BIN" exec "java@$JAVA_17_VERSION" -- java -version
    fi
  fi

  verify_command() {
    local name="$1"
    shift
    if (( DRY_RUN == 1 )); then
      quote_command "$@"
    else
      command -v "$name" >/dev/null 2>&1 || die "$name is not available on PATH"
      "$@"
    fi
  }

  (( SKIP_OPENCODE == 1 )) || verify_command opencode opencode --version
  (( SKIP_CLAUDE == 1 )) || verify_command claude claude --version
  (( SKIP_CODEX == 1 )) || verify_command codex codex --version
  (( SKIP_OPENSPEC == 1 )) || verify_command openspec openspec --version
  verify_command direnv direnv --version

  if (( SKIP_RUNTIMES == 0 && SKIP_QUALITY_TOOLS == 0 )); then
    if (( DRY_RUN == 1 )); then
      quote_command "$MISE_BIN" exec -- shellcheck --version
      quote_command "$MISE_BIN" exec -- gitleaks version
      quote_command "$MISE_BIN" exec -- python -c 'import yaml; print(yaml.__version__)'
    else
      "$MISE_BIN" exec -- shellcheck --version
      "$MISE_BIN" exec -- gitleaks version
      # Reported rather than fatal, matching the install step: the library is a
      # convenience for other repositories' test suites, not something this
      # workstation depends on to function.
      "$MISE_BIN" exec -- python -c 'import yaml; print("PyYAML", yaml.__version__)' ||
        warn "PyYAML is not importable from the mise-managed Python; suites that skip on it will skip."
    fi
  fi

  if (( SKIP_SUPERPOWERS == 0 && DRY_RUN == 0 )) && [[ -s "$OPENCODE_CONFIG" ]] && jq empty "$OPENCODE_CONFIG" >/dev/null 2>&1; then
    local plugin="$SUPERPOWERS_PLUGIN_BASE#$SUPERPOWERS_REF"
    jq -e --arg plugin "$plugin" '.plugin | type == "array" and index($plugin) != null' "$OPENCODE_CONFIG" >/dev/null || \
      die "Superpowers $SUPERPOWERS_REF is not configured in $OPENCODE_CONFIG"
  fi

  if (( SKIP_KARPATHY == 0 && DRY_RUN == 0 )); then
    # An instruction file that every agent on the machine reads is worth
    # verifying by content, not by filename. On the pinned ref the expected
    # digest is known, so a corrupted or swapped body is caught; on a custom ref
    # the caller's own digest is the reference.
    local skill skill_sha expected_skill_sha=""
    if [[ "$KARPATHY_REF" == "$KARPATHY_DEFAULT_REF" ]]; then
      expected_skill_sha="$KARPATHY_DEFAULT_SHA256"
    elif [[ -n "$KARPATHY_SHA256" ]]; then
      expected_skill_sha="${KARPATHY_SHA256,,}"
    fi

    for skill in "$HOME/.claude/skills/karpathy-guidelines/SKILL.md" \
                 "$CODEX_HOME/skills/karpathy-guidelines/SKILL.md"; do
      [[ -s "$skill" ]] || die "The Karpathy guidelines skill is missing at $skill"
      [[ "$(sed -n 's/^name: //p' "$skill" | head -n1)" == "karpathy-guidelines" ]] || \
        die "$skill does not declare 'name: karpathy-guidelines' and no harness will load it"
      if [[ -n "$expected_skill_sha" ]]; then
        skill_sha="$(sha256sum -- "$skill" | cut -d' ' -f1)"
        [[ "$skill_sha" == "$expected_skill_sha" ]] || \
          die "$skill does not match the expected digest: expected $expected_skill_sha, got $skill_sha"
      fi
    done
  fi
}

print_summary() {
  log "Setup complete"

  if (( DRY_RUN == 1 )); then
    info "No changes were made because --dry-run was used."
    return
  fi

  local karpathy_note
  if (( SKIP_KARPATHY == 1 )); then
    karpathy_note="     The Karpathy guidelines skill was NOT installed (--skip-karpathy)."
  else
    karpathy_note="     The Karpathy guidelines skill needs no such step: it is already installed
     for all three harnesses at
       \$HOME/.claude/skills/karpathy-guidelines/  (Claude Code, and OpenCode)
       $CODEX_HOME/skills/karpathy-guidelines/  (Codex)
     OpenCode reads the Claude Code directory, so it needs no copy of its own."
  fi

  cat <<EOF_SUMMARY

Manual steps after installation:
  1. Open a fresh shell, or run: exec bash -l
  2. OpenCode: run 'opencode', enter '/connect', select OpenAI, and authenticate
     with your ChatGPT Plus/Pro account.
  3. Claude Code: run 'claude' and complete the interactive sign-in.
  4. Codex: run 'codex' and sign in with your ChatGPT account.
  5. Install Superpowers separately in Claude Code and Codex using each
     harness's plugin/skill installation mechanism.
$karpathy_note
  6. For the streamlined OpenSpec 1.9.0 workflow, run once:
       openspec config profile core
   7. To initialize or update OpenSpec for a specific Git project, run:
        ./$SCRIPT_NAME --project <path>
      This creates a safe .envrc when one is absent. Review it, then run:
        cd <path> && direnv allow

Useful maintenance commands:
  ./$SCRIPT_NAME --verify-only
  ./$SCRIPT_NAME --upgrade
  ./$SCRIPT_NAME --repair-codex

Useful checks:
  command -v mise node java python dotnet uv direnv opencode claude codex openspec
  mise ls
  shellcheck --version
  gitleaks version
  python -c 'import yaml; print(yaml.__version__)'
  dotnet --list-sdks
  opencode --version
  claude --version
  codex --version
  openspec --version
  direnv --version
EOF_SUMMARY
}

main() {
  parse_args "$@"
  validate_environment

  if (( VERIFY_ONLY == 1 )); then
    verify_installation
    return
  fi

  install_system_packages
  ensure_shell_configuration
  run mkdir -p "$HOME/code"
  install_mise
  configure_runtimes
  install_python_quality_libraries
  install_opencode
  install_claude
  install_codex
  install_openspec
  configure_opencode_superpowers
  install_karpathy_skill
  configure_project
  verify_installation
  print_summary
}

main "$@"
