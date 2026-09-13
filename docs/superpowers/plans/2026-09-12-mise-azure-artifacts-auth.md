# Unified Mise Azure Artifacts Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move host-side Maven and NuGet Azure Artifacts authentication to one PAT loaded globally by mise, prove both ecosystems and all harness boundaries from cold caches, then remove the superseded host credential copies.

**Architecture:** A standalone toolkit configurator writes one mode-`0600` PAT file and one non-secret global mise fragment. Mise derives the Maven, devcontainer-compatible, and source-specific NuGet variables for every `mise exec` child; Maven's user settings retains only `${env.AZDO_MAVEN_PAT}`, while NuGet takes its higher-precedence source credentials directly from the mise environment. CI and devcontainer refactors are deliberately deferred until a separate cross-repository qualification plan.

**Tech Stack:** Bash, mise 2026.8+, dotenv, TOML, Maven 3.9.16, Java 17/21, .NET 8/10, NuGet, Azure Artifacts, Python 3 stdlib XML handling, ShellCheck.

**Spec:** `/home/previtalicl/code/spec-driven-dev/checkouts/agentic-dev-toolkit/docs/superpowers/specs/2026-09-12-mise-azure-artifacts-auth-design.md`

## Global Constraints

- Store exactly one PAT value in `~/.config/mise/secrets/azure-artifacts.env`.
- Secret directory mode is `0700`; secret file mode is `0600`.
- PAT scope is Azure DevOps organization `gewiss-resel`, Packaging Read only, with the shortest practical expiry.
- Never put a PAT in Git, command arguments, stdout/stderr, logs, systemd units, Maven settings, NuGet config, or generated effective-settings output.
- Mise derives `AZDO_MAVEN_PAT`, `AZDO_NUGET_PAT`, `NuGetPackageSourceCredentials_JoinOn`, and `NuGetPackageSourceCredentials_Foundation` from `AZDO_ARTIFACTS_PAT`.
- NuGet source-name spelling and case are exactly `JoinOn` and `Foundation`.
- Maven server ID is exactly `Foundation`.
- Host commands continue to use `~/.local/bin/mise exec -- mvn ...` and `~/.local/bin/mise exec -- dotnet ...`.
- Do not remove or modify Azure Pipelines authentication in this plan.
- Do not remove or modify tracked devcontainer authentication in this plan.
- Do not delete Git Credential Manager, Azure CLI/MSAL state, the Microsoft Azure Artifacts Credential Provider, OpenCode runtime secrets, or normal Maven/NuGet caches.
- Preserve unrelated existing work. The target toolkit repository currently has a pre-existing modification in `tests/install.sh`; inspect and integrate around it rather than reverting it.
- Do not commit or push unless the user explicitly requests it during execution.

---

## File Structure

### `agentic-dev-toolkit`

- Create `azure-artifacts/configure.sh`: safe interactive/non-interactive configurator, verifier, Maven settings migration, backup/rollback metadata, and dry-run interface.
- Create `tests/azure-artifacts.sh`: isolated-HOME behavioral suite with fake mise, Maven settings fixtures, output leak checks, permissions checks, and rollback checks.
- Modify `AGENTS.md`: document the component, test command, and credential-safety rules.
- Modify `README.md`: document setup, verification, rotation, rollback, work testing, and the deferred CI/devcontainer boundary.
- Existing `environments/linux/install.sh` and `tests/install.sh`: no change. Azure credentials are opt-in and security-sensitive; the general installer must not prompt for or provision a PAT implicitly.

### Live user home during migration

- Create `~/.config/mise/secrets/azure-artifacts.env`: one PAT assignment only.
- Create `~/.config/mise/conf.d/azure-artifacts.toml`: non-secret loader, derived variables, and redaction declarations.
- Replace symlink `~/.m2/settings.xml` with a regular, non-secret WSL file referencing `${env.AZDO_MAVEN_PAT}`.
- Create temporary rollback path `~/.m2/settings.xml.pre-mise-azure-artifacts`; preserve a symlink as a symlink rather than copying its plaintext target.

### Live Joinon workspace during cleanup

- Modify ignored `joinon-foundation/env.local`: remove only `VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` after all work tests pass; keep PostgreSQL, Elasticsearch, Kubernetes, and other unrelated values.
- Modify `joinon-foundation/env.example`: remove the now-obsolete workspace NuGet PAT example after all work tests pass.
- No product checkout is modified by this plan.

---

### Task 1: Add Secure Mise Configuration Generation

**Files:**
- Create: `azure-artifacts/configure.sh`
- Create: `tests/azure-artifacts.sh`

