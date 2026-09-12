#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT_DIR/wsl-toolchain-doctor/wsl-toolchain-doctor.sh"
PASS_COUNT=0
FAIL_COUNT=0
LAST_OUT=""
LAST_RC=0
TMP_ROOT=""

pass() { printf 'ok - %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'not ok - %s\n%s\n' "$1" "${2:-}"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_contains() {
  local name=$1 haystack=$2 needle=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected to contain: $needle\nactual: $haystack"
  fi
}

assert_not_contains() {
  local name=$1 haystack=$2 needle=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "did not expect: $needle\nactual: $haystack"
  fi
}

assert_eq() {
  local name=$1 actual=$2 expected=$3
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected: $expected\nactual: $actual"
  fi
}

setup_fixture() {
  TMP_ROOT="$(mktemp -d)"
  mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/linux/bin"
  cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
MOUNTS
  cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=true
appendWindowsPath=false
CONF
  : > "$TMP_ROOT/wslinterop"
}

teardown_fixture() { [[ -n "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"; TMP_ROOT=""; }

run_doctor() {
  set +e
  # MISE_SHELL and MISE_SESSION are cleared so that WTD_MISE_ACTIVATED is the
  # only thing deciding whether the run looks activated. mise_is_activated
  # falls back to those two variables when the override is empty, and the
  # reference workstation activates mise from .bashrc, so without this the
  # non-activated cases pass or fail according to the shell that happened to
  # launch the suite -- green from a script, two failures from a terminal.
  #
  # DOCKER_HOST is pinned for the same reason. This is `env`, not `env -i`, so
  # the caller's environment passes straight through, and a developer who has
  # DOCKER_HOST exported for their own daemon would otherwise turn every
  # no-evidence container case into a false positive. Both container overrides
  # default to empty, so the container-runtime check stays silent unless a test
  # asks for it.
  # XDG_STATE_HOME/XDG_CONFIG_HOME and the three new file-path seams
  # (WTD_CATALOG_FILE, WTD_RECEIPT_FILE, WTD_MISE_TOOLCHAIN_CONFIG) are pinned
  # under TMP_ROOT so no case reads a real receipt, catalog or mise config
  # from the developer's own machine. None of these three has a "search
  # elsewhere" fallback to protect, so pinning them to a fixture path -- one
  # that need not exist unless a specific test creates it -- disables nothing
  # a future case would need present.
  #
  # WTD_OPENSPEC_BIN and WTD_TIMEOUT_BIN are different: they are executable
  # seams with a three-state contract (unset/injected/empty), and pinning
  # them to "" by default the way WTD_MISE_BIN is pinned would collapse
  # "unset" and "empty" into one state, making the production command -v
  # fallback untestable through this harness. So they are left OUT of the env
  # invocation entirely unless a test opts in via WTD_TEST_OPENSPEC_BIN /
  # WTD_TEST_TIMEOUT_BIN (set, even to "", to inject that value; left unset to
  # keep the child's WTD_OPENSPEC_BIN/WTD_TIMEOUT_BIN genuinely unset).
  local -a env_args=(
    -u MISE_SHELL
    -u MISE_SESSION
    -u WTD_OPENSPEC_BIN
    -u WTD_TIMEOUT_BIN
    WTD_ASSUME_WSL=1
    WTD_NO_COLOR=1
    WTD_WSL_CONF="$TMP_ROOT/wsl.conf"
    WTD_MOUNTS_FILE="$TMP_ROOT/mounts"
    WTD_WSL_INTEROP_FILE="$TMP_ROOT/wslinterop"
    WTD_SCAN_PATH="${WTD_TEST_SCAN_PATH:-$TMP_ROOT/linux/bin}"
    WTD_PROFILE_FILES="${WTD_TEST_PROFILE_FILES:-}"
    WTD_MISE_BIN="${WTD_TEST_MISE_BIN:-}"
    WTD_MISE_ACTIVATED="${WTD_TEST_MISE_ACTIVATED:-}"
    WTD_FAKE_MISE_JAVA="${WTD_FAKE_MISE_JAVA:-}"
    WTD_DOCKER_SOCKET="${WTD_TEST_DOCKER_SOCKET:-}"
    DOCKER_HOST="${WTD_TEST_DOCKER_HOST:-}"
    XDG_STATE_HOME="$TMP_ROOT/xdg-state"
    XDG_CONFIG_HOME="$TMP_ROOT/xdg-config"
    WTD_CATALOG_FILE="${WTD_TEST_CATALOG_FILE:-$TMP_ROOT/catalog.env}"
    WTD_RECEIPT_FILE="${WTD_TEST_RECEIPT_FILE:-$TMP_ROOT/receipt.env}"
    WTD_MISE_TOOLCHAIN_CONFIG="${WTD_TEST_MISE_TOOLCHAIN_CONFIG:-$TMP_ROOT/mise-toolchain.toml}"
    HOME="$TMP_ROOT/home"
  )
  if [[ ${WTD_TEST_OPENSPEC_BIN+x} ]]; then
    env_args+=("WTD_OPENSPEC_BIN=$WTD_TEST_OPENSPEC_BIN")
  fi
  if [[ ${WTD_TEST_TIMEOUT_BIN+x} ]]; then
    env_args+=("WTD_TIMEOUT_BIN=$WTD_TEST_TIMEOUT_BIN")
  fi
  LAST_OUT="$(env "${env_args[@]}" bash "$SCRIPT" "$@" 2>&1)"
  LAST_RC=$?
  set -e
}

# run_doctor_status -- run_doctor's own env/fixture wiring, with the exit
# status surfaced as this function's own return instead of only $LAST_RC, so
# a call site can write `if run_doctor_status audit --probe; then ...`.
run_doctor_status() {
  run_doctor "$@"
  return "$LAST_RC"
}

# --- Task 7 fixtures: the TOOLKIT_ finding domain --------------------------

# write_test_catalog DEST
# Writes the toolkit's real software-catalog.env verbatim, so every
# TOOLKIT_* test compares against the same seventeen keys the installer
# actually ships, without duplicating its content here.
write_test_catalog() {
  cp "$ROOT_DIR/catalog/software-catalog.env" "$1"
}

# write_test_mise_config DEST
# Writes a [tools] table in the shape render_mise_configuration produces for
# the real catalog's twelve mise-managed keys. Agrees with write_valid_receipt
# below, so the two together are comparison A's "everything current" baseline.
write_test_mise_config() {
  cat > "$1" <<'TOML'
[tools]
java = ["temurin-17", "temurin-21"]
dotnet = ["10", "8"]
python = "3.12"
node = "24"
bun = "1"
maven = "3.9.16"
uv = "latest"
"dotnet:dotnet-ef" = "latest"
shellcheck = "latest"
gitleaks = "latest"
TOML
}

# write_valid_receipt DEST [CATALOG_FILE]
# Writes a receipt agreeing with the real catalog (and, by extension, with
# write_test_mise_config's rendering of it): every requested.* and
# installed.* value matches, skipped= and overridden= are both empty. Tests
# that want drift, staleness, a skip or an override mutate the fixture this
# writes rather than hand-rolling their own from scratch.
write_valid_receipt() {
  local dest=$1
  local catalog=${2:-$TMP_ROOT/catalog.env}
  local sha=""
  [[ -r "$catalog" ]] && sha="$(sha256sum -- "$catalog" 2>/dev/null | cut -d' ' -f1)"
  [[ -n "$sha" ]] || sha="$(printf '%064d' 0)"
  cat > "$dest" <<RECEIPT
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=$sha
skipped=
overridden=
requested.java-17=temurin-17
requested.java-21=temurin-21
requested.dotnet-10=10
requested.dotnet-8=8
requested.python=3.12
requested.node=24
requested.bun=1
requested.maven=3.9.16
requested.dotnet-ef=latest
requested.uv=latest
requested.shellcheck=latest
requested.gitleaks=latest
requested.pyyaml=latest
requested.openspec=1.9.0
requested.superpowers=v6.3.0
requested.karpathy-ref=2c606141936f1eeef17fa3043a72095b4765b9c2
installed.java-17=17.0.13
installed.java-21=21.0.5
installed.dotnet-10=10.0.100
installed.dotnet-8=8.0.404
installed.python=3.12.1
installed.node=24.8.1
installed.bun=1.1.0
installed.maven=3.9.16
installed.dotnet-ef=9.0.100
installed.uv=0.5.11
installed.shellcheck=0.10.0
installed.gitleaks=8.21.2
installed.pyyaml=6.0.2
installed.openspec=1.9.0
installed.karpathy-sha256=6e22cc54cb02a5e98ae42d06d9d7292db0c1b43894831b32879beb0166b2aea7
RECEIPT
}

# setup_toolkit_baseline
# The "everything current" fixture: catalog, matching global mise config, and
# a matching receipt, all agreeing. Comparison A, B and C tests start here and
# mutate one file to introduce exactly the drift/staleness/skip/override
# under test.
setup_toolkit_baseline() {
  write_test_catalog "$TMP_ROOT/catalog.env"
  write_test_mise_config "$TMP_ROOT/mise-toolchain.toml"
  write_valid_receipt "$TMP_ROOT/receipt.env" "$TMP_ROOT/catalog.env"
}

# receipt_skip_all_except DEST KEEP...
# Rewrites DEST's skipped= line so every one of the sixteen requested.* keys
# is skipped except the ones named. Isolates a single component's probe in a
# comparison-B test without needing a fixture that answers correctly for
# all twelve mise-backed probes at once.
receipt_skip_all_except() {
  local dest=$1
  shift
  local -a keep=("$@")
  local -a all=(
    java-17 java-21 dotnet-10 dotnet-8 python node bun maven dotnet-ef uv
    shellcheck gitleaks pyyaml openspec superpowers karpathy-ref
  )
  local -a skip=()
  local key k found
  for key in "${all[@]}"; do
    found=0
    for k in "${keep[@]}"; do
      [[ "$key" == "$k" ]] && { found=1; break; }
    done
    (( found == 1 )) || skip+=("$key")
  done
  local joined
  joined="$(IFS=,; printf '%s' "${skip[*]}")"
  sed -i "s/^skipped=.*/skipped=$joined/" "$dest"
}

# write_passthrough_timeout_stub DEST
# A faithful drop-in for coreutils timeout, minus the actual bound: drops the
# duration argument and execs the rest, so every real fixture command still
# runs through it.
write_passthrough_timeout_stub() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
shift
exec "$@"
STUB
  chmod +x "$1"
}

# write_timeout_stub_always_times_out DEST
# Ignores its arguments and reports coreutils timeout's own convention for
# "the bound was hit" (124), so a probe wrapped in it is a timeout without
# actually waiting ten seconds.
write_timeout_stub_always_times_out() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
exit 124
STUB
  chmod +x "$1"
}

