#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.3.0"
SCHEMA_VERSION=1
WSL_CONF="${WTD_WSL_CONF:-/etc/wsl.conf}"
MOUNTS_FILE="${WTD_MOUNTS_FILE:-/proc/self/mounts}"
WSL_INTEROP_FILE="${WTD_WSL_INTEROP_FILE:-/proc/sys/fs/binfmt_misc/WSLInterop}"
SCAN_PATH="${WTD_SCAN_PATH:-${PATH:-}}"
JSON_MODE=0
CURRENT_ACTION=""
EXEC_ERROR=0
FIX_SCOPE="wsl"
DRY_RUN=0
DROP_MISSING=0
WSL_CHANGED=0
PATH_CHANGED=0

F_SEVERITY=()
F_CODE=()
F_SUBJECT=()
F_MESSAGE=()

usage() {
  cat <<'USAGE'
Usage:
  wsl-toolchain-doctor.sh audit [--json]
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


mise_bin() {
  if [[ ${WTD_MISE_BIN+x} ]]; then
    [[ -n "$WTD_MISE_BIN" ]] || return 1
    printf '%s' "$WTD_MISE_BIN"
    return 0
  fi
  command -v mise 2>/dev/null
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
    "$SCHEMA_VERSION" "$(json_escape "$VERSION")" "$(json_escape "$CURRENT_ACTION")" "$(json_escape "$status")"
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
    (( EXEC_ERROR == 0 )) && audit_mise
    (( EXEC_ERROR == 0 )) && audit_shell_profiles
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

main() {
  local action=${1:-}
  [[ -n "$action" ]] || { usage >&2; return 2; }
  CURRENT_ACTION=$action
  shift || true
  case "$action" in
    audit)
      if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--json" ]]; }; then usage >&2; return 2; fi
      [[ "${1:-}" == "--json" ]] && JSON_MODE=1
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
      printf '%s\n' "$VERSION"
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
