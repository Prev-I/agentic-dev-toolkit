#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CONFIGURATOR="$REPOSITORY_ROOT/azure-artifacts/configure.sh"

resolve_mise_data_dir() {
  if [[ -n "${MISE_DATA_DIR:-}" ]]; then
    printf '%s\n' "$MISE_DATA_DIR"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    printf '%s/mise\n' "$XDG_DATA_HOME"
  else
    printf '%s/.local/share/mise\n' "${HOME:?HOME must be set before the test sandbox is created}"
  fi
}

ORIGINAL_HOME="${HOME:?HOME must be set before the test sandbox is created}"
ORIGINAL_MISE_DATA_DIR="$(resolve_mise_data_dir)"
if [[ -e "$ORIGINAL_MISE_DATA_DIR" ]]; then
  ORIGINAL_MISE_DATA_DIR_EXISTS=1
else
  ORIGINAL_MISE_DATA_DIR_EXISTS=0
fi
readonly ORIGINAL_HOME ORIGINAL_MISE_DATA_DIR ORIGINAL_MISE_DATA_DIR_EXISTS

cleanup() {
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

resolve_real_mise() {
  local mise_on_path

  if [[ -z "${REAL_MISE:-}" ]]; then
    if [[ -x "$ORIGINAL_HOME/.local/bin/mise" ]]; then
      REAL_MISE="$ORIGINAL_HOME/.local/bin/mise"
    else
      mise_on_path="$(command -v mise 2>/dev/null || true)"
      REAL_MISE="$mise_on_path"
    fi
  fi

  [[ -n "$REAL_MISE" && -x "$REAL_MISE" ]] || \
    fail "real Mise executable is unavailable: ${REAL_MISE:-unset}; set REAL_MISE to an executable mise binary"
  readonly REAL_MISE
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

test_mise_data_dir_resolution_prefers_explicit_then_xdg_then_home() {
  assert_equal "$(HOME=/home/fixture XDG_DATA_HOME=/xdg/data MISE_DATA_DIR=/explicit/data resolve_mise_data_dir)" \
    "/explicit/data" "MISE_DATA_DIR must take precedence"
  assert_equal "$(HOME=/home/fixture XDG_DATA_HOME=/xdg/data MISE_DATA_DIR='' resolve_mise_data_dir)" \
    "/xdg/data/mise" "XDG_DATA_HOME must supply the Mise data path"
  assert_equal "$(HOME=/home/fixture XDG_DATA_HOME='' MISE_DATA_DIR='' resolve_mise_data_dir)" \
    "/home/fixture/.local/share/mise" "HOME must supply the final Mise data-path fallback"
}

test_documentation_and_cli_contracts() {
  local component_documentation documentation document_path help required
  local -a required_documentation=()

  # shellcheck disable=SC2016,SC2088
  required_documentation=(
    'azure-artifacts/configure.sh'
    '~/.config/mise/secrets/azure-artifacts.env'
    '~/.config/mise/conf.d/azure-artifacts.toml'
    '${env.AZDO_MAVEN_PAT}'
    'NuGetPackageSourceCredentials_JoinOn'
    'NuGetPackageSourceCredentials_Foundation'
    'Packaging Read'
  )

  for required in "${required_documentation[@]}"; do
    for document_path in README.md AGENTS.md; do
      [[ "$(<"$REPOSITORY_ROOT/$document_path")" == *"$required"* ]] \
        || fail "$document_path must document $required"
    done
  done
  for document_path in README.md AGENTS.md; do
    documentation="$(<"$REPOSITORY_ROOT/$document_path")"
    documentation="${documentation//$'\n'/ }"
    [[ "$documentation" == *'CI and devcontainers'* && "$documentation" == *'outside the host migration'* ]] \
      || fail "$document_path must keep CI and devcontainers outside the host migration"
    [[ "${documentation,,}" == *'real pats never belong in git'* ]] \
      || fail "$document_path must prohibit real PATs in Git"
    [[ "$documentation" == *'~/.config/mise/conf.d/azure-artifacts.toml'* && "$documentation" == *'mv ~/.m2/settings.xml.pre-mise-azure-artifacts ~/.m2/settings.xml'* ]] \
      || fail "$document_path must give the symlink-preserving rollback paths"
    # shellcheck disable=SC2016
    [[ "$documentation" == *'If `~/.m2/settings.xml.pre-mise-azure-artifacts` exists'* && "$documentation" == *'If `~/.m2/settings.xml.pre-mise-azure-artifacts` does not exist'* ]] \
      || fail "$document_path must distinguish rollback-artifact and fresh-host rollback paths"
    # shellcheck disable=SC2016
    [[ "$documentation" == *'leave `~/.m2/settings.xml` absent'* && "$documentation" == *'secret file remains dormant'* ]] \
      || fail "$document_path must document the credential-free rollback path and dormant secret"
    [[ "$documentation" == *'fresh process'* && "$documentation" == *'cold Maven'* && "$documentation" == *'cold NuGet'* ]] \
      || fail "$document_path must require fresh-process cold Maven and NuGet rollback tests"
    [[ "${documentation,,}" == *'revoke the old pat'* && "${documentation,,}" == *'new pat passes verification'* ]] \
      || fail "$document_path must defer old PAT revocation until the replacement is proven"
    [[ "$documentation" == *'byte-preserved formatting'* && "$documentation" == *'DOCTYPE'* && "$documentation" != *'preserves byte-preserved formatting'* && "$documentation" != *'preserves byte-for-byte formatting'* && "$documentation" != *'byte-for-byte formatting is preserved'* && "$documentation" != *'formatting is preserved byte-for-byte'* ]] \
      || fail "$document_path must document formatting limits and DOCTYPE refusal"
  done

  # The stdin mode exists for a one-time migration or controlled automation, never normal use.
  for document_path in README.md AGENTS.md azure-artifacts/README.md; do
    documentation="$(<"$REPOSITORY_ROOT/$document_path")"
    documentation="${documentation//$'\n'/ }"
    [[ "$documentation" == *'--pat-stdin'* && "$documentation" == *'migration or controlled automation'* && "$documentation" == *'/dev/tty'* ]] \
      || fail "$document_path must limit --pat-stdin to migration or controlled automation"
  done

  local rollback_contract='Until a replacement PAT passes verification and cold-cache smoke tests'
  for document_path in \
    README.md \
    AGENTS.md \
    azure-artifacts/README.md \
    docs/superpowers/specs/2026-09-12-mise-azure-artifacts-auth-design.md \
    docs/superpowers/plans/2026-09-12-mise-azure-artifacts-auth.md; do
    documentation="$(<"$REPOSITORY_ROOT/$document_path")"
    [[ "$documentation" == *"$rollback_contract"* && \
      "$documentation" == *'remove or sanitize the plaintext Windows Maven settings target'* && \
      "$documentation" == *'rollback copy or symlink'* ]] \
      || fail "$document_path must document the evidence-gated exposed-PAT rollback window"
  done

  [[ -f "$REPOSITORY_ROOT/azure-artifacts/README.md" ]] \
    || fail "Azure Artifacts component must have a README"
  component_documentation="$(<"$REPOSITORY_ROOT/azure-artifacts/README.md")"
  # shellcheck disable=SC2016
  for required in \
    'opt-in organization-specific Gewiss adapter' \
    'gewiss-resel' \
    'https://pkgs.dev.azure.com/gewiss-resel/Foundation/_packaging/Foundation/maven/v1' \
    'server ID `Foundation`' \
    'source names `Foundation` and `JoinOn`' \
    'NuGetPackageSourceCredentials_Foundation' \
    'NuGetPackageSourceCredentials_JoinOn' \
    'Packaging Read'; do
    [[ "$component_documentation" == *"$required"* ]] \
      || fail "Azure Artifacts component README must document $required"
  done
  component_documentation="${component_documentation//$'\n'/ }"
  [[ "$component_documentation" == *'~/.config/mise/conf.d/azure-artifacts.toml'* && "$component_documentation" == *'mv ~/.m2/settings.xml.pre-mise-azure-artifacts ~/.m2/settings.xml'* ]] \
    || fail "Azure Artifacts component README must give the symlink-preserving rollback paths"
  # shellcheck disable=SC2016
  [[ "$component_documentation" == *'If `~/.m2/settings.xml.pre-mise-azure-artifacts` exists'* && "$component_documentation" == *'If `~/.m2/settings.xml.pre-mise-azure-artifacts` does not exist'* ]] \
    || fail "Azure Artifacts component README must distinguish rollback-artifact and fresh-host rollback paths"
  # shellcheck disable=SC2016
  [[ "$component_documentation" == *'leave `~/.m2/settings.xml` absent'* && "$component_documentation" == *'secret file remains dormant'* ]] \
    || fail "Azure Artifacts component README must document the credential-free rollback path and dormant secret"
  [[ "$component_documentation" == *'fresh process'* && "$component_documentation" == *'cold Maven'* && "$component_documentation" == *'cold NuGet'* ]] \
    || fail "Azure Artifacts component README must require fresh-process cold restore tests"
  [[ "${component_documentation,,}" == *'revoke the old pat'* && "${component_documentation,,}" == *'new pat passes verification'* ]] \
    || fail "Azure Artifacts component README must defer old PAT revocation until the replacement is proven"
  [[ "$component_documentation" == *'byte-preserved formatting'* && "$component_documentation" == *'DOCTYPE'* && "$component_documentation" != *'preserves byte-preserved formatting'* && "$component_documentation" != *'preserves byte-for-byte formatting'* && "$component_documentation" != *'byte-for-byte formatting is preserved'* && "$component_documentation" != *'formatting is preserved byte-for-byte'* ]] \
    || fail "Azure Artifacts component README must document formatting limits and DOCTYPE refusal"
  # shellcheck disable=SC2016 # Backticks and $HOME shorthand are required documentation literals.
  [[ "$component_documentation" == *'rollback object as credential-bearing'* && "$component_documentation" == *'mode `0700` on `~/.m2`'* ]] \
    || fail "Azure Artifacts component README must disclose rollback credential exposure and Maven directory mode"
  documentation="$(<"$REPOSITORY_ROOT/README.md")"
  [[ "$documentation" == *'    README.md                                      # Opt-in Gewiss Azure Artifacts adapter'* ]] \
    || fail "root README structure must include the exact Azure Artifacts README entry"
  [[ "$documentation" == *'[Azure Artifacts adapter](azure-artifacts/README.md)'* ]] \
    || fail "root README Azure section must link directly to the component README"
  [[ "$(<"$REPOSITORY_ROOT/AGENTS.md")" == *'azure-artifacts/README.md'* ]] \
    || fail "AGENTS layout must include Azure Artifacts component documentation"
  documentation="$(<"$REPOSITORY_ROOT/AGENTS.md")"
  # shellcheck disable=SC2016
  [[ "$documentation" == *'## Scope'* && "$documentation" == *'`azure-artifacts/` is the opt-in organization-specific Gewiss adapter'* ]] \
    || fail "AGENTS Scope must exempt the opt-in Azure Artifacts adapter"
  [[ "$documentation" == *'All seven suites are the current required set.'* && "$documentation" != *'transcribe them'* ]] \
    || fail "AGENTS must not claim routing evidence transcribes all seven suites"

  help="$(bash "$CONFIGURATOR" --help)"
  # shellcheck disable=SC2088
  for required in \
    '--dry-run' \
    '--verify-only' \
    '--pat-stdin' \
    '-h' \
    'Options:' \
    'azure-artifacts/configure.sh' \
    '~/.config/mise/secrets/azure-artifacts.env' \
    '~/.config/mise/conf.d/azure-artifacts.toml' \
    '~/.m2/settings.xml'; do
    [[ "$help" == *"$required"* ]] \
      || fail "configurator help must document $required"
  done
  [[ "$help" != *'PAT='* && "$help" != *'pat_'* ]] \
    || fail "configurator help must not contain a PAT example"
  [[ ! "$help" =~ [[:alnum:]]{20,} ]] \
    || fail "configurator help must not contain a long alphanumeric token-like example"
  help="$(tr -s '[:space:]' ' ' <<<"$help")"
  [[ "$help" == *'migration or controlled automation'* && "$help" == *'normal setup and rotation'* && "$help" == *'/dev/tty'* ]] \
    || fail "configurator help must limit --pat-stdin to migration or controlled automation"
}

test_successful_configuration_uses_required_summary() {
  local expected_summary

  setup_cli_sandbox configured-summary
  run_cli_with_input syntheticAzureArtifactsPat123 --pat-stdin
  expected_summary=$'Configured Azure Artifacts authentication through mise.\nRun azure-artifacts/configure.sh --verify-only to verify structure.\nRun the cold-cache work tests before removing legacy credentials.'
  assert_equal "$CLI_STATUS" "0" "configuration for the success summary"
  assert_equal "$CLI_OUTPUT" "$expected_summary" "successful configuration summary"
}

load_configurator_functions() {
  local -a configurator_lines
  local last_line

  mapfile -t configurator_lines < "$CONFIGURATOR"
  last_line="${configurator_lines[-1]}"
  [[ "$last_line" == 'main "$@"' ]] || fail "configurator entry point must remain the final line"
  unset 'configurator_lines[-1]'
  printf '%s\n' "${configurator_lines[@]}" > "$TEMP_DIR/configure-functions.sh"

  # The production script performs work through main; tests load only its functions.
  # shellcheck disable=SC1091
  source "$TEMP_DIR/configure-functions.sh"
}

write_fake_mise() {
  MISE_BIN="$TEMP_DIR/mise"
  cat > "$MISE_BIN" <<'EOF_MISE'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$1" == "exec" && "$2" == "--" ]] || exit 2
shift 2

secret_file="$HOME/.config/mise/secrets/azure-artifacts.env"
if [[ -f "$secret_file" ]]; then
  # The fixture models mise's dotenv loader without exposing its values.
  source "$secret_file"
  export AZDO_ARTIFACTS_PAT
  export AZDO_MAVEN_PAT="$AZDO_ARTIFACTS_PAT"
  export AZDO_NUGET_PAT="$AZDO_ARTIFACTS_PAT"
  export NuGetPackageSourceCredentials_JoinOn="Username=gewiss-resel;Password=$AZDO_ARTIFACTS_PAT;ValidAuthenticationTypes=Basic"
  export NuGetPackageSourceCredentials_Foundation="Username=gewiss-resel;Password=$AZDO_ARTIFACTS_PAT;ValidAuthenticationTypes=Basic"
fi

case "${MISE_TEST_BREAK:-}" in
  artifacts) unset AZDO_ARTIFACTS_PAT ;;
  maven) AZDO_MAVEN_PAT=incorrect ;;
  nuget) AZDO_NUGET_PAT=incorrect ;;
  joinon) NuGetPackageSourceCredentials_JoinOn=incorrect ;;
  foundation) NuGetPackageSourceCredentials_Foundation=incorrect ;;