# write_baseline_mise_stub DEST LOG
# A single fixture standing in for mise across every comparison-B probe,
# case-dispatching on argv to return output that write_valid_receipt's
# installed.* values already agree with -- the "everything current" B
# baseline. Every invocation is appended to LOG first, so a test can assert
# on which probes actually ran.
write_baseline_mise_stub() {
  local dest=$1 log=$2
  cat > "$dest" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$*" in
  "exec java@temurin-17"*)
    printf 'openjdk version "17.0.13" 2024-10-15\n' 1>&2 ;;
  "exec java@temurin-21"*)
    printf 'openjdk version "21.0.5" 2024-10-15\n' 1>&2 ;;
  "exec -- dotnet --list-sdks")
    printf '8.0.404 [/x]\n10.0.100 [/x]\n' ;;
  "exec -- python --version")
    printf 'Python 3.12.1\n' ;;
  "exec -- node --version")
    printf 'v24.8.1\n' ;;
  "exec -- bun --version")
    printf '1.1.0\n' ;;
  "exec -- mvn -version")
    printf 'Apache Maven 3.9.16 (abcd)\n' ;;
  "exec -- dotnet-ef --version")
    printf 'ASCII ART BANNER\n9.0.100\n' ;;
  "exec -- uv --version")
    printf 'uv 0.5.11\n' ;;
  "exec -- shellcheck --version")
    printf 'version: 0.10.0\n' ;;
  "exec -- gitleaks version")
    printf 'v8.21.2\n' ;;
  "exec -- python -c"*)
    printf '6.0.2\n' ;;
  *)
    exit 1 ;;
esac
STUB
  chmod +x "$dest"
}

# write_baseline_openspec_stub DEST LOG
# openspec's half of the B baseline: logs its invocation, then answers with
# the version write_valid_receipt already records as installed.openspec.
write_baseline_openspec_stub() {
  local dest=$1 log=$2
  cat > "$dest" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
printf 'openspec version 1.9.0\n'
STUB
  chmod +x "$dest"
}

# Task 1: configuration and environment audit
setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=false
CONF
run_doctor audit
assert_eq "clean interop config exits zero" "$LAST_RC" "0"
assert_contains "clean interop config reports enabled" "$LAST_OUT" "WSL_INTEROP_ENABLED"
assert_contains "clean interop config reports appendWindowsPath disabled" "$LAST_OUT" "WSL_APPEND_WINDOWS_PATH_DISABLED"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=true
CONF
run_doctor audit
assert_eq "missing appendWindowsPath fails policy" "$LAST_RC" "1"
assert_contains "missing appendWindowsPath identifies effective true default" "$LAST_OUT" "WSL_APPEND_WINDOWS_PATH_ENABLED"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=true
appendWindowsPath=false

[interop]
enabled=true
appendWindowsPath=false
CONF
run_doctor audit
assert_eq "duplicate interop section is configuration error" "$LAST_RC" "2"
assert_contains "duplicate interop section is explicit" "$LAST_OUT" "WSL_CONF_DUPLICATE_INTEROP"
teardown_fixture

# Non-WSL uses the real detector; no WTD_ASSUME_WSL override.
setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=true
appendWindowsPath=false
CONF
set +e
LAST_OUT="$(env -u WSL_DISTRO_NAME -u WSL_INTEROP WTD_ASSUME_WSL=0 WTD_NO_COLOR=1 WTD_WSL_CONF="$TMP_ROOT/wsl.conf" WTD_MOUNTS_FILE="$TMP_ROOT/mounts" WTD_WSL_INTEROP_FILE="$TMP_ROOT/wslinterop" WTD_SCAN_PATH="$TMP_ROOT/linux/bin" WTD_PROFILE_FILES="" HOME="$TMP_ROOT/home" bash "$SCRIPT" audit 2>&1)"
LAST_RC=$?
set -e
assert_eq "non-WSL environment is unsupported" "$LAST_RC" "2"
assert_contains "non-WSL error is explicit" "$LAST_OUT" "NOT_WSL"
teardown_fixture


# Task 2: Windows mount provenance and PATH policy
setup_fixture
mkdir -p "$TMP_ROOT/win/Windows/System32"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Windows/System32" run_doctor audit
assert_eq "generic Windows-backed PATH fails" "$LAST_RC" "1"
assert_contains "generic Windows-backed PATH is identified" "$LAST_OUT" "PATH_WINDOWS_DRVFS"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/windir/c/Users/test/bin"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/windir/c 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$TMP_ROOT/windir/c/Users/test/bin" run_doctor audit
assert_eq "non-default DrvFs root still fails" "$LAST_RC" "1"
assert_contains "non-default DrvFs root is detected from mounts" "$LAST_OUT" "PATH_WINDOWS_DRVFS"
teardown_fixture

setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
mkdir -p "$RANCHER_BIN"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$RANCHER_BIN" run_doctor audit
assert_eq "Rancher Linux bin PATH exception is allowed" "$LAST_RC" "0"
assert_contains "Rancher Linux bin PATH exception is explicit" "$LAST_OUT" "PATH_RANCHER_LINUX_ALLOWED"
assert_not_contains "Rancher Linux bin is not generic DrvFs failure" "$LAST_OUT" "PATH_WINDOWS_DRVFS"
teardown_fixture


# Task 3: tool candidate enumeration and binary classification
setup_fixture
WIN_BIN="$TMP_ROOT/win/Program Files/dotnet"
mkdir -p "$WIN_BIN"
printf 'MZfake-dotnet\n' > "$WIN_BIN/dotnet.exe"
chmod +x "$WIN_BIN/dotnet.exe"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$WIN_BIN" run_doctor audit
assert_eq "Windows PE runtime candidate fails" "$LAST_RC" "1"
assert_contains "Windows PE runtime is classified by magic" "$LAST_OUT" "TOOL_WINDOWS_PE"
assert_contains "Windows PE runtime finding names dotnet.exe" "$LAST_OUT" "dotnet.exe"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/win/runtime" "$TMP_ROOT/linux/bin"
printf 'MZfake-java\n' > "$TMP_ROOT/win/runtime/java.exe"
chmod +x "$TMP_ROOT/win/runtime/java.exe"
ln -s "$TMP_ROOT/win/runtime/java.exe" "$TMP_ROOT/linux/bin/java"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit
assert_eq "Linux-path symlink escaping to Windows PE fails" "$LAST_RC" "1"
assert_contains "symlink escape is detected from final target" "$LAST_OUT" "TOOL_WINDOWS_PE"
assert_contains "symlink report includes resolved Windows target" "$LAST_OUT" "$TMP_ROOT/win/runtime/java.exe"
teardown_fixture

setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
mkdir -p "$RANCHER_BIN"
printf '\177ELFfake-java\n' > "$RANCHER_BIN/java"
chmod +x "$RANCHER_BIN/java"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$RANCHER_BIN" run_doctor audit
assert_eq "managed runtime in Rancher path still fails" "$LAST_RC" "1"
assert_contains "managed runtime cannot use Rancher exception" "$LAST_OUT" "MANAGED_TOOL_RANCHER_PATH"
teardown_fixture

setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
mkdir -p "$RANCHER_BIN"
printf '\177ELFfake-docker\n' > "$RANCHER_BIN/docker"
chmod +x "$RANCHER_BIN/docker"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$RANCHER_BIN" run_doctor audit
assert_eq "Rancher Linux ELF container tool is allowed" "$LAST_RC" "0"
assert_contains "Rancher container exception checks ELF" "$LAST_OUT" "CONTAINER_TOOL_RANCHER_LINUX"
teardown_fixture

# Container runtime reachability.
#
# The audit's tool checks only inspect names they find on PATH, so a container
# CLI that is missing entirely produces no finding at all and the audit exits
# clean. That is the exact shape of the Rancher Desktop drift this check exists
# for: its WSL integration mounts the daemon socket and writes ~/.docker/config.json
# but never touches PATH, leaving a reachable runtime no shell can drive.
#
# The check is evidence-gated on purpose. "No container CLI" is not by itself a
# defect -- plenty of machines have no runtime and want none, and telling them
# to install one would be provisioning advice, which this tool does not give.
# Only a runtime that is demonstrably reachable while no CLI can reach it is
# drift, so a socket or DOCKER_HOST must be present before anything is said.

# Creates a real AF_UNIX socket. The production check is `-S`, not `-e`, and
# proving that requires an actual socket -- which bash cannot create. python3 is
# the only interpreter this repository already assumes elsewhere (the policy
# validator requires one, and the installer pins Python 3.12), and a hard
# failure here is deliberate: a skip would report green while leaving the one
# positive socket case unproven.
make_unix_socket() {
  local path=$1
  if ! command -v python3 >/dev/null 2>&1; then
    fail "make_unix_socket requires python3" "python3 not found; cannot create an AF_UNIX socket fixture"
    return 1
  fi
  python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sys.argv[1])' "$path"
}

setup_fixture
if make_unix_socket "$TMP_ROOT/docker.sock"; then
  WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/docker.sock" run_doctor audit
  assert_contains "reachable socket with no container CLI is reported" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
  assert_contains "unreachable runtime names the evidence" "$LAST_OUT" "$TMP_ROOT/docker.sock"
  assert_contains "unreachable runtime is a warning, not a failure" "$LAST_OUT" "WARN  CONTAINER_TOOL_UNREACHABLE"
  assert_eq "unreachable runtime does not fail the audit" "$LAST_RC" "0"
  UNREACHABLE_COUNT="$(grep -c 'CONTAINER_TOOL_UNREACHABLE' <<< "$LAST_OUT" | tr -d ' ')"
  assert_eq "unreachable runtime is reported once, not per tool name" "$UNREACHABLE_COUNT" "1"
fi
teardown_fixture

