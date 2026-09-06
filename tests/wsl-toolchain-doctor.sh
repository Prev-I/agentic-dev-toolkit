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
  LAST_OUT="$(env \
    -u MISE_SHELL \
    -u MISE_SESSION \
    WTD_ASSUME_WSL=1 \
    WTD_NO_COLOR=1 \
    WTD_WSL_CONF="$TMP_ROOT/wsl.conf" \
    WTD_MOUNTS_FILE="$TMP_ROOT/mounts" \
    WTD_WSL_INTEROP_FILE="$TMP_ROOT/wslinterop" \
    WTD_SCAN_PATH="${WTD_TEST_SCAN_PATH:-$TMP_ROOT/linux/bin}" \
    WTD_PROFILE_FILES="${WTD_TEST_PROFILE_FILES:-}" \
    WTD_MISE_BIN="${WTD_TEST_MISE_BIN:-}" \
    WTD_MISE_ACTIVATED="${WTD_TEST_MISE_ACTIVATED:-}" \
    WTD_FAKE_MISE_JAVA="${WTD_FAKE_MISE_JAVA:-}" \
    HOME="$TMP_ROOT/home" \
    bash "$SCRIPT" "$@" 2>&1)"
  LAST_RC=$?
  set -e
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
assert_contains "JSON audit exposes v0.3.0 tool version" "$LAST_OUT" '"toolVersion":"0.3.0"'
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
assert_eq "tool reports v0.3.0" "$LAST_RC" "0"
assert_eq "version string is exactly 0.3.0" "$LAST_OUT" "0.3.0"
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

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