esac

if [[ "$1" == "python" ]]; then
  shift
  command python3 "$@"
else
  "$@"
fi
EOF_MISE
  chmod 700 "$MISE_BIN"
  export MISE_BIN
}

reset_maven_fixture() {
  rm -rf "$HOME/.m2"
  install -d -m 700 "$HOME/.m2"
}

write_unrelated_maven_settings() {
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<?xml version="1.0" encoding="UTF-8"?>
<!-- leading settings comment -->
<?leading-settings processing?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <!-- retained settings comment -->
  <?retained-settings processing?>
  <mirrors>
    <mirror>
      <id>corporate-mirror</id>
      <url>https://packages.example.invalid/maven</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
  <profiles>
    <profile><id>corporate-profile</id></profile>
  </profiles>
</settings>
<!-- trailing settings comment -->
<?trailing-settings processing?>
EOF_SETTINGS
}

prepare_valid_configuration() {
  reset_maven_fixture
  write_secret_file syntheticAzureArtifactsPat123
  write_mise_config
  configure_maven_settings
}

assert_verification_fails_without_secret() {
  local output status=0

  output="$(verify_configuration 2>&1)" || status=$?
  [[ "$status" != "0" ]] || fail "verification must reject $1"
  case "$output" in
    "ERROR: Azure Artifacts secret directory must have mode 0700: "*|\
    "ERROR: Azure Artifacts secret file must have mode 0600: "*|\
    "ERROR: Azure Artifacts secret file must contain one canonical assignment: "*|\
    "ERROR: Azure Artifacts mise configuration is missing: "*|\
    "ERROR: Azure Artifacts mise configuration must have mode 0644: "*|\
    "ERROR: Azure Artifacts mise configuration must use canonical template references: "*|\
    "ERROR: Azure Artifacts Maven directory must have mode 0700: "*|\
    "ERROR: Azure Artifacts Maven settings must be a regular file: "*|\
    "ERROR: Azure Artifacts Maven settings must have mode 0600: "*|\
    "ERROR: Mise environment verification failed"|\
    "ERROR: Maven settings verification failed: "*)
      ;;
    *)
      fail "verification must use only a path-based or generic diagnostic for $1"
      ;;
  esac
  [[ "$output" != *syntheticAzureArtifactsPat123* ]] \
    || fail "verification must not print the PAT fixture for $1"
  [[ "$output" != *ParseError* ]] \
    || fail "verification must not print parser details for $1"
}