setup_fixture
if make_unix_socket "$TMP_ROOT/docker.sock"; then
  printf '\177ELFfake-docker\n' > "$TMP_ROOT/linux/bin/docker"
  chmod +x "$TMP_ROOT/linux/bin/docker"
  WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/docker.sock" run_doctor audit
  assert_not_contains "reachable socket with docker on PATH is silent" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
  assert_eq "reachable runtime with a CLI exits zero" "$LAST_RC" "0"
fi
teardown_fixture

# nerdctl counts: Rancher ships it beside docker and it drives the same
# containers, so a shell holding only nerdctl is not stranded.
setup_fixture
if make_unix_socket "$TMP_ROOT/docker.sock"; then
  printf '\177ELFfake-nerdctl\n' > "$TMP_ROOT/linux/bin/nerdctl"
  chmod +x "$TMP_ROOT/linux/bin/nerdctl"
  WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/docker.sock" run_doctor audit
  assert_not_contains "nerdctl alone satisfies runtime reachability" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
fi
teardown_fixture

# kubectl and helm are in CONTAINER_TOOL_NAMES but neither drives a container
# runtime, so neither may suppress the finding.
setup_fixture
if make_unix_socket "$TMP_ROOT/docker.sock"; then
  printf '\177ELFfake-kubectl\n' > "$TMP_ROOT/linux/bin/kubectl"
  chmod +x "$TMP_ROOT/linux/bin/kubectl"
  WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/docker.sock" run_doctor audit
  assert_contains "kubectl does not satisfy runtime reachability" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
fi
teardown_fixture

setup_fixture
run_doctor audit
assert_not_contains "no runtime evidence stays silent" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
assert_eq "no runtime evidence exits zero" "$LAST_RC" "0"
teardown_fixture

# A regular file at the socket path is not a runtime. This pins the check to
# `-S` and stops it degrading to a bare existence test.
setup_fixture
: > "$TMP_ROOT/not-a-socket"
WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/not-a-socket" run_doctor audit
assert_not_contains "a regular file at the socket path is not evidence" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
teardown_fixture

setup_fixture
WTD_TEST_DOCKER_SOCKET="$TMP_ROOT/absent.sock" run_doctor audit
assert_not_contains "a missing socket path is not evidence" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
teardown_fixture

# DOCKER_HOST is the second evidence source, and needs no filesystem: a daemon
# reached over TCP or a non-default socket is just as unreachable from a shell
# with no CLI.
setup_fixture
WTD_TEST_DOCKER_HOST="tcp://127.0.0.1:2375" run_doctor audit
assert_contains "DOCKER_HOST with no container CLI is reported" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
assert_contains "DOCKER_HOST evidence is named in the finding" "$LAST_OUT" "tcp://127.0.0.1:2375"
assert_eq "DOCKER_HOST evidence does not fail the audit" "$LAST_RC" "0"
teardown_fixture

setup_fixture
printf '\177ELFfake-docker\n' > "$TMP_ROOT/linux/bin/docker"
chmod +x "$TMP_ROOT/linux/bin/docker"
WTD_TEST_DOCKER_HOST="tcp://127.0.0.1:2375" run_doctor audit
assert_not_contains "DOCKER_HOST with docker on PATH is silent" "$LAST_OUT" "CONTAINER_TOOL_UNREACHABLE"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/a" "$TMP_ROOT/linux/b"
cat > "$TMP_ROOT/linux/a/java" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
cat > "$TMP_ROOT/linux/b/java" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$TMP_ROOT/linux/a/java" "$TMP_ROOT/linux/b/java"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/a:$TMP_ROOT/linux/b" run_doctor explain java
assert_eq "explain with two Linux candidates succeeds" "$LAST_RC" "0"
assert_contains "explain lists first candidate" "$LAST_OUT" "$TMP_ROOT/linux/a/java"
assert_contains "explain lists shadowed candidate" "$LAST_OUT" "$TMP_ROOT/linux/b/java"
assert_contains "explain identifies script format" "$LAST_OUT" "SCRIPT"
teardown_fixture


setup_fixture
mkdir -p "$TMP_ROOT/linux/bin"
cat > "$TMP_ROOT/linux/bin/java" <<'SCRIPT'
#!/usr/bin/env bash
exec "/mnt/c/Program Files/Java/bin/java.exe" "$@"
SCRIPT
chmod +x "$TMP_ROOT/linux/bin/java"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit
assert_eq "suspicious Linux wrapper is warning only" "$LAST_RC" "0"
assert_contains "managed wrapper Windows reference is surfaced" "$LAST_OUT" "TOOL_WRAPPER_WINDOWS_REFERENCE"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/bin" "$TMP_ROOT/win/Python"
printf 'MZpython\n' > "$TMP_ROOT/win/Python/python.exe"
chmod +x "$TMP_ROOT/win/Python/python.exe"
cat > "$TMP_ROOT/linux/bin/python" <<SCRIPT
#!$TMP_ROOT/win/Python/python.exe
exit 0
SCRIPT
chmod +x "$TMP_ROOT/linux/bin/python"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit
assert_eq "script with Windows shebang interpreter fails" "$LAST_RC" "1"
assert_contains "Windows shebang interpreter is explicit" "$LAST_OUT" "TOOL_SCRIPT_WINDOWS_INTERPRETER"
teardown_fixture


# Task 4: conservative shell profile scan and wsl.conf remediation
setup_fixture
mkdir -p "$TMP_ROOT/win/Program Files/dotnet"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.bashrc" <<PROFILE
export PATH="\$PATH:$TMP_ROOT/win/Program Files/dotnet"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.bashrc" run_doctor audit
assert_eq "profile that reintroduces Windows PATH fails" "$LAST_RC" "1"
assert_contains "profile contamination has dedicated code" "$LAST_OUT" "SHELL_PROFILE_WINDOWS_PATH"
assert_contains "profile contamination reports file and line" "$LAST_OUT" "$TMP_ROOT/home/.bashrc:1"
teardown_fixture

setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
mkdir -p "$RANCHER_BIN"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.bashrc" <<PROFILE
export PATH="\$PATH:$RANCHER_BIN"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.bashrc" run_doctor audit
assert_eq "profile may explicitly add Rancher Linux bin" "$LAST_RC" "0"
assert_contains "profile Rancher allowance is visible" "$LAST_OUT" "SHELL_PROFILE_RANCHER_PATH_ALLOWED"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
# keep this comment
[boot]
systemd=true

[interop]
enabled=false
appendWindowsPath=true

[network]
generateResolvConf=false
CONF
run_doctor fix
assert_eq "fix returns restart-required exit code" "$LAST_RC" "10"
assert_contains "fix reports backup" "$LAST_OUT" "WSL_CONF_BACKUP_CREATED"
assert_contains "fix reports restart requirement" "$LAST_OUT" "WSL_RESTART_REQUIRED"
FIXED_CONTENT="$(cat "$TMP_ROOT/wsl.conf")"
assert_contains "fix preserves unrelated comment" "$FIXED_CONTENT" "# keep this comment"
assert_contains "fix preserves boot section" "$FIXED_CONTENT" "systemd=true"
assert_contains "fix sets interop enabled" "$FIXED_CONTENT" "enabled=true"
assert_contains "fix disables Windows PATH append" "$FIXED_CONTENT" "appendWindowsPath=false"
assert_contains "fix preserves network section" "$FIXED_CONTENT" "generateResolvConf=false"
BACKUP_COUNT="$(find "$TMP_ROOT" -maxdepth 1 -name 'wsl.conf.bak.*' -type f | wc -l | tr -d ' ')"
assert_eq "fix creates exactly one backup" "$BACKUP_COUNT" "1"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[boot]
systemd=true
CONF
run_doctor fix
assert_eq "fix adds missing interop section and requires restart" "$LAST_RC" "10"
FIXED_CONTENT="$(cat "$TMP_ROOT/wsl.conf")"
assert_contains "missing interop section is added" "$FIXED_CONTENT" "[interop]"
assert_contains "new interop section enables interop" "$FIXED_CONTENT" "enabled=true"
assert_contains "new interop section disables Windows PATH append" "$FIXED_CONTENT" "appendWindowsPath=false"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=false
appendWindowsPath=true
[interop]
enabled=true
appendWindowsPath=false
CONF
BEFORE="$(cat "$TMP_ROOT/wsl.conf")"
run_doctor fix
assert_eq "fix refuses duplicate interop sections" "$LAST_RC" "2"
assert_contains "fix refusal explains ambiguity" "$LAST_OUT" "WSL_CONF_DUPLICATE_INTEROP"
AFTER="$(cat "$TMP_ROOT/wsl.conf")"
assert_eq "ambiguous config remains untouched" "$AFTER" "$BEFORE"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/win/Tools"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="\$PATH:$TMP_ROOT/win/Tools"
PROFILE
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=false
appendWindowsPath=true
CONF
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix
assert_eq "fix reports unresolved persistent profile contamination" "$LAST_RC" "1"
assert_contains "fix still reports restart required when config changed" "$LAST_OUT" "WSL_RESTART_REQUIRED"
assert_contains "fix leaves profile remediation to user" "$LAST_OUT" "SHELL_PROFILE_WINDOWS_PATH"
PROFILE_AFTER="$(cat "$TMP_ROOT/home/.profile")"
assert_contains "fix does not rewrite profile" "$PROFILE_AFTER" "$TMP_ROOT/win/Tools"
teardown_fixture


