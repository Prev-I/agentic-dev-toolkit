#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="0.5.0"
SCHEMA_VERSION=1
WSL_CONF="${WTD_WSL_CONF:-/etc/wsl.conf}"
MOUNTS_FILE="${WTD_MOUNTS_FILE:-/proc/self/mounts}"
WSL_INTEROP_FILE="${WTD_WSL_INTEROP_FILE:-/proc/sys/fs/binfmt_misc/WSLInterop}"
SCAN_PATH="${WTD_SCAN_PATH:-${PATH:-}}"
# The Unix socket a local container runtime listens on.
#
# Expanded with `-` rather than `:-` so that an explicitly empty
# WTD_DOCKER_SOCKET means "this machine has no socket" instead of falling back
# to the default. The test suite needs to assert that the reachability check
# stays silent, and with `:-` an empty override would silently re-adopt
# /var/run/docker.sock and make those cases pass or fail according to whether
# the developer running them happens to have a runtime installed.
DOCKER_SOCKET="${WTD_DOCKER_SOCKET-/var/run/docker.sock}"

# Component root of the doctor itself, resolved once so the catalog seam below
# has a real default. This mirrors install.sh's ADT_INSTALL_ROOT, one
# directory up from where a project-relative catalog default is anchored.
COMPONENT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# File-path seams, following the same script-scope `${VAR:-default}` shape as
# WSL_CONF/MOUNTS_FILE/WSL_INTEROP_FILE above. This is safe here in a way it
# is NOT for the executable seams below (WTD_OPENSPEC_BIN, WTD_TIMEOUT_BIN):
# there is no "search PATH for a catalog file" fallback to preserve, so an
# always-set default does not collapse a three-state contract into two.
WTD_CATALOG_FILE="${WTD_CATALOG_FILE:-$COMPONENT_ROOT/../catalog/software-catalog.env}"
WTD_RECEIPT_FILE="${WTD_RECEIPT_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev-toolkit/install-receipt.env}"
WTD_MISE_TOOLCHAIN_CONFIG="${WTD_MISE_TOOLCHAIN_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/agentic-dev-toolkit.toml}"

JSON_MODE=0
PROBE_MODE=0
CURRENT_ACTION=""
EXEC_ERROR=0
FIX_SCOPE="wsl"
DRY_RUN=0
DROP_MISSING=0
WSL_CHANGED=0
PATH_CHANGED=0

# Task 7: the TOOLKIT_ finding domain -- receipt-derived state and
# comparison A's parsed mise configuration, declared once at script scope
# beside the finding accumulators below.
#
# TOOLKIT_MISE_DOMAIN is comparison A's exact twelve-key domain: the keys the
# generated [tools] table is able to express. pyyaml, openspec, superpowers,
# karpathy-ref and karpathy-sha256 are outside it because mise is not how
# they are installed or configured.
TOOLKIT_MISE_DOMAIN=(
  java-17 java-21 dotnet-8 dotnet-10 python node bun maven uv dotnet-ef
  shellcheck gitleaks
)

# CATALOG_REQUIRED is the full seventeen-key catalog contract -- the same
# required set install.sh's CATALOG_REQUIRED declares, in catalog declaration
# order -- not to be confused with TOOLKIT_MISE_DOMAIN above, which is
# comparison A's narrower twelve-key mise domain. load_catalog below passes
# this to validate_kv so a syntactically valid but incomplete catalog is
# rejected the same way install.sh rejects one, instead of being accepted and
# blamed on the receipt later.
# shellcheck disable=SC2034 # read by validate_kv through its nameref
CATALOG_REQUIRED=(
  java-17 java-21 dotnet-10 dotnet-8 python node bun maven
  dotnet-ef uv shellcheck gitleaks pyyaml openspec superpowers
  karpathy-ref karpathy-sha256
)

declare -A RECEIPT_VALUES=() RECEIPT_LINES=()
declare -a RECEIPT_ORDER=()
RECEIPT_ERROR=""
# Receipt keys whose suffix the CURRENT catalog does not pin. Either the pin
# was retired, or the receipt was hand-edited -- the doctor cannot tell which,
# so it reports rather than rejects. Rejecting would make retiring one pin
# take the whole TOOLKIT_ domain dark on every provisioned machine at once.
declare -a RECEIPT_UNKNOWN_KEYS=()

declare -A CATALOG_VALUES=() CATALOG_LINES=()
declare -a CATALOG_ORDER=()
CATALOG_ERROR=""

declare -A MISE_CONFIG_VALUES=()

TOOLKIT_PROBE_OUTPUT=""

F_SEVERITY=()
F_CODE=()
F_SUBJECT=()
F_MESSAGE=()

usage() {
  cat <<'USAGE'
Usage:
  wsl-toolchain-doctor.sh audit [--json] [--probe]
  wsl-toolchain-doctor.sh fix [--path|--all] [--dry-run] [--drop-missing] [--json]
  wsl-toolchain-doctor.sh explain <command> [--json]
  wsl-toolchain-doctor.sh --version

Fix scopes:
  fix              remediate /etc/wsl.conf only
  fix --path       remediate safe persistent PATH assignments only
  fix --all        remediate both layers
USAGE
}

add_finding() {
  F_SEVERITY+=("$1")
  F_CODE+=("$2")
  F_SUBJECT+=("$3")
  F_MESSAGE+=("$4")
}

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_wsl() {
  # WTD_ASSUME_WSL is authoritative when set: 1 forces WSL, anything else
  # forces non-WSL. Without it only the probe below decides, and that cannot
  # be simulated from inside a real WSL distro.
  if [[ -n "${WTD_ASSUME_WSL+x}" ]]; then
    [[ "$WTD_ASSUME_WSL" == "1" ]] && return 0
    return 1
  fi
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease /proc/version 2>/dev/null
}

parse_bool() {
  case "$(lower "$(trim "$1")")" in
    true|1|yes|on) printf 'true'; return 0 ;;
    false|0|no|off) printf 'false'; return 0 ;;
    *) return 1 ;;
  esac
}

INTEROP_SECTION_COUNT=0
INTEROP_ENABLED_RAW=""
APPEND_WINDOWS_PATH_RAW=""
INTEROP_ENABLED_SEEN=0
APPEND_WINDOWS_PATH_SEEN=0

read_wsl_conf() {
  INTEROP_SECTION_COUNT=0
  INTEROP_ENABLED_RAW=""
  APPEND_WINDOWS_PATH_RAW=""
  INTEROP_ENABLED_SEEN=0
  APPEND_WINDOWS_PATH_SEEN=0

  [[ -f "$WSL_CONF" ]] || return 0

  local line stripped section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="$(trim "$line")"
    [[ -z "$stripped" ]] && continue
    [[ "$stripped" == \#* || "$stripped" == \;* ]] && continue

    if [[ "$stripped" =~ ^\[([^]]+)\]$ ]]; then
      section="$(lower "$(trim "${BASH_REMATCH[1]}")")"
      if [[ "$section" == "interop" ]]; then
        INTEROP_SECTION_COUNT=$((INTEROP_SECTION_COUNT + 1))
      fi
      continue
    fi

    [[ "$section" == "interop" ]] || continue
    if [[ "$stripped" =~ ^([^=]+)=(.*)$ ]]; then
      local key value
      key="$(lower "$(trim "${BASH_REMATCH[1]}")")"
      value="$(trim "${BASH_REMATCH[2]}")"
      case "$key" in
        enabled)
          INTEROP_ENABLED_SEEN=$((INTEROP_ENABLED_SEEN + 1))
          INTEROP_ENABLED_RAW="$value"
          ;;
        appendwindowspath)
          APPEND_WINDOWS_PATH_SEEN=$((APPEND_WINDOWS_PATH_SEEN + 1))
          APPEND_WINDOWS_PATH_RAW="$value"
          ;;
      esac
    fi
  done < "$WSL_CONF"
}

audit_wsl_environment() {
  if ! is_wsl; then
    add_finding ERROR NOT_WSL "environment" "This command is intended to run inside WSL."
    EXEC_ERROR=1
    return
  fi
  add_finding INFO WSL_DETECTED "environment" "WSL environment detected."

  if [[ -e "$WSL_INTEROP_FILE" ]]; then
    add_finding INFO WSL_INTEROP_HANDLER_PRESENT "$WSL_INTEROP_FILE" "WSLInterop binfmt handler is present."
  else
    add_finding FAIL WSL_INTEROP_HANDLER_MISSING "$WSL_INTEROP_FILE" "WSLInterop binfmt handler is missing; Windows process interop is not currently available."
  fi
}

audit_wsl_conf() {
  read_wsl_conf
  if (( INTEROP_SECTION_COUNT > 1 )); then
    add_finding ERROR WSL_CONF_DUPLICATE_INTEROP "$WSL_CONF" "Multiple [interop] sections make remediation ambiguous."
    EXEC_ERROR=1
    return
  fi
  if (( INTEROP_ENABLED_SEEN > 1 || APPEND_WINDOWS_PATH_SEEN > 1 )); then
    add_finding ERROR WSL_CONF_DUPLICATE_KEY "$WSL_CONF" "Duplicate [interop] keys make the effective configuration ambiguous."
    EXEC_ERROR=1
    return
  fi

  local enabled="true" append="true"
  if (( INTEROP_ENABLED_SEEN == 1 )); then
    if ! enabled="$(parse_bool "$INTEROP_ENABLED_RAW")"; then
      add_finding ERROR WSL_CONF_INVALID_ENABLED "$WSL_CONF" "Invalid [interop] enabled value: $INTEROP_ENABLED_RAW"
      EXEC_ERROR=1
    fi
  fi
  if (( APPEND_WINDOWS_PATH_SEEN == 1 )); then
    if ! append="$(parse_bool "$APPEND_WINDOWS_PATH_RAW")"; then
      add_finding ERROR WSL_CONF_INVALID_APPEND_WINDOWS_PATH "$WSL_CONF" "Invalid [interop] appendWindowsPath value: $APPEND_WINDOWS_PATH_RAW"
      EXEC_ERROR=1
    fi
  fi
  (( EXEC_ERROR == 0 )) || return

  if [[ "$enabled" == "true" ]]; then
    add_finding INFO WSL_INTEROP_ENABLED "$WSL_CONF" "Effective interop.enabled=true."
  else
    add_finding FAIL WSL_INTEROP_DISABLED "$WSL_CONF" "Policy requires interop.enabled=true."
  fi

  if [[ "$append" == "false" ]]; then
    add_finding INFO WSL_APPEND_WINDOWS_PATH_DISABLED "$WSL_CONF" "Effective interop.appendWindowsPath=false."
  else
    add_finding FAIL WSL_APPEND_WINDOWS_PATH_ENABLED "$WSL_CONF" "Policy requires interop.appendWindowsPath=false; the effective default is true when unset."
  fi
}


decode_mount_field() {
  # procfs mount tables encode space/tab/newline/backslash as octal escapes.
  printf '%b' "$1"
}