assert_xml_has_server() {
  local expected_id=$1
  local expected_password=$2

  python3 - "$AZDO_AUTH_MAVEN_SETTINGS" "$expected_id" "$expected_password" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, expected_id, expected_password = sys.argv[1:]
root = ET.parse(path).getroot()
namespace = root.tag.partition('}')[0][1:] if root.tag.startswith('{') else ''
tag = lambda name: f'{{{namespace}}}{name}' if namespace else name
servers = []
for section in root:
    if section.tag != tag('servers'):
        continue
    for server in section:
        if server.tag != tag('server'):
            continue
        if any(child.tag == tag('id') and child.text == expected_id for child in server):
            servers.append(server)
if len(servers) != 1:
    raise SystemExit(f'expected one {expected_id} server, found {len(servers)}')
values = {child.tag.rsplit('}', 1)[-1]: child.text for child in servers[0]}
if values.get('username') != 'gewiss-resel':
    raise SystemExit('Foundation server username differs')
if values.get('password') != expected_password:
    raise SystemExit('Foundation server password differs')
PY
}

assert_xml_has_mirror() {
  local expected_id=$1

  python3 - "$AZDO_AUTH_MAVEN_SETTINGS" "$expected_id" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, expected_id = sys.argv[1:]
root = ET.parse(path).getroot()
for element in root.iter():
    if element.tag.rsplit('}', 1)[-1] != 'mirror':
        continue
    if any(child.tag.rsplit('}', 1)[-1] == 'id' and child.text == expected_id for child in element):
        break
else:
    raise SystemExit(f'missing mirror {expected_id}')
PY
}

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

test_mise_config_redacts_pat_variables_and_nuget_credentials() {
  local config redactions name
  config="$(render_mise_config)"
  redactions="$(awk '/^redactions = \[$/,/^\]$/' <<<"$config")"

  for name in \
    'AZDO_ARTIFACTS_PAT' \
    'AZDO_MAVEN_PAT' \
    'AZDO_NUGET_PAT' \
    'NuGetPackageSourceCredentials_*'; do
    [[ "$redactions" == *"$name"* ]] || fail "mise config must redact $name"
  done
}

test_mise_config_uses_the_canonical_secret_path() {
  local config
  config="$(render_mise_config)"

  grep -q 'path = "{{env.HOME}}/.config/mise/secrets/azure-artifacts.env"' <<<"$config" \
    || fail "mise config must load the canonical secret path"
}

test_mise_config_is_written_atomically_without_a_secret() {
  local rendered="$TEMP_DIR/rendered-mise-config.toml"
  local pat='syntheticAzureArtifactsPat123'

  render_mise_config > "$rendered"
  write_mise_config

  cmp -s "$rendered" "$AZDO_AUTH_MISE_CONFIG" \
    || fail "written mise config must equal the renderer output"
  [[ -d "$(dirname "$AZDO_AUTH_MISE_CONFIG")" ]] \
    || fail "mise config parent directory must be created"
  assert_equal "$(stat -c '%a' "$AZDO_AUTH_MISE_CONFIG")" "644" \
    "mise config file mode"
  ! grep -qF "$pat" "$AZDO_AUTH_MISE_CONFIG" \
    || fail "written mise config must not contain the PAT fixture"
}

test_maven_migration_preserves_unrelated_settings() {
  local pat='syntheticAzureArtifactsPat123'

  reset_maven_fixture
  write_unrelated_maven_settings
  configure_maven_settings

  # shellcheck disable=SC2016
  assert_xml_has_server Foundation '${env.AZDO_MAVEN_PAT}'
  assert_xml_has_mirror corporate-mirror
  grep -q '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve the default settings namespace"
  grep -q '<!-- retained settings comment -->' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve comments"
  grep -q '<?retained-settings processing?>' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve processing instructions"
  grep -q '<!-- leading settings comment -->' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve leading comments"
  grep -q '<?leading-settings processing?>' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve leading processing instructions"
  grep -q '<!-- trailing settings comment -->' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve trailing comments"
  grep -q '<?trailing-settings processing?>' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve trailing processing instructions"
  assert_equal "$(stat -c '%a' "$AZDO_AUTH_MAVEN_SETTINGS")" "600" \
    "migrated Maven settings mode"
  ! grep -qF "$pat" "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "active Maven settings must not contain the PAT fixture"
  ! grep -qF "$pat" "$AZDO_AUTH_MISE_CONFIG" 2>/dev/null \
    || fail "mise configuration must not contain the PAT fixture"
}

test_maven_migration_repairs_parent_directory_mode_on_every_run() {
  reset_maven_fixture
  chmod 755 "$(dirname "$AZDO_AUTH_MAVEN_SETTINGS")"

  configure_maven_settings

  assert_equal "$(stat -c '%a' "$(dirname "$AZDO_AUTH_MAVEN_SETTINGS")")" "700" \
    "Maven parent directory mode must be repaired on every migration"
}

test_maven_migration_refuses_doctype_without_writing_or_backup() {
  local before output status=0

  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<!DOCTYPE settings SYSTEM "settings.dtd">
<settings/>
EOF_SETTINGS
  before="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  output="$(configure_maven_settings 2>&1)" || status=$?

  [[ "$status" != "0" ]] || fail "Maven migration must reject a DOCTYPE"
  assert_equal "$output" "ERROR: Could not migrate Maven settings: $AZDO_AUTH_MAVEN_SETTINGS" \
    "DOCTYPE rejection diagnostic"
  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$before" \
    "DOCTYPE rejection must not rewrite settings"
  [[ ! -e "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts" ]] \
    || fail "DOCTYPE rejection must not create a rollback copy"
}