# Task 5: JSON reporting
setup_fixture
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit --json
assert_eq "clean JSON audit exits zero" "$LAST_RC" "0"
assert_contains "JSON audit exposes schema version" "$LAST_OUT" '"schemaVersion":1'
assert_contains "JSON audit exposes v0.4.0 tool version" "$LAST_OUT" '"toolVersion":"0.4.0"'
assert_contains "JSON audit exposes action" "$LAST_OUT" '"action":"audit"'
assert_contains "JSON audit exposes PASS status" "$LAST_OUT" '"status":"PASS"'
assert_contains "JSON audit contains finding code" "$LAST_OUT" '"code":"WSL_INTEROP_ENABLED"'
assert_not_contains "JSON output has no human fixed-width prefix" "$LAST_OUT" "INFO  WSL_"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/bin\"quoted"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin\"quoted" run_doctor audit --json
assert_eq "JSON audit with literal quote now fails PATH hygiene" "$LAST_RC" "1"
assert_contains "JSON audit reports literal quote" "$LAST_OUT" 'PATH_LITERAL_QUOTE'
assert_contains "JSON escapes quotes in subjects" "$LAST_OUT" 'bin\"quoted'
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=false
appendWindowsPath=true
CONF
run_doctor fix --json
assert_eq "JSON fix keeps restart-required exit code" "$LAST_RC" "10"
assert_contains "JSON fix exposes restart-required status" "$LAST_OUT" '"status":"RESTART_REQUIRED"'
assert_contains "JSON fix includes restart finding" "$LAST_OUT" '"code":"WSL_RESTART_REQUIRED"'
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/a"
cat > "$TMP_ROOT/linux/a/java" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$TMP_ROOT/linux/a/java"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/a" run_doctor explain java --json
assert_eq "JSON explain succeeds for Linux command" "$LAST_RC" "0"
assert_contains "JSON explain exposes action" "$LAST_OUT" '"action":"explain"'
assert_contains "JSON explain exposes script format in message" "$LAST_OUT" "format=SCRIPT"
teardown_fixture


# Regression: Rancher allowance must not mask another Windows PATH on the same line.
setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
GENERIC_WIN="$TMP_ROOT/win/Windows/System32"
mkdir -p "$RANCHER_BIN" "$GENERIC_WIN"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.bashrc" <<PROFILE
export PATH="\$PATH:$RANCHER_BIN:$GENERIC_WIN"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.bashrc" run_doctor audit
assert_eq "Rancher profile exception does not mask generic Windows segment" "$LAST_RC" "1"
assert_contains "mixed Rancher and Windows line reports contamination" "$LAST_OUT" "SHELL_PROFILE_WINDOWS_PATH"
teardown_fixture


# Regression: profile audit must execute once per audit.
setup_fixture
RANCHER_BIN="$TMP_ROOT/win/Program Files/Rancher Desktop/resources/resources/linux/bin"
mkdir -p "$RANCHER_BIN"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.bashrc" <<PROFILE
export PATH="\$PATH:$RANCHER_BIN"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.bashrc" run_doctor audit
RANCHER_FINDING_COUNT="$(grep -o 'SHELL_PROFILE_RANCHER_PATH_ALLOWED' <<< "$LAST_OUT" | wc -l | tr -d ' ')"
assert_eq "profile finding is emitted once" "$RANCHER_FINDING_COUNT" "1"
teardown_fixture


# Regression: toolchain audit must execute once per audit.
setup_fixture
mkdir -p "$TMP_ROOT/linux/bin"
cat > "$TMP_ROOT/linux/bin/java" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$TMP_ROOT/linux/bin/java"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit
TOOL_FINDING_COUNT="$(grep -o 'MANAGED_TOOL_LINUX' <<< "$LAST_OUT" | wc -l | tr -d ' ')"
assert_eq "tool finding is emitted once" "$TOOL_FINDING_COUNT" "1"
teardown_fixture



# v0.3.0 regression: package version and PATH hygiene/remediation
setup_fixture
run_doctor --version
assert_eq "tool reports v0.4.0" "$LAST_RC" "0"
assert_eq "version string is exactly 0.4.0" "$LAST_OUT" "0.4.0"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/a" "$TMP_ROOT/linux/b"
ln -s "$TMP_ROOT/linux/a" "$TMP_ROOT/linux/a-link"
WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/a:$TMP_ROOT/linux/a:$TMP_ROOT/linux/a-link:$TMP_ROOT/linux/b" run_doctor audit
assert_eq "duplicate PATH entries are warnings only" "$LAST_RC" "0"
assert_contains "textual duplicate PATH is detected" "$LAST_OUT" "PATH_DUPLICATE"
assert_contains "canonical duplicate PATH is detected" "$LAST_OUT" "PATH_DUPLICATE_CANONICAL"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/bin"
printf 'not-a-directory\n' > "$TMP_ROOT/linux/file-entry"
WTD_TEST_SCAN_PATH=".:relative/bin:$TMP_ROOT/linux/file-entry:$TMP_ROOT/linux/missing:$TMP_ROOT/linux/bin" run_doctor audit
assert_eq "unsafe PATH shape fails" "$LAST_RC" "1"
assert_contains "current directory PATH is rejected" "$LAST_OUT" "PATH_CURRENT_DIRECTORY"
assert_contains "relative PATH is reported" "$LAST_OUT" "PATH_RELATIVE_ENTRY"
assert_contains "file PATH entry fails" "$LAST_OUT" "PATH_ENTRY_NOT_DIRECTORY"
assert_contains "missing PATH entry warns" "$LAST_OUT" "PATH_ENTRY_MISSING"
teardown_fixture

setup_fixture
WTD_TEST_SCAN_PATH='C:\\Program Files\\Java\\bin;/usr/bin' run_doctor audit
assert_eq "raw Windows PATH syntax fails" "$LAST_RC" "1"
assert_contains "Windows drive syntax is detected before colon split" "$LAST_OUT" "PATH_WINDOWS_SYNTAX"
assert_contains "Windows semicolon separator is detected" "$LAST_OUT" "PATH_WINDOWS_SEPARATOR"
assert_contains "excessive backslash escaping is detected" "$LAST_OUT" "PATH_EXCESSIVE_ESCAPE"
teardown_fixture

setup_fixture
# The single quotes are the point: this feeds the doctor the literal text a
# malformed PATH contains, so $HOME and %USERPROFILE% must reach it unexpanded.
# shellcheck disable=SC2016
WTD_TEST_SCAN_PATH='"/usr/bin":$HOME/bin:%USERPROFILE%/bin' run_doctor audit
assert_eq "literal quote and variables in effective PATH fail" "$LAST_RC" "1"
assert_contains "literal quote is detected" "$LAST_OUT" "PATH_LITERAL_QUOTE"
assert_contains "literal variable is detected" "$LAST_OUT" "PATH_LITERAL_VARIABLE"
teardown_fixture

setup_fixture
CONTROL_PATH="$TMP_ROOT/linux/bin"$'\t'"x"
WTD_TEST_SCAN_PATH="$CONTROL_PATH" run_doctor audit
assert_eq "control character in PATH fails" "$LAST_RC" "1"
assert_contains "control character is detected" "$LAST_OUT" "PATH_CONTROL_CHAR"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/one" "$TMP_ROOT/linux/two" "$TMP_ROOT/win/Tools"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="$TMP_ROOT/linux/one:$TMP_ROOT/linux/one:$TMP_ROOT/win/Tools:$TMP_ROOT/linux/two:\$PATH"
PROFILE
BEFORE="$(cat "$TMP_ROOT/home/.profile")"
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path --dry-run
assert_eq "PATH dry-run does not require new shell" "$LAST_RC" "0"
assert_contains "PATH dry-run reports proposal" "$LAST_OUT" "PATH_PROFILE_WOULD_CHANGE"
AFTER="$(cat "$TMP_ROOT/home/.profile")"
assert_eq "PATH dry-run is byte-for-byte non-mutating" "$AFTER" "$BEFORE"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/linux/one" "$TMP_ROOT/linux/two" "$TMP_ROOT/win/Tools"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="$TMP_ROOT/linux/one:$TMP_ROOT/linux/one:$TMP_ROOT/win/Tools:$TMP_ROOT/linux/two:\$PATH"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path
assert_eq "safe PATH remediation requires new shell" "$LAST_RC" "11"
assert_contains "safe PATH remediation reports modification" "$LAST_OUT" "PATH_PROFILE_CHANGED"
PROFILE_AFTER="$(cat "$TMP_ROOT/home/.profile")"
assert_contains "safe PATH remediation keeps first Linux entry" "$PROFILE_AFTER" "$TMP_ROOT/linux/one"
assert_not_contains "safe PATH remediation removes Windows entry" "$PROFILE_AFTER" "$TMP_ROOT/win/Tools"
ONE_COUNT="$(grep -oF "$TMP_ROOT/linux/one" <<< "$PROFILE_AFTER" | wc -l | tr -d ' ')"
assert_eq "safe PATH remediation removes duplicate" "$ONE_COUNT" "1"
BACKUP_COUNT="$(find "$TMP_ROOT/home" -maxdepth 1 -name '.profile.bak.*' -type f | wc -l | tr -d ' ')"
assert_eq "safe PATH remediation creates one sibling backup" "$BACKUP_COUNT" "1"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/home/.profile" <<'PROFILE'
export PATH="$(some-command):$PATH"
PROFILE
BEFORE="$(cat "$TMP_ROOT/home/.profile")"
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path
assert_eq "dynamic PATH remediation remains blocking" "$LAST_RC" "1"
assert_contains "dynamic PATH assignment is refused" "$LAST_OUT" "PATH_AUTO_FIX_UNSAFE"
AFTER="$(cat "$TMP_ROOT/home/.profile")"
assert_eq "dynamic PATH assignment remains unchanged" "$AFTER" "$BEFORE"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="$TMP_ROOT/linux/missing:\$PATH"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path
assert_eq "missing static PATH entry is preserved by default" "$LAST_RC" "0"
assert_contains "missing source is preserved without drop flag" "$(cat "$TMP_ROOT/home/.profile")" "$TMP_ROOT/linux/missing"
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path --drop-missing
assert_eq "drop-missing PATH remediation requires new shell" "$LAST_RC" "11"
assert_not_contains "drop-missing removes static missing source" "$(cat "$TMP_ROOT/home/.profile")" "$TMP_ROOT/linux/missing"
teardown_fixture

# v0.3.0 regression: mise-aware ownership and binding
setup_fixture
run_doctor audit
assert_contains "absence of mise is informational" "$LAST_OUT" "MISE_NOT_AVAILABLE"
assert_not_contains "absence of mise does not create required Java failure" "$LAST_OUT" "JAVA_NOT_INSTALLED"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/mise/bin" "$TMP_ROOT/mise/java/bin"
cat > "$TMP_ROOT/mise/bin/mise" <<'MISE'
#!/usr/bin/env bash
case "$1" in
  ls) printf 'java 21.0.8 ~/.config/mise.toml\n' ;;
  which) [[ "$2" == java ]] && printf '%s\n' "$WTD_FAKE_MISE_JAVA" ;;
  *) exit 1 ;;