**Interfaces:**
- Consumes: `HOME`, `MISE_BIN` (default `$HOME/.local/bin/mise`), optional test-only path overrides `AZDO_AUTH_SECRET_FILE`, `AZDO_AUTH_MISE_CONFIG`, and `AZDO_AUTH_MAVEN_SETTINGS`.
- Produces: `render_mise_config() -> stdout`, `write_secret_file(PAT)`, CLI modes `--dry-run`, `--verify-only`, and `--pat-stdin`.

- [ ] **Step 1: Add failing tests for the one-secret file and derived mise configuration**

In `tests/azure-artifacts.sh`, create an isolated HOME and source the configurator without running `main` using the same final-line convention as `tests/install.sh`. Add tests that assert:

```bash
test_secret_file_contains_one_assignment() {
  local pat='syntheticAzureArtifactsPat123'
  write_secret_file "$pat"

  assert_equal "$(wc -l < "$AZDO_AUTH_SECRET_FILE")" "1" \
    "secret file must contain exactly one assignment"
  grep -qx 'AZDO_ARTIFACTS_PAT=syntheticAzureArtifactsPat123' "$AZDO_AUTH_SECRET_FILE" \
    || fail "secret file must contain only the canonical PAT variable"
  assert_equal "$(stat -c '%a' "$(dirname "$AZDO_AUTH_SECRET_FILE")")" "700" \
    "secret directory mode"
  assert_equal "$(stat -c '%a' "$AZDO_AUTH_SECRET_FILE")" "600" \
    "secret file mode"
}

test_mise_config_derives_all_consumers_without_embedding_pat() {
  local config
  config="$(render_mise_config)"
  grep -q 'AZDO_MAVEN_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"' <<<"$config" \
    || fail "mise config must derive Maven auth"
  grep -q 'AZDO_NUGET_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"' <<<"$config" \
    || fail "mise config must preserve the devcontainer-compatible NuGet name"
  grep -q 'NuGetPackageSourceCredentials_JoinOn' <<<"$config" \
    || fail "mise config must derive JoinOn credentials"
  grep -q 'NuGetPackageSourceCredentials_Foundation' <<<"$config" \
    || fail "mise config must derive Foundation credentials"
  [[ "$config" != *syntheticAzureArtifactsPat123* ]] \
    || fail "mise config must never embed the PAT"
}
```

Also assert that `redactions` includes all five names/patterns and that the configured secret path is `{{env.HOME}}/.config/mise/secrets/azure-artifacts.env`.

- [ ] **Step 2: Run the new suite and confirm the expected failure**

Run:

```bash
bash tests/azure-artifacts.sh
```

Expected: FAIL because `azure-artifacts/configure.sh`, `write_secret_file`, and `render_mise_config` do not exist.

- [ ] **Step 3: Implement minimal secure rendering and writing**

Create `azure-artifacts/configure.sh` with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
AZDO_AUTH_SECRET_FILE="${AZDO_AUTH_SECRET_FILE:-$HOME/.config/mise/secrets/azure-artifacts.env}"
AZDO_AUTH_MISE_CONFIG="${AZDO_AUTH_MISE_CONFIG:-$HOME/.config/mise/conf.d/azure-artifacts.toml}"
AZDO_AUTH_MAVEN_SETTINGS="${AZDO_AUTH_MAVEN_SETTINGS:-$HOME/.m2/settings.xml}"

render_mise_config() {
  cat <<'EOF_MISE'
redactions = [
  "AZDO_ARTIFACTS_PAT",
  "AZDO_MAVEN_PAT",
  "AZDO_NUGET_PAT",
  "NuGetPackageSourceCredentials_*",
]

[env]
_.file = { path = "{{env.HOME}}/.config/mise/secrets/azure-artifacts.env", redact = true }
AZDO_MAVEN_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"
AZDO_NUGET_PAT = "{{env.AZDO_ARTIFACTS_PAT}}"
NuGetPackageSourceCredentials_JoinOn = "Username=gewiss-resel;Password={{env.AZDO_ARTIFACTS_PAT}};ValidAuthenticationTypes=Basic"
NuGetPackageSourceCredentials_Foundation = "Username=gewiss-resel;Password={{env.AZDO_ARTIFACTS_PAT}};ValidAuthenticationTypes=Basic"
EOF_MISE
}