test_maven_migration_refuses_plaintext_unrelated_server_password() {
  local before output status=0

  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers><server><id>other</id><password>opaqueFixturePassword</password></server></servers></settings>
EOF_SETTINGS
  before="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  output="$(configure_maven_settings 2>&1)" || status=$?

  [[ "$status" != "0" ]] || fail "Maven migration must reject plaintext unrelated passwords"
  assert_equal "$output" "ERROR: Could not migrate Maven settings for server other: $AZDO_AUTH_MAVEN_SETTINGS" \
    "plaintext-password rejection diagnostic"
  [[ "$output" != *opaqueFixturePassword* ]] \
    || fail "migration rejection must not print an unrelated password fixture"
  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$before" \
    "plaintext-password rejection must not rewrite settings"
  [[ ! -e "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts" ]] \
    || fail "plaintext-password rejection must not create a rollback copy"
}

test_maven_migration_accepts_encrypted_password_and_passphrase() {
  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers>
  <server><id>encrypted-password</id><password>{encryptedPassword}</password></server>
  <server><id>encrypted-passphrase</id><passphrase>{encryptedPassphrase}</passphrase><privateKey>/key/path</privateKey></server>
</servers></settings>
EOF_SETTINGS

  configure_maven_settings

  grep -q '{encryptedPassword}' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must retain encrypted passwords"
  grep -q '{encryptedPassphrase}' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must retain encrypted passphrases"
  grep -q '/key/path' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must retain private key paths"
}

test_maven_migration_accepts_multiline_wrapped_credentials() {
  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers>
  <server><id>wrapped-password</id><password>
    {encryptedPassword}
  </password></server>
  <server><id>wrapped-passphrase</id><passphrase>
    ${env.OTHER_PASSPHRASE}
  </passphrase></server>
</servers></settings>
EOF_SETTINGS

  configure_maven_settings

  grep -q '{encryptedPassword}' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must accept wrapped encrypted passwords"
  # shellcheck disable=SC2016
  grep -q '\${env.OTHER_PASSPHRASE}' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must accept wrapped environment passphrases"
}

test_maven_migration_preserves_envelope_with_a_fake_leading_root_tag() {
  local first

  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<!-- leading comment mentions <settings> but is not the root -->
<?leading-root processing?>
<settings><mirrors><mirror><id>corporate-mirror</id></mirror></mirrors></settings>
<!-- trailing comment -->
EOF_SETTINGS

  configure_maven_settings
  first="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  configure_maven_settings

  grep -q '<!-- leading comment mentions <settings> but is not the root -->' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve a leading fake root tag comment"
  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$first" \
    "fake-root envelope migration must be idempotent"
  python3 - "$AZDO_AUTH_MAVEN_SETTINGS" <<'PY'
import sys
import xml.etree.ElementTree as ET

ET.parse(sys.argv[1])
PY
}

test_maven_migration_refuses_plaintext_unrelated_server_passphrase() {
  local before output status=0

  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers><server><id>other</id><passphrase>opaquePassphraseFixture</passphrase><privateKey>/key/path</privateKey></server></servers></settings>
EOF_SETTINGS
  before="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  output="$(configure_maven_settings 2>&1)" || status=$?

  [[ "$status" != "0" ]] || fail "Maven migration must reject plaintext unrelated passphrases"
  assert_equal "$output" "ERROR: Could not migrate Maven settings for server other: $AZDO_AUTH_MAVEN_SETTINGS" \
    "plaintext-passphrase rejection diagnostic"
  [[ "$output" != *opaquePassphraseFixture* ]] \
    || fail "migration rejection must not print an unrelated passphrase fixture"
  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$before" \
    "plaintext-passphrase rejection must not rewrite settings"
  [[ ! -e "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts" ]] \
    || fail "plaintext-passphrase rejection must not create a rollback copy"
}

test_maven_migration_accepts_environment_referenced_unrelated_server_password() {
  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers><server><id>other</id><password>${env.OTHER_PASSWORD}</password></server></servers></settings>
EOF_SETTINGS

  configure_maven_settings

  # shellcheck disable=SC2016
  grep -q '\${env.OTHER_PASSWORD}' "$AZDO_AUTH_MAVEN_SETTINGS" \
    || fail "Maven migration must preserve environment-referenced unrelated passwords"
}

test_maven_migration_ignores_misplaced_and_wrong_namespace_foundation_servers() {
  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" xmlns:other="urn:other">
  <servers><server><other:id>Foundation</other:id></server></servers>
  <profiles><profile><servers><server><id>Foundation</id></server></servers></profile></profiles>
  <other:servers><other:server><other:id>Foundation</other:id></other:server></other:servers>
</settings>
EOF_SETTINGS

  configure_maven_settings

  # shellcheck disable=SC2016
  assert_xml_has_server Foundation '${env.AZDO_MAVEN_PAT}'
  verify_configuration >/dev/null
}

test_maven_regular_file_backup_preserves_original_settings() {
  local rollback="$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts"

  reset_maven_fixture
  write_unrelated_maven_settings
  configure_maven_settings

  assert_equal "$(stat -c '%a' "$rollback")" "600" "Maven rollback file mode"
  grep -q '<id>corporate-mirror</id>' "$rollback" \
    || fail "regular-file rollback must retain the original Maven settings"
  ! grep -q 'AZDO_MAVEN_PAT' "$rollback" \
    || fail "regular-file rollback must not contain migrated Maven settings"
}

test_maven_migration_replaces_duplicate_foundation_servers() {
  reset_maven_fixture
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings>
  <servers>
    <server><id>Foundation</id><username>old</username><password>old</password></server>
    <server><id>Foundation</id><username>older</username><password>older</password></server>
  </servers>
</settings>
EOF_SETTINGS

  configure_maven_settings

  # shellcheck disable=SC2016
  assert_xml_has_server Foundation '${env.AZDO_MAVEN_PAT}'
}

test_maven_symlink_backup_remains_a_symlink() {
  local windows_settings="$TEMP_DIR/windows-settings.xml"

  reset_maven_fixture
  write_unrelated_maven_settings
  mv "$AZDO_AUTH_MAVEN_SETTINGS" "$windows_settings"
  ln -s "$windows_settings" "$AZDO_AUTH_MAVEN_SETTINGS"
  configure_maven_settings

  [[ -f "$AZDO_AUTH_MAVEN_SETTINGS" && ! -L "$AZDO_AUTH_MAVEN_SETTINGS" ]] \
    || fail "active Maven settings must become a regular WSL file"
  [[ -L "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts" ]] \
    || fail "symlink rollback must not copy plaintext target contents"
  assert_equal "$(readlink "$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts")" \
    "$windows_settings" "symlink rollback target"
}

test_maven_migration_does_not_overwrite_an_existing_rollback() {
  local rollback="$AZDO_AUTH_MAVEN_SETTINGS.pre-mise-azure-artifacts"

  reset_maven_fixture
  write_unrelated_maven_settings
  printf 'preserve-existing-rollback\n' > "$rollback"
  configure_maven_settings

  grep -qx 'preserve-existing-rollback' "$rollback" \
    || fail "Maven migration must not overwrite an existing rollback path"
}

test_maven_envelope_preservation_is_idempotent() {
  local first

  reset_maven_fixture
  write_unrelated_maven_settings
  configure_maven_settings
  first="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  configure_maven_settings

  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$first" \
    "second envelope-preserving migration must not change Maven settings"
}