esac
MISE
cat > "$TMP_ROOT/mise/java/bin/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
chmod +x "$TMP_ROOT/mise/bin/mise" "$TMP_ROOT/mise/java/bin/java"
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_SCAN_PATH="$TMP_ROOT/mise/java/bin" run_doctor audit
assert_eq "mise-managed Linux binding passes" "$LAST_RC" "0"
assert_contains "mise executable is trusted as Linux" "$LAST_OUT" "MISE_LINUX"
assert_contains "mise configured tool is visible" "$LAST_OUT" "MISE_TOOL_CONFIGURED"
assert_contains "mise PATH binding matches" "$LAST_OUT" "MISE_BINDING_OK"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/mise/bin" "$TMP_ROOT/mise/java/bin"
cat > "$TMP_ROOT/mise/bin/mise" <<'MISE'
#!/usr/bin/env bash
case "$1" in
  ls) printf 'java 21.0.8 ~/.config/mise.toml\n' ;;
  which) [[ "$2" == java ]] && printf '%s\n' "$WTD_FAKE_MISE_JAVA" ;;
  *) exit 1 ;;
esac
MISE
cat > "$TMP_ROOT/mise/java/bin/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
chmod +x "$TMP_ROOT/mise/bin/mise" "$TMP_ROOT/mise/java/bin/java"
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/bin" run_doctor audit
assert_eq "configured mise tool need not be exposed in current shell" "$LAST_RC" "0"
assert_contains "non-activated shell is informational" "$LAST_OUT" "MISE_TOOL_NOT_EXPOSED"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/mise/bin" "$TMP_ROOT/mise/java/bin" "$TMP_ROOT/win/Java"
cat > "$TMP_ROOT/mise/bin/mise" <<'MISE'
#!/usr/bin/env bash
case "$1" in
  ls) printf 'java 21.0.8 ~/.config/mise.toml\n' ;;
  which) [[ "$2" == java ]] && printf '%s\n' "$WTD_FAKE_MISE_JAVA" ;;
  *) exit 1 ;;
esac
MISE
cat > "$TMP_ROOT/mise/java/bin/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
printf 'MZfake-java\n' > "$TMP_ROOT/win/Java/java"
chmod +x "$TMP_ROOT/mise/bin/mise" "$TMP_ROOT/mise/java/bin/java" "$TMP_ROOT/win/Java/java"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Java:$TMP_ROOT/mise/java/bin" run_doctor audit
assert_eq "Windows PATH shadowing mise target fails" "$LAST_RC" "1"
assert_contains "Windows mise shadowing has dedicated finding" "$LAST_OUT" "MISE_TOOL_SHADOWED_WINDOWS"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/win/mise"
printf 'MZfake-mise\n' > "$TMP_ROOT/win/mise/mise.exe"
chmod +x "$TMP_ROOT/win/mise/mise.exe"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_MISE_BIN="$TMP_ROOT/win/mise/mise.exe" run_doctor audit
assert_eq "Windows-backed mise is rejected" "$LAST_RC" "1"
assert_contains "Windows-backed mise has dedicated finding" "$LAST_OUT" "MISE_WINDOWS_BACKED"
teardown_fixture

setup_fixture
mkdir -p "$TMP_ROOT/mise/bin" "$TMP_ROOT/mise/java/bin" "$TMP_ROOT/linux/other"
cat > "$TMP_ROOT/mise/bin/mise" <<'MISE'
#!/usr/bin/env bash
case "$1" in
  ls) printf 'java 21.0.8 ~/.config/mise.toml\n' ;;
  which) [[ "$2" == java ]] && printf '%s\n' "$WTD_FAKE_MISE_JAVA" ;;
  *) exit 1 ;;
esac
MISE
cat > "$TMP_ROOT/mise/java/bin/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
cat > "$TMP_ROOT/linux/other/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
chmod +x "$TMP_ROOT/mise/bin/mise" "$TMP_ROOT/mise/java/bin/java" "$TMP_ROOT/linux/other/java"
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/other:$TMP_ROOT/mise/java/bin" run_doctor audit
assert_eq "different Linux binding without activation is informational" "$LAST_RC" "0"
assert_contains "different Linux binding without activation is explicit" "$LAST_OUT" "MISE_TOOL_NOT_ACTIVATED"
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_MISE_ACTIVATED=1 WTD_TEST_SCAN_PATH="$TMP_ROOT/linux/other:$TMP_ROOT/mise/java/bin" run_doctor audit
assert_eq "different Linux binding with activation fails" "$LAST_RC" "1"
assert_contains "active mise binding shadowed by Linux is explicit" "$LAST_OUT" "MISE_TOOL_SHADOWED"
teardown_fixture

# v0.3.0 combined remediation precedence
setup_fixture
mkdir -p "$TMP_ROOT/linux/one" "$TMP_ROOT/win/Tools"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/wsl.conf" <<'CONF'
[interop]
enabled=false
appendWindowsPath=true
CONF
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="$TMP_ROOT/linux/one:$TMP_ROOT/win/Tools:\$PATH"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --all
assert_eq "combined remediation prefers restart exit code" "$LAST_RC" "10"
assert_contains "combined remediation changes wsl.conf" "$LAST_OUT" "WSL_RESTART_REQUIRED"
assert_contains "combined remediation changes PATH source" "$LAST_OUT" "PATH_PROFILE_CHANGED"
teardown_fixture

# mise lists one row per installed version, so a tool pinned to several
# versions -- java = ["temurin-17", "temurin-21"] on the reference workstation
# -- used to be audited once per row and reported three identical findings per
# extra version. Every question the audit asks about a tool has one answer per
# tool, not per version.
setup_fixture
mkdir -p "$TMP_ROOT/mise/bin" "$TMP_ROOT/mise/java/bin"
cat > "$TMP_ROOT/mise/bin/mise" <<'MISE'
#!/usr/bin/env bash
case "$1" in
  ls) printf 'java  17.0.20  ~/.config/mise.toml  temurin-17\njava  21.0.12  ~/.config/mise.toml  temurin-21\n' ;;
  which) [[ "$2" == java ]] && printf '%s\n' "$WTD_FAKE_MISE_JAVA" ;;
  *) exit 1 ;;
esac
MISE
cat > "$TMP_ROOT/mise/java/bin/java" <<'JAVA'
#!/usr/bin/env bash
exit 0
JAVA
chmod +x "$TMP_ROOT/mise/bin/mise" "$TMP_ROOT/mise/java/bin/java"
WTD_TEST_MISE_BIN="$TMP_ROOT/mise/bin/mise" WTD_FAKE_MISE_JAVA="$TMP_ROOT/mise/java/bin/java" WTD_TEST_SCAN_PATH="$TMP_ROOT/mise/java/bin" run_doctor audit
assert_eq "a tool pinned to two versions is configured once" "$(printf '%s\n' "$LAST_OUT" | grep -c 'MISE_TOOL_CONFIGURED')" "1"
assert_eq "a tool pinned to two versions is bound once" "$(printf '%s\n' "$LAST_OUT" | grep -c 'MISE_BINDING_OK')" "1"
assert_contains "the deduplicated tool is still audited" "$LAST_OUT" "MISE_BINDING_OK"
teardown_fixture

# The Windows-backed PATH allowlist.
#
# The policy exists to stop a Linux build binding to a Windows PE, not to ban
# every directory that happens to sit on DrvFs. An `sh` script or Linux ELF
# under /mnt/c runs correctly, and the editor launcher and container tooling
# are exactly that -- without them appendWindowsPath=false costs `code .` and
# `docker`, which is why the exception cannot stay hardcoded to one vendor.
setup_fixture
mkdir -p "$TMP_ROOT/win/Program Files/Microsoft VS Code/bin" "$TMP_ROOT/win/Program Files/Nowhere/bin"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Program Files/Microsoft VS Code/bin" run_doctor audit
assert_contains "the editor launcher directory is allowlisted" "$LAST_OUT" "PATH_ALLOWLISTED_WINDOWS"
assert_not_contains "the editor launcher directory does not fail" "$LAST_OUT" "PATH_WINDOWS_DRVFS"

WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Program Files/Nowhere/bin" run_doctor audit
assert_contains "an unlisted Windows directory still fails" "$LAST_OUT" "PATH_WINDOWS_DRVFS"
assert_not_contains "an unlisted Windows directory is not allowlisted" "$LAST_OUT" "PATH_ALLOWLISTED_WINDOWS"

# A single entry has no trailing newline once split on ':', so the read loop
# must not discard the last field. This regressed during implementation and
# silently ignored the whole variable.
WTD_PATH_ALLOW="/program files/nowhere/bin" WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Program Files/Nowhere/bin" run_doctor audit
assert_contains "a single WTD_PATH_ALLOW entry is honoured" "$LAST_OUT" "PATH_ALLOWLISTED_WINDOWS"
assert_not_contains "the allowlisted directory no longer fails" "$LAST_OUT" "PATH_WINDOWS_DRVFS"

WTD_PATH_ALLOW="/program files/elsewhere: /program files/nowhere/bin " WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Program Files/Nowhere/bin" run_doctor audit
assert_contains "a later WTD_PATH_ALLOW entry with padding is honoured" "$LAST_OUT" "PATH_ALLOWLISTED_WINDOWS"
teardown_fixture

# Allowlisting a directory must not allowlist a Windows binary inside it: tool
# classification is independent, so a PE still fails and the list cannot be
# used to smuggle one in.
setup_fixture
mkdir -p "$TMP_ROOT/win/Program Files/Microsoft VS Code/bin"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
printf 'MZ\x90\x00\x03\x00\x00\x00' > "$TMP_ROOT/win/Program Files/Microsoft VS Code/bin/python"
chmod +x "$TMP_ROOT/win/Program Files/Microsoft VS Code/bin/python"
WTD_TEST_SCAN_PATH="$TMP_ROOT/win/Program Files/Microsoft VS Code/bin" run_doctor audit
assert_contains "the directory is still allowlisted" "$LAST_OUT" "PATH_ALLOWLISTED_WINDOWS"
assert_contains "a PE inside an allowlisted directory still fails" "$LAST_OUT" "WINDOWS"
assert_eq "a PE inside an allowlisted directory fails the run" "$LAST_RC" "1"
teardown_fixture