write_secret_file() {
  local pat=$1 dir tmp
  [[ "$pat" =~ ^[A-Za-z0-9]+$ ]] || die "PAT must be a non-empty Azure DevOps token containing only letters and digits"
  dir="$(dirname "$AZDO_AUTH_SECRET_FILE")"
  install -d -m 700 "$dir"
  tmp="$(mktemp "$dir/.azure-artifacts.env.XXXXXX")"
  chmod 600 "$tmp"
  printf 'AZDO_ARTIFACTS_PAT=%s\n' "$pat" > "$tmp"
  mv -f "$tmp" "$AZDO_AUTH_SECRET_FILE"
}
```

Add `die`, `usage`, argument parsing, and a final `main "$@"` line. Default mode reads from `/dev/tty` with `read -rsp`; `--pat-stdin` reads one line from stdin for tests and controlled automation. Neither mode prints the value.

Write the mise fragment atomically with mode `0644`; it contains no secret. `--dry-run` reports paths/actions only. `--verify-only` does not ask for a PAT.

- [ ] **Step 4: Run the focused suite**

Run:

```bash
bash tests/azure-artifacts.sh
bash -n azure-artifacts/configure.sh
shellcheck azure-artifacts/configure.sh tests/azure-artifacts.sh
```

Expected: PASS. Test output must not contain `syntheticAzureArtifactsPat123`.

- [ ] **Step 5: Check the task diff**

Run:

```bash
git diff --check -- azure-artifacts/configure.sh tests/azure-artifacts.sh
git diff -- azure-artifacts/configure.sh tests/azure-artifacts.sh
```

Expected: only the new component and its tests; no credential values.

---

### Task 2: Add Safe Maven Settings Migration And Rollback

**Files:**
- Modify: `azure-artifacts/configure.sh`
- Modify: `tests/azure-artifacts.sh`

**Interfaces:**
- Consumes: the Task 1 paths and `MISE_BIN`.
- Produces: `configure_maven_settings()`, `verify_configuration()`, and rollback path `${AZDO_AUTH_MAVEN_SETTINGS}.pre-mise-azure-artifacts`.

- [ ] **Step 1: Add failing tests for regular files, symlinks, preservation, and idempotency**

Add fixtures and assertions for:

```bash
test_maven_migration_preserves_unrelated_settings() {
  # Fixture contains one unrelated mirror/profile and no Foundation server.
  configure_maven_settings
  assert_xml_has_server Foundation '${env.AZDO_MAVEN_PAT}'
  assert_xml_has_mirror corporate-mirror
}

test_maven_symlink_backup_remains_a_symlink() {
  ln -s "$TEMP_DIR/windows-settings.xml" "$AZDO_AUTH_MAVEN_SETTINGS"
  configure_maven_settings
  [[ -f "$AZDO_AUTH_MAVEN_SETTINGS" && ! -L "$AZDO_AUTH_MAVEN_SETTINGS" ]] \
    || fail "active Maven settings must become a regular WSL file"
  [[ -L "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts" ]] \
    || fail "symlink rollback must not copy plaintext target contents"
}

test_maven_migration_is_idempotent() {
  configure_maven_settings
  local first
  first="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  configure_maven_settings
  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$first" \
    "second migration must not change Maven settings"
}
```

Also assert mode `0600`, username `gewiss-resel`, exactly one `Foundation` server,
no synthetic PAT in active settings or the mise TOML, and no overwrite of an existing
rollback path.

- [ ] **Step 2: Run the suite and confirm failure**

Run:

```bash
bash tests/azure-artifacts.sh
```

Expected: FAIL because Maven migration is not implemented.

- [ ] **Step 3: Implement the XML-preserving Maven migration**

In `configure_maven_settings()`:

1. Create `~/.m2` with mode `0700` if absent.
2. If the active settings exists and rollback does not:
   - symlink: create the rollback as the same symlink target with `ln -s`;
   - regular file: copy it with mode `0600`.
3. Use `"$MISE_BIN" exec -- python` and `xml.etree.ElementTree` to parse the dereferenced active settings, preserve unrelated root sections, create/update `<servers>`, remove duplicate `Foundation` servers, and write exactly:

```xml
<server>
  <id>Foundation</id>
  <username>gewiss-resel</username>
  <password>${env.AZDO_MAVEN_PAT}</password>