test_maven_symlink_migration_is_idempotent() {
  local windows_settings="$TEMP_DIR/windows-idempotent-settings.xml"
  local first

  reset_maven_fixture
  write_unrelated_maven_settings
  mv "$AZDO_AUTH_MAVEN_SETTINGS" "$windows_settings"
  ln -s "$windows_settings" "$AZDO_AUTH_MAVEN_SETTINGS"
  configure_maven_settings
  first="$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")"
  configure_maven_settings

  assert_equal "$(sha256sum "$AZDO_AUTH_MAVEN_SETTINGS")" "$first" \
    "second symlink-migrated settings update must not change Maven settings"
}

test_verify_configuration_checks_modes_mise_environment_and_maven_structure() {
  local pat='syntheticAzureArtifactsPat123'
  local output status=0

  reset_maven_fixture
  write_secret_file "$pat"
  write_mise_config
  configure_maven_settings
  output="$(verify_configuration 2>&1)" || status=$?

  assert_equal "$status" "0" "structural verification must succeed"
  assert_equal "$output" "PASS" "Maven structural verification output"
  ! grep -qF "$pat" <<<"$output" || fail "verification must not print the PAT fixture"
}

test_verify_configuration_rejects_secret_and_mise_template_tampering() {
  prepare_valid_configuration
  printf '%s\n%s\n' 'AZDO_ARTIFACTS_PAT=syntheticAzureArtifactsPat123' 'UNRELATED=fixture' > "$AZDO_AUTH_SECRET_FILE"
  assert_verification_fails_without_secret "a secret file with an extra assignment"

  prepare_valid_configuration
  printf '%s\n%s' 'AZDO_ARTIFACTS_PAT=syntheticAzureArtifactsPat123' 'UNRELATED=fixture' > "$AZDO_AUTH_SECRET_FILE"
  assert_verification_fails_without_secret \
    "a secret file with an extra assignment and no trailing newline"

  prepare_valid_configuration
  printf '%s\n' '[env]' > "$AZDO_AUTH_MISE_CONFIG"
  assert_verification_fails_without_secret "a mise configuration that omits canonical references"
}

test_verify_configuration_hides_malformed_maven_parser_output() {
  local pat='syntheticAzureArtifactsPat123'
  local output status=0

  reset_maven_fixture
  write_secret_file "$pat"
  write_mise_config
  printf '<settings>' > "$AZDO_AUTH_MAVEN_SETTINGS"
  chmod 600 "$AZDO_AUTH_MAVEN_SETTINGS"
  output="$(verify_configuration 2>&1)" || status=$?

  [[ "$status" != "0" ]] || fail "verification must reject malformed Maven settings"
  [[ "$output" == "ERROR: Maven settings verification failed: $AZDO_AUTH_MAVEN_SETTINGS" ]] \
    || fail "malformed Maven settings must have only a path-based diagnostic"
  [[ "$output" != *ParseError* ]] \
    || fail "Maven parser details must not reach verification output"
  ! grep -qF "$pat" <<<"$output" || fail "verification must not print the PAT fixture"
}

test_verify_configuration_rejects_a_doctype() {
  prepare_valid_configuration
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<!DOCTYPE settings SYSTEM "settings.dtd">
<settings><servers><server><id>Foundation</id><username>gewiss-resel</username><password>${env.AZDO_MAVEN_PAT}</password></server></servers></settings>
EOF_SETTINGS

  assert_verification_fails_without_secret "a Maven settings DOCTYPE"
}

test_verify_configuration_rejects_bad_modes_symlinks_and_maven_structure() {
  prepare_valid_configuration
  chmod 755 "$(dirname "$AZDO_AUTH_SECRET_FILE")"
  assert_verification_fails_without_secret "a secret directory with the wrong mode"

  prepare_valid_configuration
  chmod 644 "$AZDO_AUTH_SECRET_FILE"
  assert_verification_fails_without_secret "a secret file with the wrong mode"

  prepare_valid_configuration
  chmod 755 "$(dirname "$AZDO_AUTH_MAVEN_SETTINGS")"
  assert_verification_fails_without_secret "a Maven directory with the wrong mode"

  prepare_valid_configuration
  chmod 644 "$AZDO_AUTH_MAVEN_SETTINGS"
  assert_verification_fails_without_secret "a Maven settings file with the wrong mode"

  prepare_valid_configuration
  mv "$AZDO_AUTH_MAVEN_SETTINGS" "$TEMP_DIR/symlinked-settings.xml"
  ln -s "$TEMP_DIR/symlinked-settings.xml" "$AZDO_AUTH_MAVEN_SETTINGS"
  assert_verification_fails_without_secret "symlinked Maven settings"

  prepare_valid_configuration
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><profiles><profile><servers><server><id>Foundation</id><username>gewiss-resel</username><password>${env.AZDO_MAVEN_PAT}</password></server></servers></profile></profiles></settings>
EOF_SETTINGS
  assert_verification_fails_without_secret "a misplaced Foundation server"

  prepare_valid_configuration
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings xmlns:other="urn:other"><other:servers><other:server><other:id>Foundation</other:id><other:username>gewiss-resel</other:username><other:password>${env.AZDO_MAVEN_PAT}</other:password></other:server></other:servers></settings>
EOF_SETTINGS
  assert_verification_fails_without_secret "a wrong-namespace Foundation server"

  prepare_valid_configuration
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers><server><id>Foundation</id><username>wrong</username><password>${env.AZDO_MAVEN_PAT}</password></server></servers></settings>
EOF_SETTINGS
  assert_verification_fails_without_secret "a malformed Foundation server"

  prepare_valid_configuration
  rm "$AZDO_AUTH_MISE_CONFIG"
  assert_verification_fails_without_secret "a missing Mise configuration"

  prepare_valid_configuration
  chmod 600 "$AZDO_AUTH_MISE_CONFIG"
  assert_verification_fails_without_secret "a Mise configuration with the wrong mode"

  prepare_valid_configuration
  cat > "$AZDO_AUTH_MAVEN_SETTINGS" <<'EOF_SETTINGS'
<settings><servers>
  <server><id>Foundation</id><username>gewiss-resel</username><password>${env.AZDO_MAVEN_PAT}</password></server>
  <server><id>Foundation</id><username>gewiss-resel</username><password>${env.AZDO_MAVEN_PAT}</password></server>
</servers></settings>
EOF_SETTINGS
  assert_verification_fails_without_secret "duplicate direct Foundation servers"
}