mount_info_for_path() {
  local input=$1 path=$1
  if [[ -e "$input" ]]; then
    path="$(readlink -f -- "$input" 2>/dev/null || printf '%s' "$input")"
  fi

  local best_len=-1 best="" source mountpoint fstype options rest mp len
  while IFS=' ' read -r source mountpoint fstype options rest; do
    [[ -n "${mountpoint:-}" ]] || continue
    mp="$(decode_mount_field "$mountpoint")"
    if [[ "$mp" == "/" ]]; then
      [[ "$path" == /* ]] || continue
    elif [[ "$path" != "$mp" && "$path" != "$mp/"* ]]; then
      continue
    fi
    len=${#mp}
    if (( len > best_len )); then
      best_len=$len
      best="$fstype|$options|$source|$mp"
    fi
  done < "$MOUNTS_FILE"

  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

mount_is_windows_backed() {
  local fstype=$1 options=$2 source=$3 source_decoded
  source_decoded="$(decode_mount_field "$source" 2>/dev/null || printf '%s' "$source")"
  [[ "$(lower "$fstype")" == "drvfs" ]] && return 0
  [[ "$(lower "$options")" == *"aname=drvfs"* ]] && return 0
  [[ "$source_decoded" =~ ^[A-Za-z]:([\\/]|$) ]] && return 0
  [[ "$source_decoded" == \\* ]] && return 0
  return 1
}

is_windows_backed_path() {
  local info fstype options source mountpoint
  info="$(mount_info_for_path "$1")" || return 1
  IFS='|' read -r fstype options source mountpoint <<< "$info"
  mount_is_windows_backed "$fstype" "$options" "$source"
}

is_rancher_linux_path() {
  local p base
  p="$(lower "$1")"
  base="/rancher desktop/resources/resources/linux"
  # Rancher Desktop ships Linux container tooling in two sibling directories.
  # Both are in scope for the narrow exception; the ELF or Linux-script format
  # check still applies at the call site.
  [[ "$p" == *"$base/bin" || "$p" == *"$base/bin/"* || \
     "$p" == *"$base/docker-cli-plugins" || \
     "$p" == *"$base/docker-cli-plugins/"* ]]
}

# Windows-backed directories whose contents are Linux-executable launchers.
#
# The policy this tool enforces exists to stop a Linux build binding to a
# Windows PE where a Linux binary was meant. It does not follow from that
# that every directory on a Windows mount is dangerous: an `sh` script or a
# Linux ELF binary that merely lives on DrvFs runs correctly, just slowly.
# The two that a WSL developer cannot work without are the editor launcher
# and the container tooling, and both are exactly that.
#
# Allowlisting a directory does NOT allowlist a Windows binary inside it.
# Tool classification is independent of this list and still fails PE targets,
# Windows shebang interpreters, and any managed runtime resolved from a
# Windows mount, so widening the list cannot smuggle in a PE.
#
# Substrings, matched case-insensitively against the canonical path, so a
# per-user or non-default install location still matches. Extend for this
# machine with WTD_PATH_ALLOW, colon-separated.
windows_path_allowlist() {
  printf '%s\n' "/rancher desktop/resources/resources/linux/bin"
  printf '%s\n' "/rancher desktop/resources/resources/linux/docker-cli-plugins"
  printf '%s\n' "/microsoft vs code/bin"
  printf '%s\n' "/microsoft vs code insiders/bin"

  local extra
  if [[ -n "${WTD_PATH_ALLOW:-}" ]]; then
    # The `|| [[ -n ]]` guard is load-bearing: the last field has no trailing
    # newline, so without it a single-entry WTD_PATH_ALLOW is read and then
    # silently discarded when read returns non-zero.
    while IFS= read -r extra || [[ -n "$extra" ]]; do
      [[ -n "$(trim "$extra")" ]] || continue
      lower "$(trim "$extra")"
      printf '\n'
    done < <(printf '%s' "$WTD_PATH_ALLOW" | tr ':' '\n')
  fi
}

is_allowlisted_windows_path() {
  local p entry
  p="$(lower "$1")"
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    if [[ "$p" == *"$entry" || "$p" == *"$entry/"* ]]; then
      return 0
    fi
  done < <(windows_path_allowlist)
  return 1
}

audit_path_raw_syntax() {
  local value=$SCAN_PATH
  if [[ "$value" =~ (^|[:;])[A-Za-z]:[\\/] ]]; then
    add_finding FAIL PATH_WINDOWS_SYNTAX "PATH" "Windows drive syntax is present in the WSL PATH; inspect the raw value before POSIX colon segmentation."
  fi
  if [[ "$value" == *';'* ]]; then
    add_finding FAIL PATH_WINDOWS_SEPARATOR "PATH" "Semicolon separator found in WSL PATH; Windows-style PATH construction leaked into the environment."
  fi
  if [[ "$value" == *\"* || "$value" == *\'* ]]; then
    add_finding FAIL PATH_LITERAL_QUOTE "PATH" "Literal quote character is present in the effective PATH."
  fi
  if [[ "$value" =~ \$\{?[A-Za-z_][A-Za-z0-9_]*\}? || "$value" =~ %[A-Za-z_][A-Za-z0-9_]*% ]]; then
    add_finding FAIL PATH_LITERAL_VARIABLE "PATH" "Unexpanded variable token is present in the effective PATH."
  fi
  if [[ "$value" == *$'\r'* || "$value" == *$'\n'* || "$value" == *$'\t'* ]]; then
    add_finding FAIL PATH_CONTROL_CHAR "PATH" "PATH contains a CR, LF, or TAB control character."
  fi
  # shellcheck disable=SC1003
  if [[ "$value" == *'\\'* ]]; then
    add_finding WARN PATH_EXCESSIVE_ESCAPE "PATH" "PATH contains repeated backslash escaping; verify that Windows escaping has not leaked into WSL."
  fi
  if [[ "$value" == :* || "$value" == *: || "$value" == *::* ]]; then
    add_finding WARN PATH_EMPTY_ENTRY "PATH" "Empty PATH entry resolves to the current working directory."
  fi
}

audit_path_entries() {
  audit_path_raw_syntax
  local path_value=$SCAN_PATH entry canonical
  local -a entries=()
  local -A seen_text=() seen_canonical=()
  IFS=':' read -r -a entries <<< "$path_value"
  for entry in "${entries[@]}"; do
    [[ -n "$entry" ]] || continue

    if [[ ${seen_text[$entry]+x} ]]; then
      add_finding WARN PATH_DUPLICATE "$entry" "Duplicate textual PATH entry; the first occurrence already wins."
    else
      seen_text[$entry]=1
    fi

    if [[ "$entry" == "." ]]; then
      add_finding FAIL PATH_CURRENT_DIRECTORY "$entry" "Current-directory PATH entries are unsafe and non-deterministic."
    elif [[ "$entry" != /* ]]; then
      add_finding WARN PATH_RELATIVE_ENTRY "$entry" "Relative PATH entry depends on the current working directory."
    fi

    if [[ -e "$entry" ]]; then
      canonical="$(readlink -f -- "$entry" 2>/dev/null || printf '%s' "$entry")"
      if [[ ! -d "$entry" ]]; then
        add_finding FAIL PATH_ENTRY_NOT_DIRECTORY "$entry" "PATH entry exists but is not a directory."
      elif [[ ${seen_canonical[$canonical]+x} ]]; then
        add_finding WARN PATH_DUPLICATE_CANONICAL "$entry" "PATH entry resolves to a directory already present earlier: $canonical"
      else
        seen_canonical[$canonical]=1
      fi
    else
      canonical="$entry"
      add_finding WARN PATH_ENTRY_MISSING "$entry" "PATH entry does not exist."
    fi

    if is_windows_backed_path "$canonical"; then
      if is_rancher_linux_path "$canonical"; then
        add_finding INFO PATH_RANCHER_LINUX_ALLOWED "$entry" "Rancher Desktop Linux-bin directory is an allowed Windows-backed PATH exception."
      elif is_allowlisted_windows_path "$canonical"; then
        add_finding INFO PATH_ALLOWLISTED_WINDOWS "$entry" "Windows-backed PATH entry is allowlisted as a Linux-executable launcher directory; tool checks still reject PE targets."
      else
        add_finding FAIL PATH_WINDOWS_DRVFS "$entry" "Windows-backed DrvFs PATH entry violates Linux-first isolation."
      fi
    else
      add_finding INFO PATH_LINUX "$entry" "PATH entry is not Windows-backed."
    fi
  done
}


MANAGED_TOOL_NAMES=(
  dotnet dotnet.exe
  java java.exe javac javac.exe jar jar.exe
  mvn mvn.cmd mvn.bat mvnDebug mvnDebug.cmd mvnDebug.bat
  python python.exe python3 python3.exe pip pip.exe pip3 pip3.exe
  uv uv.exe uvx uvx.exe
)
CONTAINER_TOOL_NAMES=(
  docker docker.exe docker-compose docker-compose.exe
  nerdctl nerdctl.exe kubectl kubectl.exe helm helm.exe
)

# The subset of CONTAINER_TOOL_NAMES that can actually drive a container
# runtime. kubectl and helm talk to a Kubernetes API server and docker-compose
# is an orchestrator over a client that must already be present, so none of the
# three proves a shell can reach the runtime and none may suppress the
# reachability finding. nerdctl does qualify: Rancher Desktop ships it beside
# docker and it manages the same containers.
#
# The .exe spellings are deliberate. A PE docker.exe on PATH is already reported
# by classify_tool_candidate as TOOL_WINDOWS_PE, which is the more precise
# diagnosis; counting it here keeps the two checks from both firing about one
# binary.
CONTAINER_RUNTIME_CLI_NAMES=(
  docker docker.exe nerdctl nerdctl.exe
)

tool_kind() {
  local name=$1 item
  for item in "${MANAGED_TOOL_NAMES[@]}"; do
    [[ "$name" == "$item" ]] && { printf 'managed'; return 0; }
  done
  for item in "${CONTAINER_TOOL_NAMES[@]}"; do
    [[ "$name" == "$item" ]] && { printf 'container'; return 0; }
  done
  printf 'unknown'
}

enumerate_command_candidates() {
  local command_name=$1 dir candidate
  local -a dirs=()
  IFS=':' read -r -a dirs <<< "$SCAN_PATH"
  for dir in "${dirs[@]}"; do
    [[ -n "$dir" ]] || dir='.'
    dir="${dir%/}"
    [[ -n "$dir" ]] || dir='/'
    candidate="$dir/$command_name"
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      if [[ -x "$candidate" || "$command_name" == *.exe || "$command_name" == *.cmd || "$command_name" == *.bat ]]; then
        printf '%s\n' "$candidate"
      fi
    fi
  done
}

binary_format() {
  local path=$1 hex
  [[ -f "$path" ]] || { printf 'MISSING'; return 0; }
  hex="$(od -An -tx1 -N4 -- "$path" 2>/dev/null | tr -d '[:space:]')"
  case "$hex" in
    7f454c46*) printf 'ELF' ;;
    4d5a*) printf 'PE' ;;
    2321*) printf 'SCRIPT' ;;
    '') printf 'EMPTY' ;;
    *) printf 'OTHER' ;;
  esac
}

script_interpreter() {
  local path=$1 first interp
  IFS= read -r first < "$path" || true
  [[ "$first" == '#!'* ]] || return 1
  first="${first#\#!}"
  first="$(trim "$first")"
  interp="${first%%[[:space:]]*}"
  [[ -n "$interp" ]] || return 1
  printf '%s' "$interp"
}

script_has_windows_reference() {
  local path=$1
  head -n 256 -- "$path" 2>/dev/null | grep -Eiq '([[:alnum:]_.-]+\.(exe|cmd|bat))|([A-Za-z]:\\)'
}

classify_tool_candidate() {
  local command_name=$1 candidate=$2 kind canonical format interpreter=""
  kind="$(tool_kind "$command_name")"
  canonical="$(readlink -f -- "$candidate" 2>/dev/null || printf '%s' "$candidate")"
  format="$(binary_format "$canonical")"

  if [[ "$format" == "PE" ]]; then
    add_finding FAIL TOOL_WINDOWS_PE "$candidate" "$command_name resolves to PE/MZ Windows executable: $canonical"
    return
  fi

  if [[ "$format" == "SCRIPT" ]]; then
    interpreter="$(script_interpreter "$canonical" 2>/dev/null || true)"
    if [[ -n "$interpreter" ]]; then
      if [[ "$(lower "$interpreter")" == *.exe || "$(lower "$interpreter")" == *.cmd || "$(lower "$interpreter")" == *.bat ]] || is_windows_backed_path "$interpreter"; then
        add_finding FAIL TOOL_SCRIPT_WINDOWS_INTERPRETER "$candidate" "$command_name script uses a Windows-backed shebang interpreter: $interpreter"
      fi
    fi
  fi

  case "$kind" in
    managed)
      if is_rancher_linux_path "$canonical"; then
        add_finding FAIL MANAGED_TOOL_RANCHER_PATH "$candidate" "$command_name is managed language/tooling and may not use the Rancher Desktop exception; target=$canonical format=$format"
      elif is_windows_backed_path "$canonical"; then
        add_finding FAIL MANAGED_TOOL_WINDOWS_BACKED "$candidate" "$command_name final target is Windows-backed: $canonical format=$format"
      else
        add_finding INFO MANAGED_TOOL_LINUX "$candidate" "$command_name final target is Linux-backed: $canonical format=$format"
      fi
      if [[ "$format" == "SCRIPT" ]] && script_has_windows_reference "$canonical"; then
        add_finding WARN TOOL_WRAPPER_WINDOWS_REFERENCE "$candidate" "$command_name wrapper contains an explicit .exe/.cmd/.bat or Windows-drive reference; inspect it manually."
      fi
      ;;
    container)
      if is_rancher_linux_path "$canonical"; then
        if [[ "$format" == "ELF" || "$format" == "SCRIPT" ]]; then
          add_finding INFO CONTAINER_TOOL_RANCHER_LINUX "$candidate" "$command_name uses Rancher Desktop Linux tooling: $canonical format=$format"
        else
          add_finding FAIL CONTAINER_TOOL_RANCHER_FORMAT "$candidate" "$command_name is under Rancher Desktop Linux-bin but format is $format, expected ELF or Linux script."
        fi
      elif is_windows_backed_path "$canonical"; then
        add_finding FAIL CONTAINER_TOOL_WINDOWS_BACKED "$candidate" "$command_name final target is Windows-backed outside the Rancher Linux exception: $canonical format=$format"
      else
        add_finding INFO CONTAINER_TOOL_LINUX "$candidate" "$command_name final target is Linux-backed: $canonical format=$format"
      fi
      ;;
    *)
      if is_windows_backed_path "$canonical"; then
        add_finding FAIL TOOL_WINDOWS_BACKED "$candidate" "$command_name final target is Windows-backed: $canonical format=$format"
      else
        add_finding INFO TOOL_LINUX "$candidate" "$command_name final target is Linux-backed: $canonical format=$format"
      fi
      ;;
  esac
}

audit_toolchains() {
  local name candidate
  for name in "${MANAGED_TOOL_NAMES[@]}" "${CONTAINER_TOOL_NAMES[@]}"; do
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      classify_tool_candidate "$name" "$candidate"
    done < <(enumerate_command_candidates "$name")
  done
}

# Evidence that a container runtime is reachable from this distro, printed so
# the finding can name what triggered it.
#
# Both signals are vendor-neutral, which is the point: an earlier draft of this
# check looked for Rancher Desktop's installation directory through mount
# provenance, and that is both narrower and less accurate. Rancher also installs
# per-user under %LOCALAPPDATA%\Programs, so a "Program Files" probe misses it,
# and an installed-but-stopped Rancher offers nothing to reach, so reporting it
# would be provisioning advice rather than drift.
#
# The socket test is `-S`, not `-e`. A stale regular file left at the socket
# path is not a runtime, and treating it as one would send a reader hunting for
# a PATH problem they do not have.
container_runtime_evidence() {
  if [[ -n "$DOCKER_SOCKET" && -S "$DOCKER_SOCKET" ]]; then
    printf '%s' "$DOCKER_SOCKET"
    return 0
  fi
  # A daemon on TCP or a non-default socket is just as unreachable from a shell
  # that has no client, and needs no filesystem to detect.
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    printf '%s' "$DOCKER_HOST"
    return 0
  fi
  return 1
}

# Reports a container runtime that nothing on PATH can drive.
#
# This is the one toolchain check that fires on a tool's absence, and it needs
# to be: classify_tool_candidate only inspects names it finds, so a CLI that is
# missing entirely produces no finding and the audit exits clean. Rancher
# Desktop's WSL integration reaches exactly that state -- it mounts the daemon
# socket and writes ~/.docker/config.json, but never adds its Linux bin
# directory to PATH.
#
# Gated on evidence because "no container CLI" is not a defect on its own. A
# machine that runs no containers is not drifting, and telling it to install a
# runtime would be provisioning, which this tool does not do. Only a runtime
# that is demonstrably reachable while no CLI can reach it is drift.
#
# WARN, not FAIL: result_exit_code turns any FAIL into exit 1, and a machine
# that deliberately runs no container CLI must not start failing its audit.
audit_container_reachability() {
  local evidence name candidate
  evidence="$(container_runtime_evidence)" || return 0
  for name in "${CONTAINER_RUNTIME_CLI_NAMES[@]}"; do
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      return 0
    done < <(enumerate_command_candidates "$name")
  done
  add_finding WARN CONTAINER_TOOL_UNREACHABLE "$evidence" "A container runtime is reachable at $evidence but no container CLI (docker, nerdctl) is on the scanned PATH; the runtime cannot be driven from this shell."
}


mise_bin() {
  if [[ ${WTD_MISE_BIN+x} ]]; then
    [[ -n "$WTD_MISE_BIN" ]] || return 1
    printf '%s' "$WTD_MISE_BIN"
    return 0
  fi
  command -v mise 2>/dev/null
}

# openspec_bin and timeout_bin follow mise_bin's shape verbatim -- ${VAR+x}
# for set-ness, printf '%s' with no trailing newline, command -v as the
# fall-through -- plus one addition mise_bin does not make: an -x usability
# check. A seam pointing at a path that exists but is not executable is
# unusable, and is treated exactly like an empty seam: return 1, search
# nothing. Never assign WTD_OPENSPEC_BIN/WTD_TIMEOUT_BIN at script scope --
# doing so would make ${VAR+x} always true and the command -v branch
# unreachable, leaving --probe inert in production while every fixture test
# still passes.
openspec_bin() {
  if [[ ${WTD_OPENSPEC_BIN+x} ]]; then
    [[ -n "$WTD_OPENSPEC_BIN" && -x "$WTD_OPENSPEC_BIN" ]] || return 1
    printf '%s' "$WTD_OPENSPEC_BIN"
    return 0
  fi
  command -v openspec 2>/dev/null
}

timeout_bin() {
  if [[ ${WTD_TIMEOUT_BIN+x} ]]; then
    [[ -n "$WTD_TIMEOUT_BIN" && -x "$WTD_TIMEOUT_BIN" ]] || return 1
    printf '%s' "$WTD_TIMEOUT_BIN"
    return 0
  fi
  command -v timeout 2>/dev/null
}

# load_kv_file and validate_kv are ported from install.sh's readers of the
# same name, adapted to the doctor's one hard rule: it never calls `die` and
# must not acquire one. Every `die "$msg"` becomes
# `printf '%s\n' "$msg" >&2; return 1`, and the caller captures the message
# through its own scalar rather than a global. The doctor holds two files at
# once (catalog, receipt), so callers pass a distinct array trio for each.
#
# load_kv_file must be called DIRECTLY in the current shell -- never inside
# $( ), a pipeline, process substitution, or a grouped subshell. Its arrays
# are populated through namerefs and would die with a subshell, handing the
# caller an empty map and a zero status.
#
# kv_* nameref locals, exactly as in install.sh: a nameref whose own
# identifier equals the name the caller passed is a circular reference, so no
# caller may pass kv_values, kv_lines, kv_order or kv_errname.
load_kv_file() {
  local file=$1
  local -n kv_values=$2
  local -n kv_lines=$3
  local -n kv_order=$4
  local kv_errname=$5
  local line key value lineno=0

  printf -v "$kv_errname" '%s' ''

  if [[ ! -r "$file" ]]; then
    printf -v "$kv_errname" '%s' "cannot read $file"
    return 1
  fi

  # `|| [[ -n "$line" ]]` keeps a final line that has no trailing newline.
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$(( lineno + 1 ))
    line="${line%$'\r'}"
    if [[ -z "${line//[[:space:]]/}" || "${line#"${line%%[![:space:]]*}"}" == '#'* ]]; then
      continue
    fi
    if [[ "$line" != *=* ]]; then
      printf -v "$kv_errname" '%s' "$file:$lineno: missing '=' separator"
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ ! "$key" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
      printf -v "$kv_errname" '%s' "$file:$lineno: malformed key: $key"
      return 1
    fi
    if [[ -n "${kv_values[$key]+set}" ]]; then
      printf -v "$kv_errname" '%s' \
        "$file:$lineno: duplicate key: $key (first seen at line ${kv_lines[$key]})"
      return 1
    fi
    kv_values["$key"]="$value"
    kv_lines["$key"]="$lineno"
    kv_order+=("$key")
  done < "$file"
}

# validate_kv mutates nothing the caller can see -- its outputs are its exit
# status and its message -- so, unlike load_kv_file, it MAY be captured:
# `if ! problem="$(validate_kv … 2>&1)"; then`.
#
# v_* nameref locals: no caller may pass v_values, v_lines, v_order,
# v_required, v_listkeys or v_members.
validate_kv() {
  local file=$1
  local -n v_values=$2 v_lines=$3 v_order=$4
  local -n v_required=$5 v_listkeys=$6 v_members=$7
  local key value element
  local -a elements
  local -A seen

  # Phase 1: required keys, in the caller's declared order. A key that is
  # absent has no source line, so none is printed.
  for key in "${v_required[@]}"; do
    if [[ -z "${v_values[$key]+set}" ]]; then
      printf '%s\n' "$file: missing required key: $key" >&2
      return 1
    fi
  done

  # Phase 2: per-key syntax, walked in SOURCE order so the first problem
  # reported is the first problem in the file.
  for key in "${v_order[@]}"; do
    value="${v_values[$key]}"

    if [[ -n "${v_listkeys[$key]+set}" ]]; then
      if [[ -z "$value" ]]; then
        continue                                   # an empty list is valid
      fi
      if [[ ! "$value" =~ ^[a-z0-9][a-z0-9.-]*(,[a-z0-9][a-z0-9.-]*)*$ ]]; then
        printf '%s\n' "$file:${v_lines[$key]}: malformed list for key: $key" >&2
        return 1
      fi
      IFS=, read -ra elements <<<"$value"
      seen=()
      for element in "${elements[@]}"; do
        if [[ -n "${seen[$element]+set}" ]]; then
          printf '%s\n' "$file:${v_lines[$key]}: duplicate element in $key: $element" >&2
          return 1
        fi
        seen["$element"]=1
        if (( ${#v_members[@]} > 0 )) && [[ -z "${v_members[$element]+set}" ]]; then
          printf '%s\n' "$file:${v_lines[$key]}: unknown catalog key in $key: $element" >&2
          return 1
        fi
      done
      continue
    fi

    if [[ -z "$value" ]]; then
      printf '%s\n' "$file:${v_lines[$key]}: empty value for key: $key" >&2
      return 1
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$ ]]; then
      printf '%s\n' "$file:${v_lines[$key]}: malformed value for key: $key" >&2
      return 1
    fi
  done

  return 0
}

mise_is_activated() {
  if [[ ${WTD_MISE_ACTIVATED+x} && -n "${WTD_MISE_ACTIVATED:-}" ]]; then
    [[ "$WTD_MISE_ACTIVATED" == "1" || "$(lower "$WTD_MISE_ACTIVATED")" == "true" ]]
    return
  fi
  [[ -n "${MISE_SHELL:-}" || -n "${MISE_SESSION:-}" ]]
}

primary_binary_for_mise_tool() {
  case "$1" in
    java) printf 'java' ;;
    maven) printf 'mvn' ;;
    python) printf 'python' ;;
    uv) printf 'uv' ;;
    dotnet) printf 'dotnet' ;;
    *) return 1 ;;
  esac
}

first_command_candidate() {
  local name=$1 candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    printf '%s' "$candidate"
    return 0
  done < <(enumerate_command_candidates "$name")
  return 1
}

audit_mise() {
  local mise canonical format output line tool primary selected selected_canonical selected_format current current_canonical seen_tools
  if ! mise="$(mise_bin)"; then
    add_finding INFO MISE_NOT_AVAILABLE "mise" "mise is not available; the doctor does not substitute a static required-tool matrix."
    return 0
  fi

  canonical="$(readlink -f -- "$mise" 2>/dev/null || printf '%s' "$mise")"
  format="$(binary_format "$canonical")"
  if [[ "$format" == "PE" ]] || is_windows_backed_path "$canonical"; then
    add_finding FAIL MISE_WINDOWS_BACKED "$mise" "mise itself is Windows-backed or PE; its toolchain answers are not trusted. target=$canonical format=$format"
    return 0
  fi
  add_finding INFO MISE_LINUX "$mise" "mise is Linux-backed and can be used as toolchain source of truth. target=$canonical format=$format"

  if ! output="$("$mise" ls --current --no-header 2>/dev/null)"; then
    add_finding WARN MISE_QUERY_FAILED "$mise" "Could not query current mise context with 'mise ls --current --no-header'."
    return 0
  fi

  seen_tools=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$(trim "$line")" ]] || continue
    tool="${line%%[[:space:]]*}"
    tool="${tool%%@*}"

    # mise emits one row per installed version, so a tool pinned to several
    # versions -- java = ["temurin-17", "temurin-21"] -- appears more than
    # once. Every question below is about the binding the tool resolves to,
    # which has one answer per tool rather than one per version, so a second
    # row would repeat all three findings verbatim and query mise again for
    # the same answer.
    [[ "$seen_tools" != *"|$tool|"* ]] || continue
    seen_tools+="|$tool|"

    primary="$(primary_binary_for_mise_tool "$tool" 2>/dev/null || true)"
    [[ -n "$primary" ]] || continue
    add_finding INFO MISE_TOOL_CONFIGURED "$tool" "mise configures watched tool '$tool' in the current context; primary binary=$primary."

    if ! selected="$("$mise" which "$primary" 2>/dev/null)" || [[ -z "$selected" ]]; then
      add_finding FAIL MISE_TOOL_UNRESOLVED "$tool" "mise configures '$tool' but cannot resolve primary binary '$primary'."
      continue
    fi
    selected_canonical="$(readlink -f -- "$selected" 2>/dev/null || printf '%s' "$selected")"
    selected_format="$(binary_format "$selected_canonical")"
    if [[ "$selected_format" == "PE" ]] || is_windows_backed_path "$selected_canonical"; then
      add_finding FAIL MISE_TOOL_WINDOWS_BACKED "$tool" "mise selected a Windows-backed/PE target for $primary: $selected_canonical format=$selected_format"
      continue
    fi
    add_finding INFO MISE_TOOL_LINUX "$tool" "mise selected Linux target for $primary: $selected_canonical format=$selected_format"

    if ! current="$(first_command_candidate "$primary")"; then
      add_finding INFO MISE_TOOL_NOT_EXPOSED "$tool" "mise resolves $primary but this shell does not expose it in PATH; this is valid for mise exec/non-activated shells. target=$selected_canonical"
      continue
    fi
    current_canonical="$(readlink -f -- "$current" 2>/dev/null || printf '%s' "$current")"
    if [[ "$current_canonical" == "$selected_canonical" ]]; then
      add_finding INFO MISE_BINDING_OK "$tool" "Current PATH and mise resolve the same $primary target: $selected_canonical"
      continue
    fi
    if [[ "$(binary_format "$current_canonical")" == "PE" ]] || is_windows_backed_path "$current_canonical"; then
      add_finding FAIL MISE_TOOL_SHADOWED_WINDOWS "$tool" "Current PATH shadows mise-selected $primary with Windows-backed tooling: current=$current_canonical mise=$selected_canonical"
    elif mise_is_activated; then
      add_finding FAIL MISE_TOOL_SHADOWED "$tool" "mise activation is present but another Linux $primary shadows the selected target: current=$current_canonical mise=$selected_canonical"
    else
      add_finding INFO MISE_TOOL_NOT_ACTIVATED "$tool" "Another Linux $primary is visible while mise activation is not detected; use mise exec or activate mise when this context should own the binding. current=$current_canonical mise=$selected_canonical"
    fi
  done <<< "$output"
}

# --- Task 7: the TOOLKIT_ finding domain -----------------------------------
#
# Three comparisons over an optional install receipt:
#   A -- receipt requested.* vs the toolkit-managed global mise config file.
#   B -- receipt installed.* vs a fresh probe, opt-in via --probe.
#   C -- the current catalog vs receipt requested.*, over their intersection.
# See docs/superpowers/specs/2026-09-09-software-catalog-design.md, "Doctor:
# three comparisons", for the normative rules; the comments here cover only
# the control flow.

# load_catalog resets CATALOG_VALUES/CATALOG_LINES/CATALOG_ORDER and loads
# WTD_CATALOG_FILE through load_kv_file, called directly (never inside a
# subshell) so its nameref-populated arrays survive, then runs the loaded
# catalog through validate_kv against CATALOG_REQUIRED -- the same
# seventeen-key contract install.sh enforces -- with an empty list-keys map
# and an empty members map, since the catalog itself has no list-valued keys
# and no membership set of its own. On either failure it clears the three
# arrays back to empty rather than leaving a partial load in place:
# validate_kv's own membership check (used by load_receipt) treats a
# non-empty MEMBERS array as "a catalog is available", so a half-loaded or
# incomplete catalog must not linger as one.
load_catalog() {
  CATALOG_VALUES=()
  # shellcheck disable=SC2034 # populated by name through load_kv_file's nameref
  CATALOG_LINES=()
  CATALOG_ORDER=()
  CATALOG_ERROR=""
  if ! load_kv_file "$WTD_CATALOG_FILE" CATALOG_VALUES CATALOG_LINES CATALOG_ORDER CATALOG_ERROR; then
    CATALOG_VALUES=()
    # shellcheck disable=SC2034 # populated by name through load_kv_file's nameref
    CATALOG_LINES=()
    CATALOG_ORDER=()
    return 1
  fi

  # shellcheck disable=SC2034 # read by validate_kv through its nameref
  local -A no_lists=()
  # shellcheck disable=SC2034 # read by validate_kv through its nameref
  local -A no_members=()
  local problem
  if ! problem="$(validate_kv "$WTD_CATALOG_FILE" CATALOG_VALUES CATALOG_LINES CATALOG_ORDER CATALOG_REQUIRED no_lists no_members 2>&1)"; then
    CATALOG_ERROR="$problem"
    CATALOG_VALUES=()
    # shellcheck disable=SC2034 # populated by name through load_kv_file's nameref
    CATALOG_LINES=()
    CATALOG_ORDER=()
    return 1
  fi
  return 0
}

# load_receipt loads WTD_RECEIPT_FILE and validates it in the two ordered
# phases the design declares. Phase 1 is one call to validate_kv with the six
# literal required keys, in declared order, which also runs validate_kv's own
# per-key syntax pass over every value in the file; passing CATALOG_VALUES
# itself as the MEMBERS argument is what makes the skipped=/overridden=
# membership check (predicate 5) run only when load_catalog above actually
# populated it. Phase 2 is the four remaining structural predicates, which
# this function evaluates itself, in declared order, only after phase 1
# returns clean; predicates 2 and 4 need a catalog and are skipped without
# one, exactly like validate_kv's own membership check.
#
# Takes the caller's catalog_available flag rather than re-deriving it from
# CATALOG_VALUES' size, so the gate cannot be silently disabled by a future
# caller capturing this differently.
load_receipt() {
  local catalog_available=$1
  RECEIPT_VALUES=()
  # shellcheck disable=SC2034 # populated by name through load_kv_file's nameref
  RECEIPT_LINES=()
  RECEIPT_ORDER=()
  RECEIPT_ERROR=""
  RECEIPT_UNKNOWN_KEYS=()

  if ! load_kv_file "$WTD_RECEIPT_FILE" RECEIPT_VALUES RECEIPT_LINES RECEIPT_ORDER RECEIPT_ERROR; then
    return 1
  fi

  # shellcheck disable=SC2034 # read by validate_kv through its nameref
  local -a required=(script-version installed-at source-commit catalog-sha256 skipped overridden)
  # shellcheck disable=SC2034 # read by validate_kv through its nameref
  local -A listkeys=([skipped]=1 [overridden]=1)
  local problem
  if ! problem="$(validate_kv "$WTD_RECEIPT_FILE" RECEIPT_VALUES RECEIPT_LINES RECEIPT_ORDER required listkeys CATALOG_VALUES 2>&1)"; then
    RECEIPT_ERROR="$problem"
    return 1
  fi

  local key suffix found_requested=0
  for key in "${RECEIPT_ORDER[@]}"; do
    if [[ "$key" == requested.* ]]; then
      found_requested=1
      break
    fi
  done
  if (( found_requested == 0 )); then
    RECEIPT_ERROR="$WTD_RECEIPT_FILE: no requested.* key is present"
    return 1
  fi

  if (( catalog_available == 1 )); then
    for key in "${RECEIPT_ORDER[@]}"; do
      [[ "$key" == requested.* ]] || continue
      suffix="${key#requested.}"
      if [[ -z "${CATALOG_VALUES[$suffix]+set}" ]]; then
        RECEIPT_UNKNOWN_KEYS+=("$key")
      fi
    done
  fi

  if [[ -n "${RECEIPT_VALUES[requested.karpathy-sha256]+set}" ]]; then
    RECEIPT_ERROR="$WTD_RECEIPT_FILE: requested.karpathy-sha256 must not be present"
    return 1
  fi

  if (( catalog_available == 1 )); then
    for key in "${RECEIPT_ORDER[@]}"; do
      [[ "$key" == installed.* ]] || continue
      suffix="${key#installed.}"
      if [[ -z "${CATALOG_VALUES[$suffix]+set}" ]]; then
        RECEIPT_UNKNOWN_KEYS+=("$key")
      fi
    done
  fi

  return 0
}

# toolkit_receipt_set KEY OUTVAR
# Expands RECEIPT_VALUES[KEY] -- skipped= or overridden=, always a
# comma-joined list of catalog keys, possibly empty -- into OUTVAR as a
# membership set. OUTVAR is a nameref: never call this inside a subshell.
toolkit_receipt_set() {
  local key=$1
  local -n out=$2
  out=()
  local value="${RECEIPT_VALUES[$key]:-}"
  [[ -n "$value" ]] || return 0
  local -a items
  local item
  IFS=',' read -ra items <<< "$value"
  for item in "${items[@]}"; do
    # shellcheck disable=SC2034 # out is the caller's nameref, read after return
    out["$item"]=1
  done
}

# parse_mise_toolchain_config reads WTD_MISE_TOOLCHAIN_CONFIG's [tools] table
# directly -- never "mise ls --current", whose answer depends on the working
# directory and would silently compare a project's own mise.toml instead of
# the toolkit's global one. This is new parsing: audit_mise strips versions,
# dedups per tool, and has no node/bun watchlist entry, so none of it is
# reusable here. Recognizes exactly the four line forms
# render_mise_configuration emits; anything else is ignored rather than
# rejected, so a hand-edited comment or the "[tools]" header itself does not
# abort the parse.
#
# Array position carries the mapping for java/dotnet: mise treats the first
# element as the default, so element 1 is always the "-17"/"-10" key and
# element 2 is always the "-21"/"-8" key, regardless of the values found --
# a parser that matched by value instead of position would silently accept a
# reordered file, which is exactly the change comparison A must report.
parse_mise_toolchain_config() {
  MISE_CONFIG_VALUES=()
  [[ -r "$WTD_MISE_TOOLCHAIN_CONFIG" ]] || return 1

  local line stripped key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="$(trim "$line")"
    [[ -n "$stripped" ]] || continue
    [[ "$stripped" == \#* ]] && continue

    if [[ "$stripped" =~ ^java[[:space:]]*=[[:space:]]*\[[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*\]$ ]]; then
      MISE_CONFIG_VALUES[java-17]="${BASH_REMATCH[1]}"
      MISE_CONFIG_VALUES[java-21]="${BASH_REMATCH[2]}"
      continue
    fi
    if [[ "$stripped" =~ ^dotnet[[:space:]]*=[[:space:]]*\[[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*\]$ ]]; then
      MISE_CONFIG_VALUES[dotnet-10]="${BASH_REMATCH[1]}"
      MISE_CONFIG_VALUES[dotnet-8]="${BASH_REMATCH[2]}"
      continue
    fi
    if [[ "$stripped" =~ ^\"dotnet:dotnet-ef\"[[:space:]]*=[[:space:]]*\"([^\"]*)\"$ ]]; then
      MISE_CONFIG_VALUES[dotnet-ef]="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$stripped" =~ ^([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*=[[:space:]]*\"([^\"]*)\"$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      case "$key" in
        python|node|bun|maven|uv|shellcheck|gitleaks)
          MISE_CONFIG_VALUES[$key]="$value"
          ;;
      esac
      continue
    fi
  done < "$WTD_MISE_TOOLCHAIN_CONFIG"

  return 0
}

# toolkit_compare_a -- requested-configuration drift, every audit.
toolkit_compare_a() {
  if ! parse_mise_toolchain_config; then
    add_finding INFO TOOLKIT_CONFIG_UNAVAILABLE "$WTD_MISE_TOOLCHAIN_CONFIG" "The toolkit-managed mise configuration is absent or unreadable; requested-configuration drift was not checked."
    return 0
  fi

  local -A skip=()
  toolkit_receipt_set skipped skip

  local key requested config_value ok_count=0
  for key in "${TOOLKIT_MISE_DOMAIN[@]}"; do
    [[ -z "${skip[$key]+set}" ]] || continue
    requested="${RECEIPT_VALUES[requested.$key]:-}"
    [[ -n "$requested" ]] || continue

    if [[ -n "${MISE_CONFIG_VALUES[$key]+set}" ]]; then
      config_value="${MISE_CONFIG_VALUES[$key]}"
      if [[ "$config_value" == "$requested" ]]; then
        ok_count=$((ok_count + 1))
      else
        add_finding WARN TOOLKIT_CONFIG_DRIFT "$key" "Requested $requested but the mise configuration has $config_value."
      fi
    else
      add_finding WARN TOOLKIT_CONFIG_MISSING "$key" "Requested $requested but $key is absent from the mise configuration."
    fi
  done

  if (( ok_count > 0 )); then
    add_finding INFO TOOLKIT_CONFIG_OK "mise" "$ok_count component(s) match the requested mise configuration."
  fi
}

# toolkit_run_probe TIMEOUT_BIN CMD...
# Runs CMD bounded by "TIMEOUT_BIN 10s", capturing combined output into
# TOOLKIT_PROBE_OUTPUT and returning the command's status. Callers guard the
# call in an `if`, exactly like run_bounded_probe's callers in install.sh, so
# an expected probe failure or timeout cannot trip errexit. 124 is coreutils
# timeout's own convention for "the bound was hit", which comparison B relies
# on to tell TOOLKIT_PROBE_TIMEOUT apart from TOOLKIT_PROBE_UNAVAILABLE.
toolkit_run_probe() {
  local timeout_bin_path=$1
  shift
  local rc
  if TOOLKIT_PROBE_OUTPUT="$("$timeout_bin_path" 10s "$@" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  return "$rc"
}

# toolkit_report_probe_rc KEY RC
# Common handling for a probe's exit status: reports TOOLKIT_PROBE_TIMEOUT or
# TOOLKIT_PROBE_UNAVAILABLE and returns 1, or returns 0 when RC is success and
# TOOLKIT_PROBE_OUTPUT is ready to extract from.
toolkit_report_probe_rc() {
  local key=$1 rc=$2
  if (( rc == 124 )); then
    add_finding INFO TOOLKIT_PROBE_TIMEOUT "$key" "Probing $key timed out."
    return 1
  fi
  if (( rc != 0 )); then
    add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "$key" "Could not probe $key."
    return 1
  fi
  return 0
}

# toolkit_compare_probe_result KEY CANDIDATE COUNT_VAR
# The common tail for every comparison-B probe once a candidate token has
# been extracted: validates it against the receipt's own scalar grammar,
# reports TOOLKIT_PROBE_UNAVAILABLE for an empty or malformed one, does
# nothing when the receipt has no installed.<KEY> to compare against
# (silently outside B), and otherwise reports agreement (via COUNT_VAR, a
# nameref) or TOOLKIT_DRIFT_INSTALLED.
toolkit_compare_probe_result() {
  local key=$1 candidate=$2
  local -n count_ref=$3
  if [[ -z "$candidate" || ! "$candidate" =~ ^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$ ]]; then
    add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "$key" "Probe output for $key could not be parsed into a version."
    return 0
  fi
  local installed="${RECEIPT_VALUES[installed.$key]:-}"
  [[ -n "$installed" ]] || return 0
  if [[ "$candidate" == "$installed" ]]; then
    count_ref=$((count_ref + 1))
  else
    add_finding WARN TOOLKIT_DRIFT_INSTALLED "$key" "Installed $installed but the machine now reports $candidate."
  fi
}

# toolkit_compare_b -- installed-machine drift, --probe only. Reaches exactly
# three executables, each resolved once through its seam at the point this
# comparison begins, and never again.
toolkit_compare_b() {
  local timeout_path mise_path="" openspec_path=""
  local -A skip=()
  toolkit_receipt_set skipped skip

  if ! timeout_path="$(timeout_bin)"; then
    add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "timeout" "No usable timeout utility is available; comparison B did not run."
    return 0
  fi

  local mise_available=1
  if ! mise_path="$(mise_bin)"; then
    mise_available=0
    add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "mise" "No usable mise binary is available; mise-backed probes did not run."
  fi

  local openspec_available=1
  if ! openspec_path="$(openspec_bin)"; then
    openspec_available=0
  fi

  local ok_count=0 rc candidate

  if (( mise_available == 1 )); then
    if [[ -z "${skip[java-17]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec "java@${RECEIPT_VALUES[requested.java-17]:-}" -- java -version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc java-17 "$rc"; then
        candidate="$(awk -F'"' 'NF>=3{print $2; exit}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result java-17 "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[java-21]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec "java@${RECEIPT_VALUES[requested.java-21]:-}" -- java -version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc java-21 "$rc"; then
        candidate="$(awk -F'"' 'NF>=3{print $2; exit}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result java-21 "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[dotnet-10]+set}" || -z "${skip[dotnet-8]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- dotnet --list-sdks; then rc=0; else rc=$?; fi
      if (( rc == 124 )); then
        [[ -n "${skip[dotnet-10]+set}" ]] || add_finding INFO TOOLKIT_PROBE_TIMEOUT "dotnet-10" "Probing dotnet-10 timed out."
        [[ -n "${skip[dotnet-8]+set}" ]]  || add_finding INFO TOOLKIT_PROBE_TIMEOUT "dotnet-8" "Probing dotnet-8 timed out."
      elif (( rc != 0 )); then
        [[ -n "${skip[dotnet-10]+set}" ]] || add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "dotnet-10" "Could not probe dotnet-10."
        [[ -n "${skip[dotnet-8]+set}" ]]  || add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "dotnet-8" "Could not probe dotnet-8."
      else
        if [[ -z "${skip[dotnet-10]+set}" ]]; then
          candidate="$(awk '{ split($1, v, "."); if (v[1] == "10") { print $1; exit } }' <<<"$TOOLKIT_PROBE_OUTPUT")"
          toolkit_compare_probe_result dotnet-10 "$candidate" ok_count
        fi
        if [[ -z "${skip[dotnet-8]+set}" ]]; then
          candidate="$(awk '{ split($1, v, "."); if (v[1] == "8") { print $1; exit } }' <<<"$TOOLKIT_PROBE_OUTPUT")"
          toolkit_compare_probe_result dotnet-8 "$candidate" ok_count
        fi
      fi
    fi

    if [[ -z "${skip[python]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- python --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc python "$rc"; then
        candidate="$(awk 'NR==1{print $2}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result python "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[node]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- node --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc node "$rc"; then
        candidate="$(awk 'NR==1{ sub(/^v/, "", $1); print $1 }' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result node "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[bun]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- bun --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc bun "$rc"; then
        candidate="$(awk 'NR==1{print $1}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result bun "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[maven]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- mvn -version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc maven "$rc"; then
        candidate="$(awk 'NR==1{print $3}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result maven "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[dotnet-ef]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- dotnet-ef --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc dotnet-ef "$rc"; then
        candidate="$(awk 'NF{last=$1} END{print last}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result dotnet-ef "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[uv]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- uv --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc uv "$rc"; then
        candidate="$(awk 'NR==1{print $2}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result uv "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[shellcheck]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- shellcheck --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc shellcheck "$rc"; then
        candidate="$(awk '$1=="version:"{print $2; exit}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result shellcheck "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[gitleaks]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- gitleaks version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc gitleaks "$rc"; then
        candidate="$(awk 'NR==1{ sub(/^v/, "", $1); print $1 }' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result gitleaks "$candidate" ok_count
      fi
    fi

    if [[ -z "${skip[pyyaml]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$mise_path" exec -- python -c 'import yaml; print(yaml.__version__)'; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc pyyaml "$rc"; then
        candidate="$(awk 'NR==1{print $1}' <<<"$TOOLKIT_PROBE_OUTPUT")"
        toolkit_compare_probe_result pyyaml "$candidate" ok_count
      fi
    fi
  fi

  if (( openspec_available == 1 )); then
    if [[ -z "${skip[openspec]+set}" ]]; then
      if toolkit_run_probe "$timeout_path" "$openspec_path" --version; then rc=0; else rc=$?; fi
      if toolkit_report_probe_rc openspec "$rc"; then
        candidate="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' <<<"$TOOLKIT_PROBE_OUTPUT" | head -n1 || true)"
        toolkit_compare_probe_result openspec "$candidate" ok_count
      fi
    fi
  else
    add_finding INFO TOOLKIT_PROBE_UNAVAILABLE "openspec" "No usable openspec binary is available; installed.openspec was not measured."
  fi

  if (( ok_count > 0 )); then
    add_finding INFO TOOLKIT_INSTALLED_OK "installed" "$ok_count component(s) match a fresh probe."
  fi
}

# toolkit_compare_c -- catalog staleness, every audit with a catalog
# available. Iterates the intersection of the current catalog's keys and the
# receipt's requested.* keys: walking CATALOG_ORDER and skipping any key the
# receipt does not carry as requested.* is what keeps both directions of
# forward-compatibility -- a catalog key the receipt predates, and a
# requested.* key the catalog has since dropped -- outside C by construction.
toolkit_compare_c() {
  local -A skip=() overridden=()
  toolkit_receipt_set skipped skip
  toolkit_receipt_set overridden overridden

  local key requested catalog_value ok_count=0
  local -a not_comparable=()

  for key in "${CATALOG_ORDER[@]}"; do
    [[ "$key" != "karpathy-sha256" ]] || continue
    [[ -n "${RECEIPT_VALUES[requested.$key]+set}" ]] || continue
    requested="${RECEIPT_VALUES[requested.$key]}"
    catalog_value="${CATALOG_VALUES[$key]}"

    if [[ -n "${skip[$key]+set}" ]]; then
      not_comparable+=("$key (skipped)")
    elif [[ -n "${overridden[$key]+set}" ]]; then
      not_comparable+=("$key (overridden)")
    elif [[ "$requested" == "latest" || "$catalog_value" == "latest" ]]; then
      not_comparable+=("$key (latest)")
    elif [[ "$catalog_value" == "$requested" ]]; then
      ok_count=$((ok_count + 1))
    else
      add_finding WARN TOOLKIT_STALE_PIN "$key" "Requested $requested but the catalog now pins $catalog_value."
    fi
  done

  if (( ok_count > 0 )); then
    add_finding INFO TOOLKIT_PINS_CURRENT "catalog" "$ok_count component(s) match the current catalog."
  fi
  if (( ${#not_comparable[@]} > 0 )); then
    local joined
    joined="$(IFS=', '; printf '%s' "${not_comparable[*]}")"
    add_finding INFO TOOLKIT_NOT_COMPARABLE "catalog" "Not compared: $joined."
  fi
}

# audit_toolkit orchestrates the three comparisons under the design's
# preconditions. No TOOLKIT_* finding is ever FAIL and none of this sets
# EXEC_ERROR: a machine this toolkit never provisioned, or a receipt this
# doctor cannot read, must never stop the rest of the audit from running.
audit_toolkit() {
  local catalog_available=1
  if ! load_catalog; then
    catalog_available=0
    add_finding INFO TOOLKIT_CATALOG_UNAVAILABLE "$WTD_CATALOG_FILE" "The software catalog is absent or unreadable; catalog staleness was not checked. $CATALOG_ERROR"
  fi

  if [[ ! -e "$WTD_RECEIPT_FILE" ]]; then
    add_finding INFO TOOLKIT_NOT_PROVISIONED "$WTD_RECEIPT_FILE" "No install receipt found; this machine was not provisioned by install.sh, or was provisioned before receipts existed."
    return 0
  fi

  if ! load_receipt "$catalog_available"; then
    add_finding INFO TOOLKIT_RECEIPT_UNREADABLE "$WTD_RECEIPT_FILE" "$RECEIPT_ERROR"
    return 0
  fi

  local unknown_key
  for unknown_key in ${RECEIPT_UNKNOWN_KEYS[@]+"${RECEIPT_UNKNOWN_KEYS[@]}"}; do
    add_finding INFO TOOLKIT_RECEIPT_UNKNOWN_KEY "$unknown_key" "This receipt names a component the catalog no longer pins; it is excluded from staleness checking. Either the pin was retired, or this receipt was edited by hand."
  done

  if (( PROBE_MODE == 0 )); then
    add_finding INFO TOOLKIT_INSTALLED_NOT_PROBED "$WTD_RECEIPT_FILE" "Run 'audit --probe' to compare installed versions against a fresh probe."
  fi

  toolkit_compare_a

  if (( PROBE_MODE == 1 )); then
    toolkit_compare_b
  fi

  if (( catalog_available == 1 )); then
    toolkit_compare_c
  fi
}

explain_command() {
  local name=$1 candidate found=0
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    found=1
    classify_tool_candidate "$name" "$candidate"
  done < <(enumerate_command_candidates "$name")
  if (( found == 0 )); then
    add_finding WARN TOOL_NOT_FOUND "$name" "No executable candidate for $name exists in the scanned PATH."
  fi
}


profile_files() {
  local file
  if [[ ${WTD_PROFILE_FILES+x} ]]; then
    [[ -n "$WTD_PROFILE_FILES" ]] || return 0
    local -a configured=()
    IFS=':' read -r -a configured <<< "$WTD_PROFILE_FILES"
    for file in "${configured[@]}"; do
      [[ -n "$file" ]] && printf '%s\n' "$file"
    done
    return 0
  fi

  for file in \
    "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.bashrc" \
    "$HOME/.zprofile" "$HOME/.zshrc" \
    /etc/environment /etc/profile /etc/bash.bashrc; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done
  for file in /etc/profile.d/*.sh "$HOME"/.config/environment.d/*.conf; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done
}

windows_mount_points() {
  local source mountpoint fstype options rest
  while IFS=' ' read -r source mountpoint fstype options rest; do
    [[ -n "${mountpoint:-}" ]] || continue
    if mount_is_windows_backed "$fstype" "$options" "$source"; then
      decode_mount_field "$mountpoint"
      printf '\n'
    fi
  done < "$MOUNTS_FILE"
}

line_references_windows_mount() {
  local line=$1 mp
  while IFS= read -r mp; do
    [[ -n "$mp" ]] || continue
    [[ "$line" == *"$mp"* ]] && return 0
  done < <(windows_mount_points)
  return 1
}

audit_shell_profiles() {
  local file line stripped lower_line n segment lower_segment
  local has_rancher has_allowlisted has_generic
  local -a segments=()
  while IFS= read -r file; do
    [[ -n "$file" && -f "$file" && -r "$file" ]] || continue
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      stripped="$(trim "$line")"
      [[ -n "$stripped" ]] || continue
      [[ "$stripped" == \#* || "$stripped" == \;* ]] && continue
      lower_line="$(lower "$line")"
      [[ "$lower_line" == *"path"* ]] || continue

      has_rancher=0
      has_allowlisted=0
      has_generic=0
      segments=()
      IFS=':' read -r -a segments <<< "$line"
      for segment in "${segments[@]}"; do
        lower_segment="$(lower "$segment")"
        if [[ "$lower_segment" == *"/rancher desktop/resources/resources/linux/bin"* || "$lower_segment" == *"/rancher desktop/resources/resources/linux/docker-cli-plugins"* ]]; then
          has_rancher=1
          continue
        fi
        # A profile that re-adds an allowlisted launcher directory is the
        # documented way to keep the editor and container tooling working once
        # appendWindowsPath is off, so it must not be reported as a relapse.
        if is_allowlisted_windows_path "$lower_segment"; then
          has_allowlisted=1
          continue
        fi
        if line_references_windows_mount "$segment" || \
           [[ "$lower_segment" == *"windows/system32"* || "$lower_segment" == *"program files"* || "$lower_segment" == *"appdata/"* || \
              "$lower_segment" == *".exe"* || "$lower_segment" == *".cmd"* || "$lower_segment" == *".bat"* || \
              "$lower_segment" == *"powershell"* || "$lower_segment" == *"cmd.exe"* ]]; then
          has_generic=1
        fi
      done

      if (( has_rancher )); then
        add_finding INFO SHELL_PROFILE_RANCHER_PATH_ALLOWED "$file:$n" "Profile adds the narrow Rancher Desktop Linux-bin PATH exception."
      fi
      if (( has_allowlisted )); then
        add_finding INFO SHELL_PROFILE_ALLOWLISTED_PATH "$file:$n" "Profile adds an allowlisted Windows-backed launcher directory."
      fi
      if (( has_generic )); then
        add_finding FAIL SHELL_PROFILE_WINDOWS_PATH "$file:$n" "Shell startup line may reintroduce Windows tooling into PATH; remediation is manual."
      fi
    done < "$file"
  done < <(profile_files)
}


# The single quotes below are deliberate: these functions compare against the
# literal text '$PATH' and '$HOME' as written in a profile file. Expanding
# them is precisely the bug being avoided.
# shellcheck disable=SC2016
path_assignment_parts() {
  local line=$1 stripped rhs export_kw=""
  stripped="$(trim "$line")"
  [[ -n "$stripped" && "$stripped" != \#* && "$stripped" != \;* ]] || return 1
  if [[ "$stripped" =~ ^(export[[:space:]]+)?PATH[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    [[ -n "${BASH_REMATCH[1]}" ]] && export_kw="export "
    rhs="${BASH_REMATCH[2]}"
    printf '%s\037%s' "$export_kw" "$rhs"
    return 0
  fi
  return 1
}

# shellcheck disable=SC2016
path_rhs_safe() {
  local rhs=$1 body=$1 scrub
  [[ "$rhs" != *'$('* && "$rhs" != *'`'* && "$rhs" != *'#'* ]] || return 1
  [[ "$rhs" != *';'* && "$rhs" != *'&&'* && "$rhs" != *'||'* && "$rhs" != *'<'* && "$rhs" != *'>'* ]] || return 1

  if [[ ${#body} -ge 2 ]]; then
    if [[ "${body:0:1}" == '"' && "${body: -1}" == '"' ]]; then
      body="${body:1:${#body}-2}"
    elif [[ "${body:0:1}" == "'" && "${body: -1}" == "'" ]]; then
      body="${body:1:${#body}-2}"
    fi
  fi
  scrub="$body"
  scrub="${scrub//\$PATH/}"
  scrub="${scrub//\$\{PATH\}/}"
  scrub="${scrub//\$HOME/}"
  scrub="${scrub//\$\{HOME\}/}"
  [[ "$scrub" != *'$'* ]] || return 1
  [[ ! "$scrub" =~ %[A-Za-z_][A-Za-z0-9_]*% ]] || return 1
  return 0
}

expand_path_source_segment() {
  local seg=$1
  # The tilde and variable patterns below are literal match targets, not
  # expansions: quoting them is deliberate, and expanding them is the bug this
  # function exists to avoid. Neither SC2088 nor SC2016 applies.
  # shellcheck disable=SC2088,SC2016
  case "$seg" in
    '$PATH'|'${PATH}') printf '%s' "$seg" ; return 0 ;;
    '~') printf '%s' "$HOME" ; return 0 ;;
    '~/'*) printf '%s/%s' "$HOME" "${seg#~/}" ; return 0 ;;
    '$HOME'|'${HOME}') printf '%s' "$HOME" ; return 0 ;;
    '$HOME/'*) printf '%s/%s' "$HOME" "${seg#\$HOME/}" ; return 0 ;;
    '${HOME}/'*) printf '%s/%s' "$HOME" "${seg#\$\{HOME\}/}" ; return 0 ;;
  esac
  printf '%s' "$seg"
}

# shellcheck disable=SC2016
rewrite_path_assignment_line() {
  local line=$1 parts export_kw rhs body seg expanded canonical key joined="" changed=0
  local -a segments=() kept=()
  local -A seen_text=() seen_canonical=()

  parts="$(path_assignment_parts "$line")" || return 3
  IFS=$'\037' read -r export_kw rhs <<< "$parts"
  path_rhs_safe "$rhs" || return 2

  body="$rhs"
  if [[ ${#body} -ge 2 && "${body:0:1}" == '"' && "${body: -1}" == '"' ]]; then
    body="${body:1:${#body}-2}"
  elif [[ ${#body} -ge 2 && "${body:0:1}" == "'" && "${body: -1}" == "'" ]]; then
    body="${body:1:${#body}-2}"
  elif [[ "$body" == *[[:space:]]* ]]; then
    return 2
  fi

  IFS=':' read -r -a segments <<< "$body"
  for seg in "${segments[@]}"; do
    if [[ -z "$seg" ]]; then changed=1; continue; fi
    if [[ ${seen_text[$seg]+x} ]]; then changed=1; continue; fi
    seen_text[$seg]=1

    if [[ "$seg" == '$PATH' || "$seg" == '${PATH}' ]]; then
      kept+=("$seg")
      continue
    fi

    expanded="$(expand_path_source_segment "$seg")"
    if [[ -e "$expanded" ]]; then
      canonical="$(readlink -f -- "$expanded" 2>/dev/null || printf '%s' "$expanded")"
      if [[ ! -d "$expanded" ]]; then changed=1; continue; fi
      if is_windows_backed_path "$canonical" && ! is_allowlisted_windows_path "$canonical"; then changed=1; continue; fi
      if [[ ${seen_canonical[$canonical]+x} ]]; then changed=1; continue; fi
      seen_canonical[$canonical]=1
    else
      if is_windows_backed_path "$expanded" && ! is_allowlisted_windows_path "$expanded"; then changed=1; continue; fi
      if (( DROP_MISSING )); then changed=1; continue; fi
    fi
    kept+=("$seg")
  done

  local first=1
  for seg in "${kept[@]}"; do
    if (( first )); then joined="$seg"; first=0; else joined+=":$seg"; fi
  done
  printf '%sPATH="%s"' "$export_kw" "$joined"
  (( changed )) && return 0
  return 1
}

render_fixed_profile() {
  local file=$1 output=$2 line replacement rc n=0 changed=0 unsafe=0
  : > "$output"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if path_assignment_parts "$line" >/dev/null; then
      if replacement="$(rewrite_path_assignment_line "$line")"; then
        rc=0
      else
        rc=$?
      fi
      case "$rc" in
        0) printf '%s\n' "$replacement" >> "$output"; changed=1 ;;
        1|3) printf '%s\n' "$line" >> "$output" ;;
        2) printf '%s\n' "$line" >> "$output"; add_finding FAIL PATH_AUTO_FIX_UNSAFE "$file:$n" "PATH assignment is dynamic or ambiguous and was not rewritten automatically."; unsafe=1 ;;
        *) printf '%s\n' "$line" >> "$output"; add_finding ERROR PATH_PROFILE_RENDER_FAILED "$file:$n" "Unexpected PATH rewrite result."; EXEC_ERROR=1; return 2 ;;
      esac
    else
      printf '%s\n' "$line" >> "$output"
    fi
  done < "$file"
  (( unsafe )) && return 4
  (( changed )) && return 0
  return 3
}

apply_path_fixes() {
  local file preview rc dir base candidate backup stamp mode changed_any=0 unsafe_any=0
  while IFS= read -r file; do
    [[ -n "$file" && -f "$file" && -r "$file" ]] || continue
    preview="$(mktemp)" || { add_finding ERROR PATH_FIX_TEMP_FAILED "$file" "Could not create preview file."; EXEC_ERROR=1; return 2; }
    if render_fixed_profile "$file" "$preview"; then
      rc=0
    else
      rc=$?
    fi
    if (( rc == 2 )); then rm -f -- "$preview"; return 2; fi
    if (( rc == 4 )); then unsafe_any=1; rm -f -- "$preview"; continue; fi
    if (( rc == 3 )) || cmp -s -- "$file" "$preview"; then rm -f -- "$preview"; continue; fi

    if (( DRY_RUN )); then
      add_finding INFO PATH_PROFILE_WOULD_CHANGE "$file" "Safe persistent PATH cleanup is available; dry-run left the file unchanged."
      rm -f -- "$preview"
      continue
    fi
    if [[ ! -w "$file" ]]; then
      add_finding ERROR PATH_PROFILE_NOT_WRITABLE "$file" "Profile requires a safe PATH change but is not writable; PATH remediation never escalates privileges."
      EXEC_ERROR=1
      rm -f -- "$preview"
      return 2
    fi

    dir="$(dirname -- "$file")"; base="$(basename -- "$file")"; stamp="$(date +%Y%m%d-%H%M%S).$$"
    backup="$dir/$base.bak.$stamp"
    if ! cp -p -- "$file" "$backup"; then
      add_finding ERROR PATH_PROFILE_BACKUP_FAILED "$file" "Could not create profile backup."; EXEC_ERROR=1; rm -f -- "$preview"; return 2
    fi
    candidate="$dir/.${base}.wtd.$$"
    mode="$(stat -c '%a' -- "$file")"
    if ! install -m "$mode" -- "$preview" "$candidate" || ! mv -f -- "$candidate" "$file"; then
      rm -f -- "$preview" "$candidate" 2>/dev/null || true
      add_finding ERROR PATH_PROFILE_WRITE_FAILED "$file" "Atomic PATH profile replacement failed."; EXEC_ERROR=1; return 2
    fi
    rm -f -- "$preview"
    add_finding INFO PATH_PROFILE_BACKUP_CREATED "$backup" "Backup created before persistent PATH remediation."
    add_finding INFO PATH_PROFILE_CHANGED "$file" "Safe persistent PATH entries were normalized; start a new login shell before validating the effective PATH."
    changed_any=1
  done < <(profile_files)

  (( changed_any )) && PATH_CHANGED=1
  (( unsafe_any )) && return 4
  return 0
}

wsl_conf_fix_state() {
  read_wsl_conf
  if (( INTEROP_SECTION_COUNT > 1 )); then
    add_finding ERROR WSL_CONF_DUPLICATE_INTEROP "$WSL_CONF" "Multiple [interop] sections make remediation ambiguous."
    EXEC_ERROR=1
    return 2
  fi
  if (( INTEROP_ENABLED_SEEN > 1 || APPEND_WINDOWS_PATH_SEEN > 1 )); then
    add_finding ERROR WSL_CONF_DUPLICATE_KEY "$WSL_CONF" "Duplicate [interop] keys make remediation ambiguous."
    EXEC_ERROR=1
    return 2
  fi

  local enabled="true" append="true"
  if (( INTEROP_ENABLED_SEEN == 1 )); then
    if ! enabled="$(parse_bool "$INTEROP_ENABLED_RAW")"; then
      add_finding ERROR WSL_CONF_INVALID_ENABLED "$WSL_CONF" "Invalid [interop] enabled value: $INTEROP_ENABLED_RAW"
      EXEC_ERROR=1
      return 2
    fi
  fi
  if (( APPEND_WINDOWS_PATH_SEEN == 1 )); then
    if ! append="$(parse_bool "$APPEND_WINDOWS_PATH_RAW")"; then
      add_finding ERROR WSL_CONF_INVALID_APPEND_WINDOWS_PATH "$WSL_CONF" "Invalid [interop] appendWindowsPath value: $APPEND_WINDOWS_PATH_RAW"
      EXEC_ERROR=1
      return 2
    fi
  fi

  if (( INTEROP_SECTION_COUNT == 1 && INTEROP_ENABLED_SEEN == 1 && APPEND_WINDOWS_PATH_SEEN == 1 )) && \
     [[ "$enabled" == "true" && "$append" == "false" ]]; then
    return 0
  fi
  return 1
}

render_fixed_wsl_conf() {
  local output=$1
  if [[ ! -f "$WSL_CONF" ]]; then
    printf '[interop]\nenabled=true\nappendWindowsPath=false\n' > "$output"
    return 0
  fi

  read_wsl_conf
  if (( INTEROP_SECTION_COUNT == 0 )); then
    cat -- "$WSL_CONF" > "$output"
    [[ ! -s "$WSL_CONF" ]] || printf '\n' >> "$output"
    printf '[interop]\nenabled=true\nappendWindowsPath=false\n' >> "$output"
    return 0
  fi

  local line stripped section="" in_interop=0 enabled_written=0 append_written=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="$(trim "$line")"
    if [[ "$stripped" =~ ^\[([^]]+)\]$ ]]; then
      if (( in_interop )); then
        (( enabled_written )) || printf 'enabled=true\n' >> "$output"
        (( append_written )) || printf 'appendWindowsPath=false\n' >> "$output"
      fi
      section="$(lower "$(trim "${BASH_REMATCH[1]}")")"
      [[ "$section" == "interop" ]] && in_interop=1 || in_interop=0
      printf '%s\n' "$line" >> "$output"
      continue
    fi

    if (( in_interop )) && [[ "$stripped" =~ ^([^=]+)=(.*)$ ]]; then
      local key
      key="$(lower "$(trim "${BASH_REMATCH[1]}")")"
      case "$key" in
        enabled)
          printf 'enabled=true\n' >> "$output"
          enabled_written=1
          continue
          ;;
        appendwindowspath)
          printf 'appendWindowsPath=false\n' >> "$output"
          append_written=1
          continue
          ;;
      esac
    fi
    printf '%s\n' "$line" >> "$output"
  done < "$WSL_CONF"

  if (( in_interop )); then
    (( enabled_written )) || printf 'enabled=true\n' >> "$output"
    (( append_written )) || printf 'appendWindowsPath=false\n' >> "$output"
  fi
}

run_privileged_for_dir() {
  local dir=$1
  shift
  if (( EUID == 0 )) || [[ -w "$dir" ]]; then
    "$@"
    return
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    add_finding ERROR SUDO_UNAVAILABLE "$dir" "Remediation requires elevated write access but sudo is unavailable."
    EXEC_ERROR=1
    return 1
  fi
  sudo "$@"
}

apply_wsl_conf_fix() {
  local state
  if wsl_conf_fix_state; then state=0; else state=$?; fi
  if (( state == 2 )); then
    return 2
  elif (( state == 0 )); then
    return 3
  fi
  if (( DRY_RUN )); then
    add_finding INFO WSL_CONF_WOULD_CHANGE "$WSL_CONF" "wsl.conf requires remediation; dry-run left it unchanged."
    return 4
  fi

  local tmp dir base candidate backup stamp mode uid gid
  tmp="$(mktemp)" || { add_finding ERROR FIX_TEMP_FAILED "$WSL_CONF" "Could not create temporary file."; EXEC_ERROR=1; return 2; }
  : > "$tmp"
  if ! render_fixed_wsl_conf "$tmp"; then
    rm -f -- "$tmp"
    add_finding ERROR WSL_CONF_RENDER_FAILED "$WSL_CONF" "Could not render remediated configuration."
    EXEC_ERROR=1
    return 2
  fi

  dir="$(dirname -- "$WSL_CONF")"
  base="$(basename -- "$WSL_CONF")"
  candidate="$dir/.${base}.wtd.$$"
  stamp="$(date +%Y%m%d-%H%M%S)"

  if [[ -f "$WSL_CONF" ]]; then
    backup="$WSL_CONF.bak.$stamp"
    if ! run_privileged_for_dir "$dir" cp -p -- "$WSL_CONF" "$backup"; then
      rm -f -- "$tmp"
      add_finding ERROR WSL_CONF_BACKUP_FAILED "$WSL_CONF" "Could not create backup before remediation."
      EXEC_ERROR=1
      return 2
    fi
    add_finding INFO WSL_CONF_BACKUP_CREATED "$backup" "Backup created before modifying wsl.conf."
    mode="$(stat -c '%a' -- "$WSL_CONF")"
    uid="$(stat -c '%u' -- "$WSL_CONF")"
    gid="$(stat -c '%g' -- "$WSL_CONF")"
  else
    mode=644
    uid=0
    gid=0
  fi

  if (( EUID == 0 )) || [[ -w "$dir" ]]; then
    if ! install -m "$mode" -- "$tmp" "$candidate" || ! mv -f -- "$candidate" "$WSL_CONF"; then
      rm -f -- "$tmp" "$candidate" 2>/dev/null || true
      add_finding ERROR WSL_CONF_WRITE_FAILED "$WSL_CONF" "Atomic replacement failed."
      EXEC_ERROR=1
      return 2
    fi
  else
    if ! run_privileged_for_dir "$dir" install -m "$mode" -o "$uid" -g "$gid" -- "$tmp" "$candidate" || \
       ! run_privileged_for_dir "$dir" mv -f -- "$candidate" "$WSL_CONF"; then
      run_privileged_for_dir "$dir" rm -f -- "$candidate" >/dev/null 2>&1 || true
      rm -f -- "$tmp"
      add_finding ERROR WSL_CONF_WRITE_FAILED "$WSL_CONF" "Atomic replacement failed."
      EXEC_ERROR=1
      return 2
    fi
  fi
  rm -f -- "$tmp"
  add_finding INFO WSL_CONF_FIXED "$WSL_CONF" "Set interop.enabled=true and interop.appendWindowsPath=false."
  return 0
}

finding_counts() {
  local fail=0 warn=0 error=0 i
  for ((i=0; i<${#F_SEVERITY[@]}; i++)); do
    case "${F_SEVERITY[$i]}" in
      FAIL) fail=$((fail + 1)) ;;
      WARN) warn=$((warn + 1)) ;;
      ERROR) error=$((error + 1)) ;;
    esac
  done
  printf '%s %s %s' "$fail" "$warn" "$error"
}

status_for_findings() {
  (( EXEC_ERROR != 0 )) && { printf 'ERROR'; return; }
  local counts fail warn rest
  counts="$(finding_counts)"
  fail=${counts%% *}
  rest=${counts#* }
  warn=${rest%% *}
  if (( fail > 0 )); then
    printf 'FAIL'
  elif (( warn > 0 )); then
    printf 'WARN'
  else
    printf 'PASS'
  fi
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

render_human() {
  local i
  for ((i=0; i<${#F_SEVERITY[@]}; i++)); do
    printf '%-5s %-40s %s -- %s\n' "${F_SEVERITY[$i]}" "${F_CODE[$i]}" "${F_SUBJECT[$i]}" "${F_MESSAGE[$i]}"
  done
}

render_json() {
  local status=$1 i comma=""
  printf '{"schemaVersion":%d,"toolVersion":"%s","action":"%s","status":"%s","findings":[' \
    "$SCHEMA_VERSION" "$(json_escape "$SCRIPT_VERSION")" "$(json_escape "$CURRENT_ACTION")" "$(json_escape "$status")"
  for ((i=0; i<${#F_SEVERITY[@]}; i++)); do
    printf '%s{"severity":"%s","code":"%s","subject":"%s","message":"%s"}' \
      "$comma" \
      "$(json_escape "${F_SEVERITY[$i]}")" \
      "$(json_escape "${F_CODE[$i]}")" \
      "$(json_escape "${F_SUBJECT[$i]}")" \
      "$(json_escape "${F_MESSAGE[$i]}")"
    comma=','
  done
  printf ']}\n'
}

render_output() {
  local status=${1:-}
  [[ -n "$status" ]] || status="$(status_for_findings)"
  if (( JSON_MODE )); then
    render_json "$status"
  else
    render_human
  fi
}

result_exit_code() {
  (( EXEC_ERROR != 0 )) && return 2
  local counts fail
  counts="$(finding_counts)"
  fail=${counts%% *}
  (( fail > 0 )) && return 1
  return 0
}

run_audit() {
  audit_wsl_environment
  if (( EXEC_ERROR == 0 )); then
    audit_wsl_conf
    (( EXEC_ERROR == 0 )) && audit_path_entries
    (( EXEC_ERROR == 0 )) && audit_toolchains
    (( EXEC_ERROR == 0 )) && audit_container_reachability
    (( EXEC_ERROR == 0 )) && audit_mise
    (( EXEC_ERROR == 0 )) && audit_shell_profiles
    (( EXEC_ERROR == 0 )) && audit_toolkit
  fi
  render_output
  result_exit_code
}

run_fix() {
  if ! is_wsl; then
    add_finding ERROR NOT_WSL "environment" "This command is intended to run inside WSL."
    EXEC_ERROR=1
    render_output ERROR
    return 2
  fi
  add_finding INFO WSL_DETECTED "environment" "WSL environment detected."

  local rc counts fail
  if [[ "$FIX_SCOPE" == "wsl" || "$FIX_SCOPE" == "all" ]]; then
    if apply_wsl_conf_fix; then rc=0; else rc=$?; fi
    if (( rc == 2 )); then render_output ERROR; return 2; fi
    (( rc == 0 )) && WSL_CHANGED=1
  fi

  if [[ "$FIX_SCOPE" == "path" || "$FIX_SCOPE" == "all" ]]; then
    if apply_path_fixes; then rc=0; else rc=$?; fi
    if (( rc == 2 )); then render_output ERROR; return 2; fi
  fi

  if (( WSL_CHANGED )); then
    audit_wsl_conf
    if [[ "$FIX_SCOPE" == "wsl" ]]; then
      audit_shell_profiles
    elif [[ "$FIX_SCOPE" == "all" ]]; then
      audit_shell_profiles
    fi
    add_finding INFO WSL_RESTART_REQUIRED "$WSL_CONF" "wsl.conf changed. Run 'wsl.exe --shutdown' from Windows, reopen the distro, then rerun audit."
  elif [[ "$FIX_SCOPE" == "wsl" ]]; then
    if [[ -e "$WSL_INTEROP_FILE" ]]; then
      add_finding INFO WSL_INTEROP_HANDLER_PRESENT "$WSL_INTEROP_FILE" "WSLInterop binfmt handler is present."
    else
      add_finding FAIL WSL_INTEROP_HANDLER_MISSING "$WSL_INTEROP_FILE" "WSLInterop binfmt handler is missing; Windows process interop is not currently available."
    fi
    audit_wsl_conf
    audit_path_entries
    audit_toolchains
    audit_mise
    audit_shell_profiles
  elif [[ "$FIX_SCOPE" == "path" ]]; then
    # Re-scan sources only after an applied change. During dry-run, fixable source
    # contamination is represented by PATH_PROFILE_WOULD_CHANGE instead of a
    # second blocking finding from the unchanged file.
    (( DRY_RUN )) || audit_shell_profiles
  fi

  (( EXEC_ERROR != 0 )) && { render_output ERROR; return 2; }
  counts="$(finding_counts)"; fail=${counts%% *}
  if (( fail > 0 )); then render_output FAIL; return 1; fi
  if (( DRY_RUN )); then render_output; return 0; fi
  if (( WSL_CHANGED )); then render_output RESTART_REQUIRED; return 10; fi
  if (( PATH_CHANGED )); then render_output NEW_SHELL_REQUIRED; return 11; fi
  render_output
  return 0
}

run_explain() {
  local name=$1
  audit_wsl_environment
  if (( EXEC_ERROR == 0 )); then
    explain_command "$name"
  fi
  render_output
  result_exit_code
}

parse_fix_args() {
  local arg
  FIX_SCOPE="wsl"; DRY_RUN=0; DROP_MISSING=0; JSON_MODE=0
  for arg in "$@"; do
    case "$arg" in
      --path) [[ "$FIX_SCOPE" == "all" ]] || FIX_SCOPE="path" ;;
      --all) FIX_SCOPE="all" ;;
      --dry-run) DRY_RUN=1 ;;
      --drop-missing) DROP_MISSING=1 ;;
      --json) JSON_MODE=1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# parse_audit_args replaces the arm's former inline `(( $# > 1 ))` test. It is
# not merely "shaped like parse_fix_args": that one tolerates a repeated
# flag, while `audit` has always rejected a second argument outright, and
# that strictness is kept here for both --json and --probe. Every arithmetic
# test sits inside an `if` condition, never as a standalone `(( … ))`
# command -- a standalone arithmetic command returns 1 when its expression is
# zero, which would abort the parse itself under `set -e`. The function ends
# with an explicit `return 0`, because relying on the `case` inside the last
# loop iteration to supply the status is how a parser starts failing on its
# own success.
parse_audit_args() {
  local arg
  local seen_json=0
  local seen_probe=0

  JSON_MODE=0
  PROBE_MODE=0

  for arg in "$@"; do
    case "$arg" in
      --json)
        if (( seen_json == 1 )); then
          return 1
        fi
        seen_json=1
        JSON_MODE=1
        ;;
      --probe)
        if (( seen_probe == 1 )); then
          return 1
        fi
        seen_probe=1
        PROBE_MODE=1
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

main() {
  local action=${1:-}
  [[ -n "$action" ]] || { usage >&2; return 2; }
  CURRENT_ACTION=$action
  shift || true
  case "$action" in
    audit)
      # A rejected parse may leave a partial JSON_MODE/PROBE_MODE assignment
      # behind (e.g. `audit --probe --probe` sets PROBE_MODE=1 before the
      # repeat is detected). That is harmless: usage/return 2 below runs
      # before run_audit, so no audit runs and no probe is invoked on this
      # command line, and the next invocation resets both flags regardless.
      parse_audit_args "$@" || { usage >&2; return 2; }
      run_audit
      ;;
    fix)
      parse_fix_args "$@" || { usage >&2; return 2; }
      run_fix
      ;;
    explain)
      local name=${1:-}
      [[ -n "$name" ]] || { usage >&2; return 2; }
      shift || true
      if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--json" ]]; }; then usage >&2; return 2; fi
      [[ "${1:-}" == "--json" ]] && JSON_MODE=1
      run_explain "$name"
      ;;
    -h|--help|help)
      (( $# == 0 )) || { usage >&2; return 2; }
      usage
      ;;
    --version)
      (( $# == 0 )) || { usage >&2; return 2; }
      printf '%s\n' "$SCRIPT_VERSION"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