</server>
```

4. Write to a mode-`0600` temporary file in `~/.m2`, parse it once more, then atomically rename it over the active settings path. Renaming replaces the symlink itself, not its Windows target.

The Python code must not inspect or receive the PAT. Its only secret-related value is the literal string `${env.AZDO_MAVEN_PAT}`.

- [ ] **Step 4: Implement structural verification**

`verify_configuration()` must:

```bash
[[ "$(stat -c '%a' "$(dirname "$AZDO_AUTH_SECRET_FILE")")" == 700 ]]
[[ "$(stat -c '%a' "$AZDO_AUTH_SECRET_FILE")" == 600 ]]
[[ -f "$AZDO_AUTH_MISE_CONFIG" ]]
[[ -f "$AZDO_AUTH_MAVEN_SETTINGS" && ! -L "$AZDO_AUTH_MAVEN_SETTINGS" ]]
```

Then invoke mise without displaying values:

```bash
"$MISE_BIN" exec -- sh -c '
  test -n "$AZDO_ARTIFACTS_PAT"
  test "$AZDO_MAVEN_PAT" = "$AZDO_ARTIFACTS_PAT"
  test "$AZDO_NUGET_PAT" = "$AZDO_ARTIFACTS_PAT"
  case "$NuGetPackageSourceCredentials_JoinOn" in
    Username=gewiss-resel\;Password=*\;ValidAuthenticationTypes=Basic) ;;
    *) exit 1 ;;
  esac
  case "$NuGetPackageSourceCredentials_Foundation" in
    Username=gewiss-resel\;Password=*\;ValidAuthenticationTypes=Basic) ;;
    *) exit 1 ;;
  esac
'
```

Parse Maven settings structurally with Python and report only `PASS` or a path-based diagnostic.

- [ ] **Step 5: Run focused verification**

Run:

```bash
bash tests/azure-artifacts.sh
bash -n azure-artifacts/configure.sh
shellcheck azure-artifacts/configure.sh tests/azure-artifacts.sh
```

Expected: PASS, no synthetic PAT in output.

---

### Task 3: Document The Component And Its Security Boundary

**Files:**
- Modify: `AGENTS.md:16-37,44-70,210-235`
- Modify: `README.md:139-180`
- Modify: `azure-artifacts/configure.sh`
- Modify: `tests/azure-artifacts.sh`

**Interfaces:**
- Consumes: Task 1-2 CLI and paths.
- Produces: discoverable setup/rotation/verification/rollback instructions and accurate maintainer guidance.

- [ ] **Step 1: Add failing documentation contract tests**

Add tests that require `README.md` and `AGENTS.md` to mention:

```text
azure-artifacts/configure.sh
~/.config/mise/secrets/azure-artifacts.env
~/.config/mise/conf.d/azure-artifacts.toml
${env.AZDO_MAVEN_PAT}
NuGetPackageSourceCredentials_JoinOn
NuGetPackageSourceCredentials_Foundation
Packaging Read
```

Assert both docs state that CI and devcontainers are outside the host migration and that real PATs never belong in Git.

- [ ] **Step 2: Run the suite and confirm documentation tests fail**

Run:

```bash
bash tests/azure-artifacts.sh
```

Expected: FAIL on missing documentation contracts.

- [ ] **Step 3: Update README and AGENTS**

In `README.md`, add a concise `Azure Artifacts through mise` section with:

```bash
./azure-artifacts/configure.sh
./azure-artifacts/configure.sh --verify-only
~/.local/bin/mise exec -- mvn -version
~/.local/bin/mise exec -- dotnet --info
```

Document rotation as rerunning the configurator with a new Packaging Read PAT.
Document rollback as restoring `~/.m2/settings.xml.pre-mise-azure-artifacts`, disabling
the mise fragment, and starting a fresh process. State that direct `mise env`, `env`, and
verbose dumps can expose values and must not be used in support transcripts.

In `AGENTS.md`, add the component to the repository layout, add
`bash tests/azure-artifacts.sh` to Build and Test, and state:

- mise owns host credential injection;
- Maven/NuGet files contain references only;
- CI and devcontainers retain independent auth until separately qualified;
- no test may print a real or synthetic PAT.

- [ ] **Step 4: Add safe CLI help and summary text**

Ensure `configure.sh --help` names all paths, modes, and commands but contains no
example PAT. A successful configure prints only:

```text
Configured Azure Artifacts authentication through mise.
Run azure-artifacts/configure.sh --verify-only to verify structure.
Run the cold-cache work tests before removing legacy credentials.
```

- [ ] **Step 5: Run component and repository checks**

Run:

```bash
bash tests/azure-artifacts.sh
bash tests/install.sh
bash -n azure-artifacts/configure.sh environments/linux/install.sh
shellcheck azure-artifacts/configure.sh tests/azure-artifacts.sh \
  environments/linux/install.sh tests/install.sh