# fix --path must keep an allowlisted entry, or the remediation would undo the
# reason the allowlist exists.
setup_fixture
mkdir -p "$TMP_ROOT/win/Program Files/Microsoft VS Code/bin" "$TMP_ROOT/win/Tools" "$TMP_ROOT/linux/one"
cat > "$TMP_ROOT/mounts" <<MOUNTS
/dev/root / ext4 rw,relatime 0 0
C: $TMP_ROOT/win 9p rw,aname=drvfs 0 0
MOUNTS
cat > "$TMP_ROOT/home/.profile" <<PROFILE
export PATH="$TMP_ROOT/linux/one:$TMP_ROOT/win/Program Files/Microsoft VS Code/bin:$TMP_ROOT/win/Tools:\$PATH"
PROFILE
WTD_TEST_PROFILE_FILES="$TMP_ROOT/home/.profile" run_doctor fix --path
assert_contains "remediation kept the allowlisted launcher directory" "$(cat "$TMP_ROOT/home/.profile")" "Microsoft VS Code/bin"
assert_not_contains "remediation dropped the unlisted Windows directory" "$(cat "$TMP_ROOT/home/.profile")" "win/Tools"
teardown_fixture

# Task 6: doctor groundwork -- --probe parsing, the executable seams, and the
# ported adt-kv reader/validator. Comparisons A/B/C are a later task; nothing
# here asserts a TOOLKIT_* finding.

# --probe and --json accepted together, in either order.
setup_fixture
run_doctor audit --probe
assert_eq "audit --probe is accepted" "$LAST_RC" "0"
teardown_fixture

setup_fixture
run_doctor audit --probe --json
assert_eq "audit --probe --json is accepted" "$LAST_RC" "0"
teardown_fixture

setup_fixture
run_doctor audit --json --probe
assert_eq "audit --json --probe is accepted" "$LAST_RC" "0"
teardown_fixture

# Repeats and unknown arguments are usage errors, preserving today's
# strictness rather than parse_fix_args' tolerance for a repeated flag.
setup_fixture
run_doctor audit --json --json
assert_eq "repeated --json exits 2" "$LAST_RC" "2"
teardown_fixture

setup_fixture
run_doctor audit --probe --probe
assert_eq "repeated --probe exits 2" "$LAST_RC" "2"
teardown_fixture

setup_fixture
run_doctor audit --nonsense
assert_eq "an unknown argument exits 2" "$LAST_RC" "2"
assert_contains "an unknown argument shows usage" "$LAST_OUT" "Usage:"
teardown_fixture

# A rejected command line runs no audit at all: with a bad second argument,
# none of the ordinary WSL findings appear, proving parse happens strictly
# before run_audit.
setup_fixture
run_doctor audit --probe --probe
assert_not_contains "a rejected parse runs no audit" "$LAST_OUT" "WSL_DETECTED"
teardown_fixture

# The executable seams: openspec_bin and timeout_bin, in their four states.
# Each is invoked directly by sourcing the doctor script -- safe, because
# main() only runs when BASH_SOURCE[0] == $0, which is false once sourced
# from inside `bash -c`.
SEAM_ROOT="$(mktemp -d)"
mkdir -p "$SEAM_ROOT/pathdir"
cat > "$SEAM_ROOT/pathdir/openspec" <<'FIXTURE'
#!/usr/bin/env bash
exit 0
FIXTURE
cp "$SEAM_ROOT/pathdir/openspec" "$SEAM_ROOT/pathdir/timeout"
chmod +x "$SEAM_ROOT/pathdir/openspec" "$SEAM_ROOT/pathdir/timeout"

SEAM_INJECTED_OPENSPEC="$SEAM_ROOT/injected-openspec"
cp "$SEAM_ROOT/pathdir/openspec" "$SEAM_INJECTED_OPENSPEC"
chmod +x "$SEAM_INJECTED_OPENSPEC"
SEAM_INJECTED_TIMEOUT="$SEAM_ROOT/injected-timeout"
cp "$SEAM_ROOT/pathdir/timeout" "$SEAM_INJECTED_TIMEOUT"
chmod +x "$SEAM_INJECTED_TIMEOUT"

SEAM_NOT_EXECUTABLE="$SEAM_ROOT/not-executable"
: > "$SEAM_NOT_EXECUTABLE"
chmod -x "$SEAM_NOT_EXECUTABLE"

assert_seam_resolves() {
  # assert_seam_resolves NAME FN VAR VALUE_MODE(unset|value) VALUE PATH_DIR EXPECT_RC EXPECT_OUT_MODE(literal|command-v|empty)
  local name=$1 fn=$2 var=$3 value_mode=$4 value=$5 pathdir=$6 expect_rc=$7 expect_out_mode=$8
  local out rc expected
  # run_doctor() leaves errexit ON after its first call (it ends with
  # `set -e`, restoring what it found, and this suite starts under `set -u`
  # only). The resolver legitimately returns non-zero for the empty/unusable
  # cases below, so the assignment is the condition of an `if` -- exactly
  # like the doctor's own `if ! bin="$(openspec_bin)"; then` callers -- never
  # a bare statement, which is what errexit would abort on.
  if [[ "$value_mode" == "unset" ]]; then
    # shellcheck disable=SC2016 # $1/$2 are the inner bash -c's own
    # positionals, deliberately not expanded by this outer shell.
    if out="$(env -u "$var" PATH="$pathdir:$PATH" bash -c 'source "$1"; "$2"' _ "$SCRIPT" "$fn")"; then
      rc=0
    else
      rc=$?
    fi
  else
    # shellcheck disable=SC2016 # same as above: inner bash -c positionals.
    if out="$(env "$var=$value" PATH="$pathdir:$PATH" bash -c 'source "$1"; "$2"' _ "$SCRIPT" "$fn")"; then
      rc=0
    else
      rc=$?
    fi
  fi
  assert_eq "$name exit status" "$rc" "$expect_rc"
  case "$expect_out_mode" in
    command-v)
      expected="$(PATH="$pathdir:$PATH" command -v "${fn%_bin}")"
      assert_eq "$name resolves the PATH fixture" "$out" "$expected"
      ;;
    literal)
      assert_eq "$name resolves the injected path" "$out" "$value"
      ;;
    empty)
      assert_eq "$name prints nothing" "$out" ""
      ;;
  esac
}

# unset: not exported at all, with a working fixture on PATH -- proves the
# production command -v fallback works, and that a fixture-only suite cannot
# conceal a --probe that is inert in production.
assert_seam_resolves "unset openspec_bin" openspec_bin WTD_OPENSPEC_BIN unset "" "$SEAM_ROOT/pathdir" 0 command-v
assert_seam_resolves "unset timeout_bin" timeout_bin WTD_TIMEOUT_BIN unset "" "$SEAM_ROOT/pathdir" 0 command-v

# injected: set to a fixture path, that fixture is used exactly.
assert_seam_resolves "injected openspec_bin" openspec_bin WTD_OPENSPEC_BIN value "$SEAM_INJECTED_OPENSPEC" "$SEAM_ROOT/pathdir" 0 literal
assert_seam_resolves "injected timeout_bin" timeout_bin WTD_TIMEOUT_BIN value "$SEAM_INJECTED_TIMEOUT" "$SEAM_ROOT/pathdir" 0 literal

# empty: set to "", deliberately absent -- no PATH search, proven by leaving
# a working "openspec"/"timeout" fixture on PATH and getting nothing back.
assert_seam_resolves "empty openspec_bin" openspec_bin WTD_OPENSPEC_BIN value "" "$SEAM_ROOT/pathdir" 1 empty
assert_seam_resolves "empty timeout_bin" timeout_bin WTD_TIMEOUT_BIN value "" "$SEAM_ROOT/pathdir" 1 empty

# unusable: exists but is not executable -- treated exactly like empty, again
# with no PATH fallback despite a working fixture sitting on PATH.
assert_seam_resolves "unusable openspec_bin" openspec_bin WTD_OPENSPEC_BIN value "$SEAM_NOT_EXECUTABLE" "$SEAM_ROOT/pathdir" 1 empty
assert_seam_resolves "unusable timeout_bin" timeout_bin WTD_TIMEOUT_BIN value "$SEAM_NOT_EXECUTABLE" "$SEAM_ROOT/pathdir" 1 empty

rm -rf "$SEAM_ROOT"

# The ported adt-kv reader and validator: load_kv_file and validate_kv,
# invoked directly (never through command substitution relative to their own
# arrays) by declaring the arrays in the same `bash -c` process that sources
# the doctor and calls the function.
KV_ROOT="$(mktemp -d)"

cat > "$KV_ROOT/good.env" <<'KV'
alpha=1
beta=two
KV
OUT="$(bash -c '
  source "$1"
  declare -A VALUES=() LINES=()
  declare -a ORDER=()
  ERR=""
  if load_kv_file "$2" VALUES LINES ORDER ERR; then
    printf "OK %s %s %s\n" "${VALUES[alpha]}" "${VALUES[beta]}" "${#ORDER[@]}"
  else
    printf "FAIL %s\n" "$ERR"
  fi
' _ "$SCRIPT" "$KV_ROOT/good.env")"
assert_eq "load_kv_file loads a well-formed file" "$OUT" "OK 1 two 2"

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=() LINES=()
  declare -a ORDER=()
  ERR=""
  if load_kv_file "$2" VALUES LINES ORDER ERR; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$ERR"
  fi
' _ "$SCRIPT" "$KV_ROOT/does-not-exist.env")"
assert_contains "load_kv_file reports an unreadable file without die" "$OUT" "FAIL cannot read"

cat > "$KV_ROOT/dup.env" <<'KV'
alpha=1
alpha=2
KV
OUT="$(bash -c '
  source "$1"
  declare -A VALUES=() LINES=()
  declare -a ORDER=()
  ERR=""
  if load_kv_file "$2" VALUES LINES ORDER ERR; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$ERR"
  fi
' _ "$SCRIPT" "$KV_ROOT/dup.env")"
assert_contains "load_kv_file rejects a duplicate key with the loader's text" "$OUT" \
  "dup.env:2: duplicate key: alpha (first seen at line 1)"