test_cli_preflight_rejects_missing_mise_without_mutating_files() {
  local pat='syntheticAzureArtifactsPat123'
  local missing_mise="$TEMP_DIR/missing-mise"

  install -d -m 600 "$missing_mise"
  setup_cli_sandbox missing-mise-cli
  CLI_STATUS=0
  CLI_OUTPUT="$(printf '%s' "$pat" | env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$missing_mise" bash "$CONFIGURATOR" --pat-stdin 2>&1)" || CLI_STATUS=$?

  [[ "$CLI_STATUS" != "0" ]] || fail "missing Mise must fail preflight"
  assert_equal "$CLI_OUTPUT" "ERROR: Mise executable is unavailable: $missing_mise" \
    "missing Mise diagnostic"
  assert_cli_output_has_no_pat "$pat"
  [[ ! -e "$CLI_HOME/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "missing Mise preflight must not write a secret file"
  [[ ! -e "$CLI_HOME/.config/mise/conf.d/azure-artifacts.toml" ]] \
    || fail "missing Mise preflight must not write a Mise config"
  [[ ! -e "$CLI_HOME/.m2/settings.xml" ]] \
    || fail "missing Mise preflight must not write Maven settings"
}

test_cli_preflight_rejects_missing_python_without_mutating_files() {
  local pat='syntheticAzureArtifactsPat123'
  local no_python_mise="$TEMP_DIR/no-python-mise"

  cat > "$no_python_mise" <<'EOF_MISE'
#!/usr/bin/env bash
exit 1
EOF_MISE
  chmod 700 "$no_python_mise"
  setup_cli_sandbox missing-python
  CLI_STATUS=0
  CLI_OUTPUT="$(printf '%s' "$pat" | env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$no_python_mise" bash "$CONFIGURATOR" --pat-stdin 2>&1)" || CLI_STATUS=$?

  [[ "$CLI_STATUS" != "0" ]] || fail "missing Mise Python must fail preflight"
  assert_equal "$CLI_OUTPUT" "ERROR: Mise Python is unavailable: $no_python_mise" \
    "missing Mise Python diagnostic"
  assert_cli_output_has_no_pat "$pat"
  [[ ! -e "$CLI_HOME/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "missing Mise Python preflight must not write a secret file"
  [[ ! -e "$CLI_HOME/.config/mise/conf.d/azure-artifacts.toml" ]] \
    || fail "missing Mise Python preflight must not write a Mise config"
  [[ ! -e "$CLI_HOME/.m2/settings.xml" ]] \
    || fail "missing Mise Python preflight must not write Maven settings"
}

test_cli_preflight_rejects_invalid_maven_without_mutating_files() {
  local pat='syntheticAzureArtifactsPat123'
  local before

  setup_cli_sandbox invalid-maven-preflight
  install -d -m 700 "$CLI_HOME/.m2"
  printf '<settings>' > "$CLI_HOME/.m2/settings.xml"
  before="$(sha256sum "$CLI_HOME/.m2/settings.xml")"
  CLI_STATUS=0
  CLI_OUTPUT="$(printf '%s' "$pat" | env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$TEMP_DIR/mise" bash "$CONFIGURATOR" --pat-stdin 2>&1)" || CLI_STATUS=$?

  [[ "$CLI_STATUS" != "0" ]] || fail "invalid Maven settings must fail preflight"
  assert_equal "$CLI_OUTPUT" "ERROR: Maven settings preflight failed: $CLI_HOME/.m2/settings.xml" \
    "invalid Maven preflight diagnostic"
  assert_cli_output_has_no_pat "$pat"
  assert_equal "$(sha256sum "$CLI_HOME/.m2/settings.xml")" "$before" \
    "invalid Maven preflight must not rewrite settings"
  [[ ! -e "$CLI_HOME/.m2/settings.xml.pre-mise-azure-artifacts" ]] \
    || fail "invalid Maven preflight must not create a rollback copy"
  [[ ! -e "$CLI_HOME/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "invalid Maven preflight must not write a secret file"
  [[ ! -e "$CLI_HOME/.config/mise/conf.d/azure-artifacts.toml" ]] \
    || fail "invalid Maven preflight must not write a Mise config"
}

test_rendered_mise_config_loads_secret_and_rejects_missing_secret_with_actual_mise() {
  local actual_home="$TEMP_DIR/actual-mise-home"
  local actual_data="$TEMP_DIR/actual-mise-data"
  local actual_cache="$TEMP_DIR/actual-mise-cache"
  local actual_state="$TEMP_DIR/actual-mise-state"
  local original_data_before original_data_after
  local output status=0

  if (( ORIGINAL_MISE_DATA_DIR_EXISTS )); then
    # Check the original root's metadata only; do not recursively inspect user data.
    original_data_before="$(stat -c '%d:%i:%f:%s:%Y:%Z' "$ORIGINAL_MISE_DATA_DIR")"
  fi
  install -d -m 700 "$actual_home/.config/mise/conf.d" "$actual_home/.config/mise/secrets" \
    "$actual_data" "$actual_cache" "$actual_state"
  render_mise_config > "$actual_home/.config/mise/conf.d/azure-artifacts.toml"
  printf 'AZDO_ARTIFACTS_PAT=syntheticAzureArtifactsPat123\n' > "$actual_home/.config/mise/secrets/azure-artifacts.env"
  env -u MISE_CONFIG_DIR -u MISE_CONFIG_FILE -u MISE_GLOBAL_CONFIG_FILE -u MISE_STATE_DIR \
    HOME="$actual_home" XDG_CONFIG_HOME="$actual_home/.config" XDG_CACHE_HOME="$actual_cache" \
    XDG_DATA_HOME="$actual_data" XDG_STATE_HOME="$actual_state" MISE_DATA_DIR="$actual_data" \
    MISE_CACHE_DIR="$actual_cache" bash -c "cd \"\$1\"; shift; exec \"\$@\"" _ "$actual_home" \
    "$REAL_MISE" env --quiet --json > "$actual_home/env.json"
  python3 - "$actual_home/env.json" <<'PY'
import json
import sys

environment_path, = sys.argv[1:]
environment = json.load(open(environment_path, encoding='utf-8'))
pat = environment['AZDO_ARTIFACTS_PAT']
if environment['AZDO_MAVEN_PAT'] != pat or environment['AZDO_NUGET_PAT'] != pat:
    raise SystemExit(1)
for name in ('NuGetPackageSourceCredentials_JoinOn', 'NuGetPackageSourceCredentials_Foundation'):
    value = environment[name]
    if value != f'Username=gewiss-resel;Password={pat};ValidAuthenticationTypes=Basic':
        raise SystemExit(1)
PY
  rm "$actual_home/.config/mise/secrets/azure-artifacts.env"
  output="$(env -u MISE_CONFIG_DIR -u MISE_CONFIG_FILE -u MISE_GLOBAL_CONFIG_FILE -u MISE_STATE_DIR \
    HOME="$actual_home" XDG_CONFIG_HOME="$actual_home/.config" XDG_CACHE_HOME="$actual_cache" \
    XDG_DATA_HOME="$actual_data" XDG_STATE_HOME="$actual_state" MISE_DATA_DIR="$actual_data" \
    MISE_CACHE_DIR="$actual_cache" bash -c "cd \"\$1\"; shift; exec \"\$@\"" _ "$actual_home" \
    "$REAL_MISE" env --quiet 2>&1)" || status=$?
  [[ "$status" != "0" ]] || fail "actual Mise must reject the rendered config without its secret input"
  [[ "$output" != *syntheticAzureArtifactsPat123* ]] \
    || fail "actual Mise parse output must not contain the PAT fixture"
  [[ ! -e "$actual_home/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "actual Mise parsing must not create a missing secret file"
  if (( ORIGINAL_MISE_DATA_DIR_EXISTS )); then
    original_data_after="$(stat -c '%d:%i:%f:%s:%Y:%Z' "$ORIGINAL_MISE_DATA_DIR")"
    assert_equal "$original_data_after" "$original_data_before" \
      "actual Mise tests must not mutate the original Mise data-root metadata"
  fi
}

test_verify_configuration_rejects_each_broken_mise_variable() {
  local broken output status

  for broken in artifacts maven nuget joinon foundation; do
    prepare_valid_configuration
    MISE_TEST_BREAK="$broken"
    export MISE_TEST_BREAK
    status=0
    output="$(verify_configuration 2>&1)" || status=$?
    [[ "$status" != "0" ]] || fail "verification must reject a broken $broken Mise variable"
    assert_equal "$output" "ERROR: Mise environment verification failed" \
      "broken $broken Mise variable diagnostic"
    unset MISE_TEST_BREAK
  done
}

test_verify_only_preflights_mise_and_python() {
  local missing_mise="$TEMP_DIR/verify-missing-mise"
  local no_python_mise="$TEMP_DIR/verify-no-python-mise"

  setup_cli_sandbox verify-preflight
  run_cli_with_input syntheticAzureArtifactsPat123 --pat-stdin
  assert_equal "$CLI_STATUS" "0" "verify preflight fixture setup"

  CLI_STATUS=0
  CLI_OUTPUT="$(env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$missing_mise" bash "$CONFIGURATOR" --verify-only 2>&1)" || CLI_STATUS=$?
  [[ "$CLI_STATUS" != "0" ]] || fail "verify-only must reject a missing Mise executable"
  assert_equal "$CLI_OUTPUT" "ERROR: Mise executable is unavailable: $missing_mise" \
    "verify-only missing Mise diagnostic"

  cat > "$no_python_mise" <<'EOF_MISE'
#!/usr/bin/env bash
exit 1
EOF_MISE
  chmod 700 "$no_python_mise"
  CLI_STATUS=0
  CLI_OUTPUT="$(env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$no_python_mise" bash "$CONFIGURATOR" --verify-only 2>&1)" || CLI_STATUS=$?
  [[ "$CLI_STATUS" != "0" ]] || fail "verify-only must reject missing Mise Python"
  assert_equal "$CLI_OUTPUT" "ERROR: Mise Python is unavailable: $no_python_mise" \
    "verify-only missing Mise Python diagnostic"
}

test_secret_temp_file_is_removed_when_rename_fails() {
  local pat='syntheticAzureArtifactsPat123'

  # shellcheck disable=SC2329
  mv() {
    return 1
  }

  if ( write_secret_file "$pat" ) >/dev/null 2>&1; then
    fail "a failed secret rename must fail the write"
  fi
  compgen -G "$(dirname "$AZDO_AUTH_SECRET_FILE")/.azure-artifacts.env.*" >/dev/null \
    && fail "a failed secret rename must remove the PAT-bearing temporary file"
  unset -f mv
}

test_secret_temp_file_is_removed_when_writing_fails() {
  local pat='syntheticAzureArtifactsPat123'
  local output status=0

  # shellcheck disable=SC2329
  printf() {
    if [[ "$1" == 'AZDO_ARTIFACTS_PAT=%s\n' ]]; then
      return 1
    fi
    # shellcheck disable=SC2059
    builtin printf "$@"
  }

  output="$( ( write_secret_file "$pat" ) 2>&1)" || status=$?
  compgen -G "$(dirname "$AZDO_AUTH_SECRET_FILE")/.azure-artifacts.env.*" >/dev/null \
    && fail "a failed secret write must remove the PAT-bearing temporary file"
  unset -f printf

  assert_equal "$status" "1" "a failed secret write must fail the write"
  [[ "$output" == *"Could not write Azure Artifacts secret file: $AZDO_AUTH_SECRET_FILE"* ]] \
    || fail "a failed secret write must name only the destination path"
  [[ "$output" != *"$pat"* ]] || fail "a failed secret write must not echo the PAT"
}

setup_cli_sandbox() {
  CLI_HOME="$TEMP_DIR/$1/home"
  mkdir -p "$CLI_HOME"
}

run_cli() {
  CLI_STATUS=0
  CLI_OUTPUT="$(env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" MISE_BIN="$TEMP_DIR/mise" bash "$CONFIGURATOR" "$@" 2>&1)" || CLI_STATUS=$?
}

run_cli_with_input() {
  local input=$1
  shift

  CLI_STATUS=0
  CLI_OUTPUT="$(printf '%s' "$input" | env -u AZDO_AUTH_SECRET_FILE -u AZDO_AUTH_MISE_CONFIG \
    -u AZDO_AUTH_MAVEN_SETTINGS HOME="$CLI_HOME" MISE_BIN="$TEMP_DIR/mise" bash "$CONFIGURATOR" "$@" 2>&1)" || CLI_STATUS=$?
}

assert_cli_output_has_no_pat() {
  local pat=$1

  [[ "$CLI_OUTPUT" != *"$pat"* ]] || fail "CLI output must not contain the PAT fixture"
}

test_pat_stdin_accepts_crlf_and_eof_then_rotates_without_output() {
  local first_pat='syntheticAzureArtifactsPat123'
  local second_pat='rotatedAzureArtifactsPat456'
  local secret_file config_file

  setup_cli_sandbox pat-stdin
  run_cli_with_input "$first_pat"$'\r\n' --pat-stdin
  case "$CLI_OUTPUT" in
    *"Mise executable is unavailable"*) fail "--pat-stdin preflight rejected the fake Mise executable" ;;
    *"Mise Python is unavailable"*) fail "--pat-stdin preflight rejected the fake Mise Python" ;;
    *"Maven settings preflight failed"*) fail "--pat-stdin Maven preflight failed" ;;
  esac
  assert_equal "$CLI_STATUS" "0" "--pat-stdin must accept CRLF input"
  assert_cli_output_has_no_pat "$first_pat"
  secret_file="$CLI_HOME/.config/mise/secrets/azure-artifacts.env"
  config_file="$CLI_HOME/.config/mise/conf.d/azure-artifacts.toml"
  local maven_settings="$CLI_HOME/.m2/settings.xml"
  grep -qx "AZDO_ARTIFACTS_PAT=$first_pat" "$secret_file" \
    || fail "--pat-stdin must normalize a trailing CR"
  ! grep -qF "$first_pat" "$config_file" \
    || fail "written mise config must not embed the PAT"
  [[ -f "$maven_settings" && ! -L "$maven_settings" ]] \
    || fail "setup must write regular Maven settings"
  ! grep -qF "$first_pat" "$maven_settings" \
    || fail "written Maven settings must not embed the PAT"

  run_cli_with_input "$second_pat" --pat-stdin
  assert_equal "$CLI_STATUS" "0" "--pat-stdin must accept input without a final newline"
  assert_cli_output_has_no_pat "$second_pat"
  assert_equal "$(wc -l < "$secret_file")" "1" "PAT rotation must preserve one assignment"
  grep -qx "AZDO_ARTIFACTS_PAT=$second_pat" "$secret_file" \
    || fail "PAT rotation must replace the secret value"
}