git diff --check
```

Expected: all pass. Preserve the pre-existing `tests/install.sh` work; do not overwrite or reformat unrelated sections.

---

### Task 4: Install The Live Mise Authentication With A Rotated PAT

**Files:**
- Create outside Git: `~/.config/mise/secrets/azure-artifacts.env`
- Create outside Git: `~/.config/mise/conf.d/azure-artifacts.toml`
- Replace outside Git: `~/.m2/settings.xml`
- Create temporary rollback path: `~/.m2/settings.xml.pre-mise-azure-artifacts`

**Interfaces:**
- Consumes: a newly issued Azure DevOps Packaging Read PAT entered by the user at the terminal.
- Produces: live host authentication through global mise while old NuGet workspace auth remains available only for rollback.

- [ ] **Step 1: Inspect live paths without printing credentials**

Run:

```bash
stat -c '%F %a %U:%G %n' ~/.m2/settings.xml ~/.nuget/NuGet/NuGet.Config
readlink -f ~/.m2/settings.xml
test -e ~/.m2/settings.xml.pre-mise-azure-artifacts && echo 'rollback path already exists'
~/.local/bin/mise config ls
```

Expected: record current path types and stop if the rollback path already exists unexpectedly.

- [ ] **Step 2: Restrict exposed legacy secret files before migration**

Run:

```bash
chmod 600 /home/previtalicl/code/joinon-foundation/env.local
stat -c '%a %U:%G %n' /home/previtalicl/code/joinon-foundation/env.local
```

Expected: `600 previtalicl:previtalicl`. Do not read the file contents.

- [ ] **Step 3: Create a replacement PAT interactively**

The user creates or rotates a PAT at:

```text
https://dev.azure.com/gewiss-resel/_usersSettings/tokens
```

Required scope: Packaging Read only. Do not paste it into chat, a task prompt, shell history, or a command argument.

- [ ] **Step 4: Run the configurator from a controlling terminal**

Run:

```bash
./azure-artifacts/configure.sh
./azure-artifacts/configure.sh --verify-only
```

Expected: both commands report success without printing any credential value.

- [ ] **Step 5: Verify live structure without values**

Run:

```bash
stat -c '%a %U:%G %n' \
  ~/.config/mise/secrets \
  ~/.config/mise/secrets/azure-artifacts.env \
  ~/.config/mise/conf.d/azure-artifacts.toml \
  ~/.m2/settings.xml

test ! -L ~/.m2/settings.xml
~/.local/bin/mise exec -- sh -c '
  for name in AZDO_ARTIFACTS_PAT AZDO_MAVEN_PAT AZDO_NUGET_PAT \
    NuGetPackageSourceCredentials_JoinOn \
    NuGetPackageSourceCredentials_Foundation; do
    eval "test -n \"\${$name:-}\"" || exit 1
  done
  echo "all Azure Artifacts variables are set"
'
```

Expected: secret directory/file `700/600`, Maven settings `600`, and presence-only PASS.

---

### Task 5: Run Cold-Cache Maven, NuGet, And Harness Work Tests

**Files:**
- No tracked files.
- Temporary evidence: `/tmp/opencode/azure-artifacts-work-test/` with credential-free logs only.

**Interfaces:**
- Consumes: Task 4 live mise auth.
- Produces: go/no-go evidence for host duplicate removal.

- [ ] **Step 1: Create isolated cache roots and a secret-safe runner**

Run:

```bash
rm -rf /tmp/opencode/azure-artifacts-work-test
mkdir -p /tmp/opencode/azure-artifacts-work-test/{m2,nuget,http,logs}
chmod 700 /tmp/opencode/azure-artifacts-work-test
```

Every command in this task starts with:

```bash
env -u VSS_NUGET_EXTERNAL_FEED_ENDPOINTS \
    -u ARTIFACTS_CREDENTIALPROVIDER_EXTERNAL_FEED_ENDPOINTS \
    ~/.local/bin/mise exec --
```

This strips the old workspace provider path before mise injects the new source-specific credentials.

- [ ] **Step 2: Prove Maven from clean caches**

Run each command with a distinct temporary repository and capture normal build output only:

```bash
env -u VSS_NUGET_EXTERNAL_FEED_ENDPOINTS \
  ~/.local/bin/mise exec -- mvn -B -ntp \
  -Dmaven.repo.local=/tmp/opencode/azure-artifacts-work-test/m2/api-rest \
  clean test