# The loader is called directly, never through command substitution, in
# every site above: the arrays are declared in the same `bash -c` process
# that calls load_kv_file, so a populated VALUES/ORDER after a successful
# load is itself proof the call was not swallowed by a subshell.

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=([alpha]="1") LINES=([alpha]=1)
  declare -a ORDER=(alpha)
  declare -a REQUIRED=(alpha beta)
  declare -A LISTKEYS=() MEMBERS=()
  if problem="$(validate_kv "somefile.env" VALUES LINES ORDER REQUIRED LISTKEYS MEMBERS 2>&1)"; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$problem"
  fi
' _ "$SCRIPT")"
assert_eq "validate_kv reports the first missing required key, not die" "$OUT" \
  "FAIL somefile.env: missing required key: beta"

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=([alpha]="not a value!") LINES=([alpha]=3)
  declare -a ORDER=(alpha)
  declare -a REQUIRED=()
  declare -A LISTKEYS=() MEMBERS=()
  if problem="$(validate_kv "somefile.env" VALUES LINES ORDER REQUIRED LISTKEYS MEMBERS 2>&1)"; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$problem"
  fi
' _ "$SCRIPT")"
assert_eq "validate_kv reports a malformed value" "$OUT" \
  "FAIL somefile.env:3: malformed value for key: alpha"

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=([tools]="node,unknown-tool") LINES=([tools]=5)
  declare -a ORDER=(tools)
  declare -a REQUIRED=()
  declare -A LISTKEYS=([tools]=1) MEMBERS=([node]=1)
  if problem="$(validate_kv "somefile.env" VALUES LINES ORDER REQUIRED LISTKEYS MEMBERS 2>&1)"; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$problem"
  fi
' _ "$SCRIPT")"
assert_eq "validate_kv rejects an unknown list member when membership can be checked" "$OUT" \
  "FAIL somefile.env:5: unknown catalog key in tools: unknown-tool"

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=([tools]="node,node") LINES=([tools]=7)
  declare -a ORDER=(tools)
  declare -a REQUIRED=()
  declare -A LISTKEYS=([tools]=1) MEMBERS=()
  if problem="$(validate_kv "somefile.env" VALUES LINES ORDER REQUIRED LISTKEYS MEMBERS 2>&1)"; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$problem"
  fi
' _ "$SCRIPT")"
assert_eq "validate_kv rejects a duplicate list element" "$OUT" \
  "FAIL somefile.env:7: duplicate element in tools: node"

OUT="$(bash -c '
  source "$1"
  declare -A VALUES=([tools]="") LINES=([tools]=9)
  declare -a ORDER=(tools)
  declare -a REQUIRED=()
  declare -A LISTKEYS=([tools]=1) MEMBERS=()
  if problem="$(validate_kv "somefile.env" VALUES LINES ORDER REQUIRED LISTKEYS MEMBERS 2>&1)"; then
    printf "OK\n"
  else
    printf "FAIL %s\n" "$problem"
  fi
' _ "$SCRIPT")"
assert_eq "validate_kv treats an empty list as valid" "$OUT" "OK"

rm -rf "$KV_ROOT"

# The doctor does not call die and must not acquire one -- the ported reader
# and validator report through printf+return instead.
DIE_HITS="$(grep -noE '\bdie[[:space:]]*\(' "$SCRIPT" || true)"
assert_eq "the doctor defines no die()" "$DIE_HITS" ""


# Task 7: the TOOLKIT_ finding domain -- comparisons A, B and C over an
# optional install receipt.

# --- Preconditions ----------------------------------------------------------

setup_fixture
run_doctor audit
assert_contains "no receipt is informational" "$LAST_OUT" "TOOLKIT_NOT_PROVISIONED"
assert_not_contains "no receipt is a normal state, not an error" "$LAST_OUT" "ERROR"
assert_not_contains "no receipt produces no probe advice" "$LAST_OUT" "TOOLKIT_INSTALLED_NOT_PROBED"
teardown_fixture

setup_fixture
printf 'garbage\n' > "$TMP_ROOT/receipt.env"
run_doctor audit
assert_contains "an unreadable receipt is informational" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
assert_contains "the audit still completes" "$LAST_OUT" "PATH_"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
script-version=0.1.0
script-version=0.1.0
RECEIPT
run_doctor audit
assert_contains "a duplicate receipt key reaches RECEIPT_UNREADABLE" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
assert_contains "the loader's own duplicate-key text survives" "$LAST_OUT" "duplicate key: script-version"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=deadbeef
skipped=
overridden=
RECEIPT
run_doctor audit
assert_contains "a receipt missing a required key names it first, in declared order" "$LAST_OUT" \
  "missing required key: script-version"
teardown_fixture

setup_fixture
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=deadbeef
skipped=
overridden=
RECEIPT
run_doctor audit
assert_contains "a receipt with no requested.* key is unreadable" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
teardown_fixture

# Predicate 5 (list membership) and predicate 1 (at least one requested.*)
# both fail on the same receipt: a skipped= member that is not a catalog key,
# and no requested.* key at all. This is the ruled, deliberate order:
# predicate 5 is validate_kv's own list-membership check, folded into the
# single validate_kv call that also does phase 1's required-key check, so it
# runs -- and reports -- before load_receipt's own phase-2 loop ever reaches
# predicate 1. The spec's declared 1->2->3->4->5 numbering is conceptual;
# this pins the actual, deterministic execution order as tested behaviour so
# a future refactor cannot silently invert it.
setup_fixture
write_test_catalog "$TMP_ROOT/catalog.env"
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=deadbeef
skipped=not-a-catalog-key
overridden=
RECEIPT
run_doctor audit
assert_contains "predicate 5 (list membership) is reported before predicate 1 (at least one requested.*)" \
  "$LAST_OUT" "unknown catalog key in skipped: not-a-catalog-key"
assert_not_contains "predicate 1's message does not also appear" "$LAST_OUT" "no requested.* key is present"
teardown_fixture

setup_fixture
write_test_catalog "$TMP_ROOT/catalog.env"
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=deadbeef
skipped=
overridden=
requested.java-17=temurin-17
requested.karpathy-sha256=abc123
RECEIPT
run_doctor audit
assert_contains "requested.karpathy-sha256 is rejected" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
assert_contains "the diagnostic names the forbidden key" "$LAST_OUT" "requested.karpathy-sha256"
teardown_fixture

setup_fixture
write_test_catalog "$TMP_ROOT/catalog.env"
cat > "$TMP_ROOT/receipt.env" <<'RECEIPT'
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=deadbeef
skipped=
overridden=
requested.not-a-catalog-key=1
RECEIPT
run_doctor audit
assert_contains "an unknown requested.* suffix is rejected (catalog available)" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
teardown_fixture

# No catalog: C is skipped, A still runs (it needs the mise config, not the
# catalog), and a valid receipt is still accepted (predicates 2/4/5 are
# skipped without a catalog, exactly like validate_kv's own membership check).
setup_fixture
write_test_mise_config "$TMP_ROOT/mise-toolchain.toml"
write_valid_receipt "$TMP_ROOT/receipt.env"
run_doctor audit
assert_contains "no catalog is informational" "$LAST_OUT" "TOOLKIT_CATALOG_UNAVAILABLE"
assert_contains "A still runs without a catalog" "$LAST_OUT" "TOOLKIT_CONFIG_OK"
assert_not_contains "C does not run without a catalog" "$LAST_OUT" "TOOLKIT_PINS_CURRENT"
assert_not_contains "no catalog is not a receipt validation failure" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
teardown_fixture

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_contains "a readable receipt advises --probe" "$LAST_OUT" "TOOLKIT_INSTALLED_NOT_PROBED"
teardown_fixture

# --- Comparison A: requested-configuration drift -----------------------------

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_contains "agreement reports TOOLKIT_CONFIG_OK" "$LAST_OUT" "TOOLKIT_CONFIG_OK"
assert_not_contains "agreement reports no drift" "$LAST_OUT" "TOOLKIT_CONFIG_DRIFT"
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i 's/^node = "24"$/node = "22"/' "$TMP_ROOT/mise-toolchain.toml"
run_doctor audit
assert_contains "a changed node in the global config is drift" "$LAST_OUT" "TOOLKIT_CONFIG_DRIFT"
assert_contains "the drift finding names both values" "$LAST_OUT" "Requested 24 but the mise configuration has 22."
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i 's/^java = \["temurin-17", "temurin-21"\]$/java = ["temurin-21", "temurin-17"]/' "$TMP_ROOT/mise-toolchain.toml"
run_doctor audit
assert_contains "a reordered java array drifts on java-17" "$LAST_OUT" \
  "Requested temurin-17 but the mise configuration has temurin-21."
assert_contains "a reordered java array drifts on java-21" "$LAST_OUT" \
  "Requested temurin-21 but the mise configuration has temurin-17."
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i '/^shellcheck = /d' "$TMP_ROOT/mise-toolchain.toml"
run_doctor audit
assert_contains "a config missing a requested key is reported" "$LAST_OUT" "TOOLKIT_CONFIG_MISSING"
teardown_fixture

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_not_contains "openspec is outside the twelve and never reports CONFIG_MISSING" "$LAST_OUT" \
  "openspec is absent from the mise configuration"
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i 's/^overridden=$/overridden=node/' "$TMP_ROOT/receipt.env"
sed -i 's/^node = "24"$/node = "22"/' "$TMP_ROOT/mise-toolchain.toml"
run_doctor audit
assert_contains "an overridden component still participates in A" "$LAST_OUT" \
  "Requested 24 but the mise configuration has 22."
teardown_fixture

# The case that proves A reads the global file: a project-local mise.toml,
# sitting in the working directory the doctor is invoked from, must never be
# read -- WTD_MISE_TOOLCHAIN_CONFIG names the global file regardless of cwd.
setup_fixture
setup_toolkit_baseline
mkdir -p "$TMP_ROOT/project"
cat > "$TMP_ROOT/project/mise.toml" <<'TOML'
[tools]
node = "18"
TOML
TOOLKIT_PREV_PWD="$PWD"
cd "$TMP_ROOT/project"
run_doctor audit
cd "$TOOLKIT_PREV_PWD"
assert_contains "a project-local mise config still reports agreement" "$LAST_OUT" "TOOLKIT_CONFIG_OK"
assert_not_contains "a project-local mise config produces no A finding" "$LAST_OUT" "TOOLKIT_CONFIG_DRIFT"
teardown_fixture

# --- Comparison B: installed-machine drift, --probe only --------------------