test_pat_stdin_rejects_empty_and_non_alphanumeric_input_without_output() {
  local invalid='not-a-valid-pat'

  setup_cli_sandbox invalid-pat
  run_cli_with_input $'\r\n' --pat-stdin
  [[ "$CLI_STATUS" != "0" ]] || fail "empty PAT input must fail"
  [[ "$CLI_OUTPUT" == *"PAT must be"* ]] || fail "empty PAT failure must explain the grammar"

  run_cli_with_input "$invalid" --pat-stdin
  [[ "$CLI_STATUS" != "0" ]] || fail "non-alphanumeric PAT input must fail"
  assert_cli_output_has_no_pat "$invalid"
  [[ ! -e "$CLI_HOME/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "invalid PAT input must not write a secret file"
}

test_dry_run_reports_actions_without_files_or_pat_output() {
  local pat='syntheticAzureArtifactsPat123'

  setup_cli_sandbox dry-run
  run_cli_with_input "$pat" --dry-run
  assert_equal "$CLI_STATUS" "0" "--dry-run must succeed"
  assert_cli_output_has_no_pat "$pat"
  [[ "$CLI_OUTPUT" == *"Would write Azure Artifacts secret file"* ]] \
    || fail "--dry-run must report the secret-file action"
  [[ "$CLI_OUTPUT" == *"Would write Azure Artifacts mise configuration"* ]] \
    || fail "--dry-run must report the mise-config action"
  [[ "$CLI_OUTPUT" == *"Would write Maven settings"* ]] \
    || fail "--dry-run must report the Maven-settings action"
  [[ ! -e "$CLI_HOME/.config/mise/secrets/azure-artifacts.env" ]] \
    || fail "--dry-run must not write the secret file"
  [[ ! -e "$CLI_HOME/.config/mise/conf.d/azure-artifacts.toml" ]] \
    || fail "--dry-run must not write the mise config"
  [[ ! -e "$CLI_HOME/.m2/settings.xml" ]] \
    || fail "--dry-run must not write Maven settings"
}

test_verify_only_succeeds_for_existing_files_and_fails_when_missing() {
  local pat='syntheticAzureArtifactsPat123'

  setup_cli_sandbox verify-only
  run_cli_with_input "$pat" --pat-stdin
  assert_equal "$CLI_STATUS" "0" "setup must create the Azure Artifacts files"
  run_cli --verify-only
  assert_equal "$CLI_STATUS" "0" "--verify-only must not need PAT input when files exist"
  assert_cli_output_has_no_pat "$pat"

  rm "$CLI_HOME/.config/mise/secrets/azure-artifacts.env"
  run_cli --verify-only
  [[ "$CLI_STATUS" != "0" ]] || fail "--verify-only must fail when the secret file is missing"
  assert_cli_output_has_no_pat "$pat"
}

test_cli_rejects_meaningless_combinations_and_unexpected_arguments() {
  local positional='synthetic-positional-value'
  local dash_prefixed_secret='--pat=syntheticDashPrefixedSecret'

  setup_cli_sandbox invalid-arguments
  run_cli --pat-stdin --dry-run
  [[ "$CLI_STATUS" != "0" ]] || fail "--pat-stdin --dry-run must fail"
  [[ "$CLI_OUTPUT" == *"cannot be used together"* ]] \
    || fail "invalid option combination must be explained"

  run_cli --pat-stdin --verify-only
  [[ "$CLI_STATUS" != "0" ]] || fail "--pat-stdin --verify-only must fail"
  [[ "$CLI_OUTPUT" == *"cannot be used together"* ]] \
    || fail "invalid option combination must be explained"

  run_cli "$positional"
  [[ "$CLI_STATUS" != "0" ]] || fail "an unexpected positional argument must fail"
  [[ "$CLI_OUTPUT" == *"Unexpected positional argument"* ]] \
    || fail "unexpected positional input must have a generic diagnostic"
  assert_cli_output_has_no_pat "$positional"

  run_cli "$dash_prefixed_secret"
  [[ "$CLI_STATUS" != "0" ]] || fail "an unknown dash-prefixed argument must fail"
  [[ "$CLI_OUTPUT" == *"Unknown option"* ]] \
    || fail "an unknown dash-prefixed argument must have a generic diagnostic"
  assert_cli_output_has_no_pat "$dash_prefixed_secret"
  [[ "$CLI_OUTPUT" != *syntheticDashPrefixedSecret* ]] \
    || fail "unknown option output must not contain its bare synthetic secret"
}

test_cli_rejects_a_noncanonical_secret_override_before_writing_or_verifying() {
  local pat='syntheticAzureArtifactsPat123'
  local wrong_secret="$TEMP_DIR/noncanonical-secret.env"

  setup_cli_sandbox path-mismatch
  CLI_STATUS=0
  CLI_OUTPUT="$(printf '%s' "$pat" | env -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS \
    HOME="$CLI_HOME" AZDO_AUTH_SECRET_FILE="$wrong_secret" \
    bash "$CONFIGURATOR" --pat-stdin 2>&1)" || CLI_STATUS=$?
  [[ "$CLI_STATUS" != "0" ]] || fail "a noncanonical secret override must fail before writing"
  [[ "$CLI_OUTPUT" == *"AZDO_AUTH_SECRET_FILE must use"* ]] \
    || fail "secret override rejection must identify the path contract"
  assert_cli_output_has_no_pat "$pat"
  [[ ! -e "$wrong_secret" ]] || fail "a rejected secret override must not write a file"

  CLI_STATUS=0
  CLI_OUTPUT="$(env -u AZDO_AUTH_MISE_CONFIG -u AZDO_AUTH_MAVEN_SETTINGS HOME="$CLI_HOME" \
    AZDO_AUTH_SECRET_FILE="$wrong_secret" \
    bash "$CONFIGURATOR" --verify-only 2>&1)" || CLI_STATUS=$?
  [[ "$CLI_STATUS" != "0" ]] || fail "a noncanonical secret override must fail in verify mode"
  [[ "$CLI_OUTPUT" == *"AZDO_AUTH_SECRET_FILE must use"* ]] \
    || fail "verify mode must enforce the secret path contract"
}

TEMP_DIR="$(mktemp -d)"
resolve_real_mise
HOME="$TEMP_DIR/home"
AZDO_AUTH_SECRET_FILE="$HOME/.config/mise/secrets/azure-artifacts.env"
AZDO_AUTH_MISE_CONFIG="$HOME/.config/mise/conf.d/azure-artifacts.toml"
AZDO_AUTH_MAVEN_SETTINGS="$HOME/.m2/settings.xml"
export HOME AZDO_AUTH_SECRET_FILE AZDO_AUTH_MISE_CONFIG AZDO_AUTH_MAVEN_SETTINGS

write_fake_mise
load_configurator_functions
test_mise_data_dir_resolution_prefers_explicit_then_xdg_then_home
test_documentation_and_cli_contracts
test_successful_configuration_uses_required_summary
test_secret_file_contains_one_assignment
test_mise_config_derives_all_consumers_without_embedding_pat
test_mise_config_redacts_pat_variables_and_nuget_credentials
test_mise_config_uses_the_canonical_secret_path
test_mise_config_is_written_atomically_without_a_secret
test_maven_migration_preserves_unrelated_settings
test_maven_migration_repairs_parent_directory_mode_on_every_run
test_maven_migration_refuses_doctype_without_writing_or_backup
test_maven_migration_refuses_plaintext_unrelated_server_password
test_maven_migration_accepts_environment_referenced_unrelated_server_password
test_maven_migration_accepts_encrypted_password_and_passphrase
test_maven_migration_accepts_multiline_wrapped_credentials
test_maven_migration_refuses_plaintext_unrelated_server_passphrase
test_maven_migration_preserves_envelope_with_a_fake_leading_root_tag
test_maven_regular_file_backup_preserves_original_settings
test_maven_migration_replaces_duplicate_foundation_servers
test_maven_migration_ignores_misplaced_and_wrong_namespace_foundation_servers
test_maven_symlink_backup_remains_a_symlink
test_maven_migration_does_not_overwrite_an_existing_rollback
test_maven_envelope_preservation_is_idempotent
test_maven_symlink_migration_is_idempotent
test_verify_configuration_checks_modes_mise_environment_and_maven_structure
test_verify_configuration_rejects_secret_and_mise_template_tampering
test_verify_configuration_hides_malformed_maven_parser_output
test_verify_configuration_rejects_a_doctype
test_verify_configuration_rejects_bad_modes_symlinks_and_maven_structure
test_verify_configuration_rejects_each_broken_mise_variable
test_verify_only_preflights_mise_and_python
test_cli_preflight_rejects_missing_mise_without_mutating_files
test_cli_preflight_rejects_missing_python_without_mutating_files
test_cli_preflight_rejects_invalid_maven_without_mutating_files
test_rendered_mise_config_loads_secret_and_rejects_missing_secret_with_actual_mise
test_secret_temp_file_is_removed_when_rename_fails
test_secret_temp_file_is_removed_when_writing_fails
test_pat_stdin_accepts_crlf_and_eof_then_rotates_without_output
test_pat_stdin_rejects_empty_and_non_alphanumeric_input_without_output
test_dry_run_reports_actions_without_files_or_pat_output
test_verify_only_succeeds_for_existing_files_and_fails_when_missing
test_cli_rejects_meaningless_combinations_and_unexpected_arguments
test_cli_rejects_a_noncanonical_secret_override_before_writing_or_verifying

printf 'PASS: Azure Artifacts configuration tests\n'