```

Working directory: `joinon-foundation/checkouts/foundation-api-rest`.

Repeat with the same command shape for:

```text
foundation-device-core       -> clean test
foundation-cloud-lib-java    -> clean test
foundation-cloud-parent-maven -> clean install
```

Expected: no HTTP 401/403; private `io.gewiss` artifacts download; tests/build pass or any pre-existing non-auth failure is recorded separately.

- [ ] **Step 3: Prove NuGet from clean caches**

For each service, use separate package and HTTP cache directories:

```bash
env -u VSS_NUGET_EXTERNAL_FEED_ENDPOINTS \
    -u ARTIFACTS_CREDENTIALPROVIDER_EXTERNAL_FEED_ENDPOINTS \
    NUGET_PACKAGES=/tmp/opencode/azure-artifacts-work-test/nuget/datalog \
    NUGET_HTTP_CACHE_PATH=/tmp/opencode/azure-artifacts-work-test/http/datalog \
    ~/.local/bin/mise exec -- dotnet restore src --no-cache --force --verbosity minimal

NUGET_PACKAGES=/tmp/opencode/azure-artifacts-work-test/nuget/datalog \
  ~/.local/bin/mise exec -- dotnet build src -c Release --no-restore
NUGET_PACKAGES=/tmp/opencode/azure-artifacts-work-test/nuget/datalog \
  ~/.local/bin/mise exec -- dotnet test src -c Release --no-restore
```

Working directory: `joinon-foundation/checkouts/joinon-datalog`.

Repeat for:

```text
joinon-rfid
joinon-recharge-session
```

For `foundation-cloud-lib-dotnet`, replace `src` with `Foundation.Cloud.Lib.sln`.

Expected: no `NU1301` or HTTP 401. Record pass/fail/skip counts and distinguish existing test failures from authentication failures.

- [ ] **Step 4: Prove harness-equivalent process boundaries**

From each harness, run without printing values:

```bash
~/.local/bin/mise exec -- sh -c '
  test -n "$AZDO_MAVEN_PAT"
  test -n "$NuGetPackageSourceCredentials_Foundation"
  echo PASS
'
```

Then run one fresh-cache Maven dependency resolution and one fresh-cache NuGet restore through:

1. Claude Code shell tool
2. Codex shell tool
3. OpenCode shell tool

Expected: all use `/home/previtalicl/.local/bin/mise`, the same HOME, and succeed without interactive prompts or harness-specific configuration.

- [ ] **Step 5: Run configuration and authentication negative controls**

Create a temporary HOME containing no mise auth fragment while reusing only the
existing tool installation and the non-secret tool manifest:

```bash
NEGATIVE_HOME=/tmp/opencode/azure-artifacts-work-test/negative-home
rm -rf "$NEGATIVE_HOME"
mkdir -p "$NEGATIVE_HOME"

env -i \
  HOME="$NEGATIVE_HOME" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  MISE_DATA_DIR=/home/previtalicl/.local/share/mise \
  MISE_CACHE_DIR="$NEGATIVE_HOME/.cache/mise" \
  MISE_GLOBAL_CONFIG_FILE=/home/previtalicl/.config/mise/conf.d/agentic-dev-toolkit.toml \
  /home/previtalicl/.local/bin/mise exec -- mvn \
    -s /home/previtalicl/.m2/settings.xml \
    -B -ntp \
    -Dmaven.repo.local=/tmp/opencode/azure-artifacts-work-test/m2/negative \
    dependency:go-offline
```

Working directory: `joinon-foundation/checkouts/foundation-api-rest`.

Run the NuGet control:

```bash
env -i \
  HOME="$NEGATIVE_HOME" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  MISE_DATA_DIR=/home/previtalicl/.local/share/mise \
  MISE_CACHE_DIR="$NEGATIVE_HOME/.cache/mise" \
  MISE_GLOBAL_CONFIG_FILE=/home/previtalicl/.config/mise/conf.d/agentic-dev-toolkit.toml \
  NUGET_PACKAGES=/tmp/opencode/azure-artifacts-work-test/nuget/negative \
  NUGET_HTTP_CACHE_PATH=/tmp/opencode/azure-artifacts-work-test/http/negative \
  /home/previtalicl/.local/bin/mise exec -- dotnet restore src \
    --no-cache --force --verbosity minimal