setup_fixture
setup_toolkit_baseline
MISE_LOG="$TMP_ROOT/mise.log"; : > "$MISE_LOG"
OPENSPEC_LOG="$TMP_ROOT/openspec.log"; : > "$OPENSPEC_LOG"
write_baseline_mise_stub "$TMP_ROOT/fake-mise" "$MISE_LOG"
write_baseline_openspec_stub "$TMP_ROOT/fake-openspec" "$OPENSPEC_LOG"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="$TMP_ROOT/fake-openspec" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit
# The pre-existing audit_mise check (unrelated to comparison B) also uses the
# WTD_MISE_BIN seam and logs one "ls --current --no-header" line regardless
# of --probe; comparison B's own invocations are the "exec ..." lines, so
# their absence is what "plain audit invokes no probe stub" actually means.
assert_not_contains "plain audit invokes no comparison-B mise probe" "$(cat "$MISE_LOG")" "exec "
assert_eq "plain audit invokes no openspec probe stub" "$(cat "$OPENSPEC_LOG")" ""
assert_not_contains "plain audit reports no comparison-B findings" "$LAST_OUT" "TOOLKIT_INSTALLED_OK"
teardown_fixture

setup_fixture
setup_toolkit_baseline
MISE_LOG="$TMP_ROOT/mise.log"; : > "$MISE_LOG"
OPENSPEC_LOG="$TMP_ROOT/openspec.log"; : > "$OPENSPEC_LOG"
write_baseline_mise_stub "$TMP_ROOT/fake-mise" "$MISE_LOG"
write_baseline_openspec_stub "$TMP_ROOT/fake-openspec" "$OPENSPEC_LOG"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="$TMP_ROOT/fake-openspec" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
if [[ -s "$MISE_LOG" ]]; then pass "--probe invokes the mise probe stub (log non-empty)"
else fail "--probe invokes the mise probe stub (log non-empty)" "log was empty"; fi
if [[ -s "$OPENSPEC_LOG" ]]; then pass "--probe invokes the openspec probe stub (log non-empty)"
else fail "--probe invokes the openspec probe stub (log non-empty)" "log was empty"; fi
assert_contains "full agreement reports TOOLKIT_INSTALLED_OK" "$LAST_OUT" "TOOLKIT_INSTALLED_OK"
assert_not_contains "full agreement reports no drift" "$LAST_OUT" "TOOLKIT_DRIFT_INSTALLED"
assert_contains "a latest-pinned component (uv) is still probed" "$(cat "$MISE_LOG")" "exec -- uv --version"
teardown_fixture

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_contains "no receipt/probe advice becomes probe advice once readable" "$LAST_OUT" "TOOLKIT_INSTALLED_NOT_PROBED"
teardown_fixture

setup_fixture
setup_toolkit_baseline
receipt_skip_all_except "$TMP_ROOT/receipt.env" node
cat > "$TMP_ROOT/fake-mise" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "exec -- node --version") printf 'v22.0.0\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP_ROOT/fake-mise"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_contains "a changed probe result is drift" "$LAST_OUT" "TOOLKIT_DRIFT_INSTALLED"
assert_contains "the drift finding names both values" "$LAST_OUT" "Installed 24.8.1 but the machine now reports 22.0.0."
teardown_fixture

setup_fixture
setup_toolkit_baseline
receipt_skip_all_except "$TMP_ROOT/receipt.env" node
write_baseline_mise_stub "$TMP_ROOT/fake-mise" "$TMP_ROOT/mise.log"
write_timeout_stub_always_times_out "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_contains "a timeout is reported, not a failure" "$LAST_OUT" "TOOLKIT_PROBE_TIMEOUT"
assert_contains "a timeout does not abort the audit" "$LAST_OUT" "PATH_"
assert_not_contains "a timeout is never FAIL" "$LAST_OUT" "FAIL  TOOLKIT_"
teardown_fixture

setup_fixture
setup_toolkit_baseline
receipt_skip_all_except "$TMP_ROOT/receipt.env" java-17 pyyaml
cat > "$TMP_ROOT/fake-mise" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "exec java@temurin-17"*) exit 1 ;;
  "exec -- python -c"*) printf '6.0.2\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP_ROOT/fake-mise"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_contains "an earlier failing probe is reported" "$LAST_OUT" "TOOLKIT_PROBE_UNAVAILABLE"
assert_contains "a later probe still runs and agrees" "$LAST_OUT" "TOOLKIT_INSTALLED_OK"
teardown_fixture

setup_fixture
setup_toolkit_baseline
# node is deliberately excluded from "keep" -- it stays in skipped= -- while
# python is kept, so one run proves both halves: the skipped component's
# probe never fires, and a non-skipped component in the same run still does.
receipt_skip_all_except "$TMP_ROOT/receipt.env" python
NODE_LOG="$TMP_ROOT/mise.log"; : > "$NODE_LOG"
write_baseline_mise_stub "$TMP_ROOT/fake-mise" "$NODE_LOG"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_not_contains "a skipped= component is never probed" "$(cat "$NODE_LOG")" "exec -- node --version"
assert_contains "a non-skipped component in the same run is still probed" "$(cat "$NODE_LOG")" "exec -- python --version"
teardown_fixture

setup_fixture
write_test_catalog "$TMP_ROOT/catalog.env"
MISE_LOG="$TMP_ROOT/mise.log"; : > "$MISE_LOG"
OPENSPEC_LOG="$TMP_ROOT/openspec.log"; : > "$OPENSPEC_LOG"
write_baseline_mise_stub "$TMP_ROOT/fake-mise" "$MISE_LOG"
write_baseline_openspec_stub "$TMP_ROOT/fake-openspec" "$OPENSPEC_LOG"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="$TMP_ROOT/fake-mise" WTD_TEST_OPENSPEC_BIN="$TMP_ROOT/fake-openspec" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_contains "no receipt is still informational under --probe" "$LAST_OUT" "TOOLKIT_NOT_PROVISIONED"
# As above: the pre-existing audit_mise check logs its own unrelated
# "ls --current --no-header" line regardless of the receipt; comparison B's
# own invocations are the "exec ..." lines.
assert_not_contains "no receipt invokes no comparison-B mise probe" "$(cat "$MISE_LOG")" "exec "
assert_eq "no receipt invokes no openspec probe stub" "$(cat "$OPENSPEC_LOG")" ""
teardown_fixture

setup_fixture
setup_toolkit_baseline
WTD_TEST_TIMEOUT_BIN="" run_doctor audit --probe
assert_contains "no resolvable timeout means B does not run" "$LAST_OUT" "TOOLKIT_PROBE_UNAVAILABLE"
assert_not_contains "no resolvable timeout reports no drift" "$LAST_OUT" "TOOLKIT_DRIFT_INSTALLED"
assert_not_contains "no resolvable timeout is never FAIL" "$LAST_OUT" "FAIL  TOOLKIT_"
teardown_fixture

setup_fixture
setup_toolkit_baseline
write_baseline_openspec_stub "$TMP_ROOT/fake-openspec" "$TMP_ROOT/openspec.log"
write_passthrough_timeout_stub "$TMP_ROOT/fake-timeout"
WTD_TEST_MISE_BIN="" WTD_TEST_OPENSPEC_BIN="$TMP_ROOT/fake-openspec" \
  WTD_TEST_TIMEOUT_BIN="$TMP_ROOT/fake-timeout" run_doctor audit --probe
assert_eq "no resolvable mise reports exactly one TOOLKIT_PROBE_UNAVAILABLE for mise" \
  "$(printf '%s\n' "$LAST_OUT" | grep -c 'TOOLKIT_PROBE_UNAVAILABLE *mise')" "1"
if [[ -s "$TMP_ROOT/openspec.log" ]]; then pass "the openspec probe still runs without mise"
else fail "the openspec probe still runs without mise" "log was empty"; fi
teardown_fixture

# --- Comparison C: catalog staleness ----------------------------------------

setup_fixture
setup_toolkit_baseline
sed -i 's/^node=24$/node=26/' "$TMP_ROOT/catalog.env"
run_doctor audit
assert_contains "a catalog ahead of the receipt is a stale pin" "$LAST_OUT" "TOOLKIT_STALE_PIN"
assert_contains "the stale pin names both values" "$LAST_OUT" "Requested 24 but the catalog now pins 26."
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i 's/^node=24$/node=26/' "$TMP_ROOT/catalog.env"
sed -i 's/^overridden=$/overridden=node/' "$TMP_ROOT/receipt.env"
run_doctor audit
assert_not_contains "an overridden stale pin produces no finding" "$LAST_OUT" "TOOLKIT_STALE_PIN"
teardown_fixture

setup_fixture
setup_toolkit_baseline
sed -i 's/^node=24$/node=26/' "$TMP_ROOT/catalog.env"
sed -i 's/^skipped=$/skipped=node/' "$TMP_ROOT/receipt.env"
run_doctor audit
assert_not_contains "a skipped stale pin produces no finding" "$LAST_OUT" "TOOLKIT_STALE_PIN"
teardown_fixture

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_contains "latest components are grouped as not comparable" "$LAST_OUT" "TOOLKIT_NOT_COMPARABLE"
assert_contains "the not-comparable finding names uv" "$LAST_OUT" "uv (latest)"
assert_eq "a latest component is never a stale pin" \
  "$(printf '%s\n' "$LAST_OUT" | grep -c 'TOOLKIT_STALE_PIN *uv' || true)" "0"
teardown_fixture

setup_fixture
setup_toolkit_baseline
printf 'brand-new-tool=1\n' >> "$TMP_ROOT/catalog.env"
run_doctor audit
assert_not_contains "a catalog key the receipt predates produces no finding" "$LAST_OUT" "brand-new-tool"
teardown_fixture

# --- Severity: no TOOLKIT_ finding is ever FAIL ------------------------------

setup_fixture
setup_toolkit_baseline
run_doctor audit
assert_not_contains "toolkit findings are never FAIL (plain audit)" "$LAST_OUT" "FAIL  TOOLKIT_"
teardown_fixture

setup_fixture
setup_toolkit_baseline
WTD_TEST_OPENSPEC_BIN="" WTD_TEST_TIMEOUT_BIN="" run_doctor audit --probe
assert_not_contains "toolkit findings are never FAIL (--probe)" "$LAST_OUT" "FAIL  TOOLKIT_"
teardown_fixture


printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