```

Working directory: `joinon-foundation/checkouts/joinon-datalog`.

Expected for the isolated-HOME commands: both fail during mise template evaluation.
Record them as configuration negatives only.

Then keep the real mise configuration and override only the last-hop credentials with
the literal test value `invalid`, using new empty caches. Maven must reach the
Foundation feed and fail HTTP 401. NuGet must fail `NU1301`/HTTP 401 for JoinOn, and
a Foundation-only probe must fail the Foundation endpoint the same way. These are the
authentication negatives.

Finally record value-free presence/absence for user NuGet credential sections,
the Microsoft Credential Provider session token, the MSAL cache, and NuGet's plugin
cache. If a persisted token cache exists, identify it as part of the credential
surface before cleanup; do not print or delete its content.

- [ ] **Step 6: Scan evidence for secret leakage**

Do not search using the PAT itself. Verify logs contain no credential-bearing variable assignments, Basic/Bearer authorization headers, `ClearTextPassword`, or provider JSON:

```bash
rg -n 'AZDO_ARTIFACTS_PAT=|AZDO_MAVEN_PAT=|AZDO_NUGET_PAT=|NuGetPackageSourceCredentials_.*=|Authorization: (Basic|Bearer)|ClearTextPassword|endpointCredentials' \
  /tmp/opencode/azure-artifacts-work-test/logs
```

Expected: no matches.

- [ ] **Step 7: Apply the cleanup gate**

Proceed to Task 6 only if:

- all four Maven gates resolved private packages without 401/403;
- all four NuGet gates restored private packages without `NU1301`/401;
- all three harness boundaries passed;
- negative controls failed authentication;
- no credential-like output was logged.

Otherwise restore the prior Maven settings path from rollback and keep legacy NuGet auth untouched.

---

### Task 6: Remove Confirmed Host Duplicates And Re-Verify

**Files:**
- Modify ignored live file: `/home/previtalicl/code/joinon-foundation/env.local`
- Modify tracked workspace template: `/home/previtalicl/code/joinon-foundation/env.example:58-59`
- Remove or sanitize outside Git: `/mnt/c/Users/previtalicl/.m2/settings.xml`
- Remove temporary rollback path after the rollback window: `~/.m2/settings.xml.pre-mise-azure-artifacts`

**Interfaces:**
- Consumes: Task 5 green evidence.
- Produces: one active host PAT copy under mise and a credential-free Maven/NuGet configuration surface.

- [ ] **Step 1: Remove only the obsolete NuGet line from `env.local`**

Delete the complete assignment without printing it. `apply_patch` is deliberately
not used here because a context diff would expose the live value. Preserve every
other line:

```bash
legacy_env=/home/previtalicl/code/joinon-foundation/env.local
backup=/tmp/opencode/azure-artifacts-work-test/env.local.pre-cleanup
filtered=/tmp/opencode/azure-artifacts-work-test/env.local.filtered
install -m 600 "$legacy_env" "$backup"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" == export\ VSS_NUGET_EXTERNAL_FEED_ENDPOINTS=* ]] || printf '%s\n' "$line"
done < "$legacy_env" > "$filtered"
install -m 600 "$filtered" "$legacy_env"
rm -f "$filtered"
```

Then verify names only:

```bash
if grep -q '^export VSS_NUGET_EXTERNAL_FEED_ENDPOINTS=' \
  /home/previtalicl/code/joinon-foundation/env.local; then
  echo 'legacy NuGet credential still present' >&2
  exit 1
fi
stat -c '%a %U:%G %n' /home/previtalicl/code/joinon-foundation/env.local
```

Expected: no matching variable and mode remains `600`.

- [ ] **Step 2: Remove the obsolete example from the Joinon workspace**

Delete the `# ---- Devops Artifact` section and its
`VSS_NUGET_EXTERNAL_FEED_ENDPOINTS` line from `env.example`. Replace it with a
credential-free note pointing to the toolkit's `azure-artifacts/configure.sh`.

Run:

```bash
git -C /home/previtalicl/code/joinon-foundation diff --check -- env.example
```

- [ ] **Step 3: Resolve the old Windows Maven settings copy**

The old symlink target contains the superseded plaintext PAT. Choose based on actual
Windows usage established during execution:

- If Windows-native Maven is not supported: delete the old Windows `settings.xml`
  after confirming the active WSL settings is a regular file.
- If Windows-native Maven is required: replace its password with an environment
  reference and configure the Windows process environment separately; do not copy the
  PAT back into the file.

Never leave the old plaintext PAT in place after the new PAT is active.

- [ ] **Step 4: Start fresh processes and repeat smoke tests**

Start new Claude Code and Codex sessions. Restart OpenCode only if needed to start a
fresh session; its `mise exec` command reads global mise configuration at invocation.
Run:

```bash
~/.local/bin/mise exec -- mvn -B -ntp \
  -Dmaven.repo.local=/tmp/opencode/azure-artifacts-work-test/m2/post-cleanup \
  dependency:go-offline

NUGET_PACKAGES=/tmp/opencode/azure-artifacts-work-test/nuget/post-cleanup \
NUGET_HTTP_CACHE_PATH=/tmp/opencode/azure-artifacts-work-test/http/post-cleanup \
  ~/.local/bin/mise exec -- dotnet restore src --no-cache --force --verbosity minimal
```

Use `foundation-api-rest` for Maven and `joinon-datalog` for NuGet. Expected: both pass with legacy workspace auth absent.

- [ ] **Step 5: Revoke the old PAT and expire rollback**

The initial migration reused the current PAT, so it is both the live mise credential
and the credential referenced by the rollback target. Do not revoke it yet. Instead:

1. Create a replacement Azure DevOps PAT with Packaging Read scope only.
2. Rerun `./azure-artifacts/configure.sh` and `--verify-only` with the replacement.
3. Repeat the post-cleanup cold Maven and NuGet smoke tests from Step 4.
4. Revoke the superseded PAT only after both smoke tests pass.
5. Resolve the Windows settings target as described in Step 3, then delete
   `~/.m2/settings.xml.pre-mise-azure-artifacts` after the rollback window closes.

This ordering is load-bearing: revoking before Step 2 would revoke the current live
mise credential and the rollback credential at the same time.

By 2026-09-14, either complete replacement-PAT rotation, smoke testing, and revocation, or roll back or stop using the exposed credential.
This is an operational deadline, not automatic enforcement.

- [ ] **Step 6: Record deferred cleanup inventory**

Create a follow-up design/plan rather than editing product repositories in this task.
It must cover:

- three .NET `packageSourceCredentials` placeholder blocks;
- three duplicated .NET pipeline substitution blocks;
- three .NET devcontainer token-injection scripts;
- eight Java devcontainer settings copies;
- the shared .NET library's source/credential-name mismatch and legacy endpoint;
- cold Dev Container rebuilds and branch/tag pipeline qualification.

Expected: no product checkout changes in this implementation plan.

---

### Task 7: Run Final Toolkit Verification And Review

**Files:**
- Review all tracked changes in `agentic-dev-toolkit`.
- Review `joinon-foundation/env.example` separately in its own repository.

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: final verified implementation and explicit list of deferred cross-repo cleanup.

- [ ] **Step 1: Run every toolkit suite required by AGENTS.md**

Run:

```bash
bash tests/install.sh
bash tests/repository-policy.sh
bash tests/wsl-toolchain-doctor.sh
bash tests/opencode-service.sh
bash tests/azure-artifacts.sh
bash models/routing/opencode/eval/run-tests.sh
```

Expected: all PASS.

- [ ] **Step 2: Run syntax, lint, and secret scans**

Run:

```bash
bash -n environments/linux/install.sh azure-artifacts/configure.sh
shellcheck environments/linux/install.sh tests/install.sh \
  tests/repository-policy.sh repository-policy/validate.sh \
  wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh \
  opencode-service/opencode-startup-ready.sh \
  opencode-service/opencode-gateway-restart.sh tests/opencode-service.sh \
  azure-artifacts/configure.sh tests/azure-artifacts.sh
~/.local/bin/mise exec -- gitleaks detect --no-banner --redact
git diff --check
```

Expected: all pass. Investigate any gitleaks finding; never add a broad allowlist for a real secret.

- [ ] **Step 3: Review independent repository state**

Run in `agentic-dev-toolkit`:

```bash
git status --short
git diff --stat
git diff
```

Run in `joinon-foundation`:

```bash
git status --short -- env.example docs/superpowers/specs docs/superpowers/plans
git diff --check -- env.example
git diff -- env.example
```

Expected: unrelated pre-existing changes remain untouched; no secret-bearing file is staged or shown.

- [ ] **Step 4: Request independent code review**

Use the `requesting-code-review` skill. The reviewer must check:

- no secret can reach output or arguments;
- setup is idempotent;
- symlink rollback does not copy plaintext;
- XML merge preserves unrelated Maven settings;
- mise derives all variables from one physical secret;
- cold-cache and negative-control evidence proves authentication rather than cache use;
- cleanup did not cross into CI/devcontainer behavior.

- [ ] **Step 5: Report completion without committing**

Report:

- exact tests and work-test outcomes;
- active non-secret config paths and secret path permissions;
- old PAT revocation status;
- whether Windows-native Maven remains supported;
- deferred repository/CI/devcontainer cleanup scope;
- both independent repository diffs.

Do not commit or push unless explicitly requested.
