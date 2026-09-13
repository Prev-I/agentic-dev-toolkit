#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

MISE_BIN="${MISE_BIN:-$HOME/.local/bin/mise}"
AZDO_AUTH_SECRET_FILE="${AZDO_AUTH_SECRET_FILE:-$HOME/.config/mise/secrets/azure-artifacts.env}"
AZDO_AUTH_MISE_CONFIG="${AZDO_AUTH_MISE_CONFIG:-$HOME/.config/mise/conf.d/azure-artifacts.toml}"
AZDO_AUTH_MAVEN_SETTINGS="${AZDO_AUTH_MAVEN_SETTINGS:-$HOME/.m2/settings.xml}"

DRY_RUN=0
VERIFY_ONLY=0
PAT_STDIN=0

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF_USAGE'
Usage: configure.sh [--dry-run] [--verify-only] [--pat-stdin]

Configure mise environment variables for Azure Artifacts authentication.

Canonical paths:
  ~/.config/mise/secrets/azure-artifacts.env
  ~/.config/mise/conf.d/azure-artifacts.toml
  ~/.m2/settings.xml

Commands:
  azure-artifacts/configure.sh
  azure-artifacts/configure.sh --verify-only
  ~/.local/bin/mise exec -- mvn -version
  ~/.local/bin/mise exec -- dotnet --info

Options:
  --dry-run      Report paths and actions without changing files or reading a PAT.
  --verify-only  Verify generated configuration without reading a PAT.
  --pat-stdin    migration or controlled automation only. normal setup and
                 rotation prompt hidden from /dev/tty.
  --help, -h     Show this help text.
EOF_USAGE
}

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
  if ! printf 'AZDO_ARTIFACTS_PAT=%s\n' "$pat" > "$tmp" || ! mv -f "$tmp" "$AZDO_AUTH_SECRET_FILE"; then
    rm -f "$tmp"
    die "Could not write Azure Artifacts secret file: $AZDO_AUTH_SECRET_FILE"
  fi
}

write_mise_config() {
  local dir tmp

  dir="$(dirname "$AZDO_AUTH_MISE_CONFIG")"
  install -d -m 755 "$dir"
  tmp="$(mktemp "$dir/.azure-artifacts.toml.XXXXXX")"
  chmod 644 "$tmp"
  render_mise_config > "$tmp"
  mv -f "$tmp" "$AZDO_AUTH_MISE_CONFIG"
}

preflight_mise() {
  [[ -x "$MISE_BIN" ]] || die "Mise executable is unavailable: $MISE_BIN"
  "$MISE_BIN" exec -- python -c 'pass' >/dev/null 2>&1 \
    || die "Mise Python is unavailable: $MISE_BIN"
}

preflight_maven_settings() {
  local offending_server

  preflight_mise
  if [[ ! -e "$AZDO_AUTH_MAVEN_SETTINGS" && ! -L "$AZDO_AUTH_MAVEN_SETTINGS" ]]; then
    return 0
  fi

  if ! offending_server="$("$MISE_BIN" exec -- python - "$AZDO_AUTH_MAVEN_SETTINGS" 2>/dev/null <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
with open(path, 'rb') as settings_file:
    if re.search(rb'<!DOCTYPE(?:\s|>)', settings_file.read(), re.IGNORECASE):
        raise SystemExit(1)
parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
root = ET.parse(path, parser=parser).getroot()
namespace = root.tag.partition('}')[0][1:] if root.tag.startswith('{') else ''

def tag(name):
    return f'{{{namespace}}}{name}' if namespace else name

for section in root:
    if section.tag != tag('servers'):
        continue
    for server in section:
        if server.tag != tag('server'):
            continue
        server_id = next((child.text or '' for child in server if child.tag == tag('id')), '')
        if server_id == 'Foundation':
            continue
        for field in ('password', 'passphrase'):
            value = next((child.text for child in server if child.tag == tag(field)), None)
            if value and not (
                re.fullmatch(r'\$\{env\.[^}]+\}', value.strip())
                or re.fullmatch(r'\{.+\}', value.strip(), re.DOTALL)
            ):
                print(server_id.replace('\n', ' ').replace('\r', ' '))
                raise SystemExit(1)
PY
)"; then
    if [[ -n "$offending_server" ]]; then
      die "Maven settings preflight failed for server $offending_server: $AZDO_AUTH_MAVEN_SETTINGS"
    fi
    die "Maven settings preflight failed: $AZDO_AUTH_MAVEN_SETTINGS"
  fi
}

configure_maven_settings() {
  local dir rollback tmp migration_error

  dir="$(dirname "$AZDO_AUTH_MAVEN_SETTINGS")"
  rollback="${AZDO_AUTH_MAVEN_SETTINGS}.pre-mise-azure-artifacts"
  install -d "$dir"
  chmod 700 "$dir"

  tmp="$(mktemp "$dir/.settings.xml.XXXXXX")"
  chmod 600 "$tmp"
  if ! migration_error="$("$MISE_BIN" exec -- python - "$AZDO_AUTH_MAVEN_SETTINGS" "$tmp" 2>/dev/null <<'PY'
import os
import re
import sys
import xml.etree.ElementTree as ET

source, destination = sys.argv[1:]
prefix = b''
suffix = b''
if os.path.exists(source):
    with open(source, 'rb') as settings_file:
        source_bytes = settings_file.read()
        if re.search(rb'<!DOCTYPE(?:\s|>)', source_bytes, re.IGNORECASE):
            raise SystemExit(1)
    prolog = re.match(rb'(?:\s|<!--.*?-->|<\?.*?\?>)*', source_bytes, re.DOTALL)
    root_start_offset = prolog.end()
    root_start = re.match(rb'<settings(?:\s|>)', source_bytes[root_start_offset:])
    root_ends = list(re.finditer(rb'</settings\s*>', source_bytes))
    root_end = root_ends[-1] if root_ends else None
    if not root_start or not root_end:
        raise SystemExit(1)
    prefix = source_bytes[:root_start_offset]
    suffix = source_bytes[root_end.end():]
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    root = ET.parse(source, parser=parser).getroot()
else:
    root = ET.Element('settings')

namespace = root.tag.partition('}')[0][1:] if root.tag.startswith('{') else ''
if namespace:
    ET.register_namespace('', namespace)

def tag(name):
    return f'{{{namespace}}}{name}' if namespace else name

servers_sections = [child for child in root if child.tag == tag('servers')]
if servers_sections:
    servers = servers_sections[0]
else:
    before = {
        tag('mirrors'), tag('proxies'), tag('profiles'), tag('activeProfiles'), tag('pluginGroups'),
    }
    index = next((index for index, child in enumerate(root) if child.tag in before), len(root))
    servers = ET.Element(tag('servers'))
    root.insert(index, servers)

for section in servers_sections:
    for server in list(section):
        if server.tag != tag('server'):
            continue
        server_id = next((child.text for child in server if child.tag == tag('id')), None)
        if server_id == 'Foundation':
            section.remove(server)
        elif server_id != 'Foundation':
            for field in ('password', 'passphrase'):
                value = next((child.text for child in server if child.tag == tag(field)), None)
                if value and not (
                    re.fullmatch(r'\$\{env\.[^}]+\}', value.strip())
                    or re.fullmatch(r'\{.+\}', value.strip(), re.DOTALL)
                ):
                    print((server_id or '').replace('\n', ' ').replace('\r', ' '))
                    raise SystemExit(1)

server = ET.SubElement(servers, tag('server'))
ET.SubElement(server, tag('id')).text = 'Foundation'
ET.SubElement(server, tag('username')).text = 'gewiss-resel'
ET.SubElement(server, tag('password')).text = '${env.AZDO_MAVEN_PAT}'

tree = ET.ElementTree(root)
ET.indent(tree, space='  ')
with open(destination, 'wb') as destination_file:
    destination_file.write(prefix)
    destination_file.write(ET.tostring(root, encoding='utf-8'))
    destination_file.write(suffix)
# Final parse prevents an invalid envelope/root combination from being renamed.
ET.parse(destination)
PY
)"; then
    rm -f "$tmp"
    if [[ -n "$migration_error" ]]; then
      die "Could not migrate Maven settings for server $migration_error: $AZDO_AUTH_MAVEN_SETTINGS"
    fi
    die "Could not migrate Maven settings: $AZDO_AUTH_MAVEN_SETTINGS"
  fi

  if [[ ( -e "$AZDO_AUTH_MAVEN_SETTINGS" || -L "$AZDO_AUTH_MAVEN_SETTINGS" ) \
    && ! -e "$rollback" && ! -L "$rollback" ]]; then
    if [[ -L "$AZDO_AUTH_MAVEN_SETTINGS" ]]; then
      ln -s "$(readlink "$AZDO_AUTH_MAVEN_SETTINGS")" "$rollback"
    else
      install -m 600 "$AZDO_AUTH_MAVEN_SETTINGS" "$rollback"
    fi
  fi

  if ! mv -f "$tmp" "$AZDO_AUTH_MAVEN_SETTINGS"; then
    rm -f "$tmp"
    die "Could not write Maven settings: $AZDO_AUTH_MAVEN_SETTINGS"
  fi
}

verify_configuration() {
  local secret_dir maven_dir

  secret_dir="$(dirname "$AZDO_AUTH_SECRET_FILE")"
  maven_dir="$(dirname "$AZDO_AUTH_MAVEN_SETTINGS")"
  preflight_mise
  [[ -f "$AZDO_AUTH_SECRET_FILE" ]] || die "Azure Artifacts secret file is missing: $AZDO_AUTH_SECRET_FILE"
  [[ "$(stat -c '%a' "$secret_dir")" == 700 ]] \
    || die "Azure Artifacts secret directory must have mode 0700: $secret_dir"
  [[ "$(stat -c '%a' "$AZDO_AUTH_SECRET_FILE")" == 600 ]] \
    || die "Azure Artifacts secret file must have mode 0600: $AZDO_AUTH_SECRET_FILE"
  if ! [[ "$(awk 'END { print NR }' "$AZDO_AUTH_SECRET_FILE")" == 1 ]] \
    || ! grep -qxE 'AZDO_ARTIFACTS_PAT=[A-Za-z0-9]+' "$AZDO_AUTH_SECRET_FILE"; then
    die "Azure Artifacts secret file must contain one canonical assignment: $AZDO_AUTH_SECRET_FILE"
  fi
  [[ -f "$AZDO_AUTH_MISE_CONFIG" ]] || die "Azure Artifacts mise configuration is missing: $AZDO_AUTH_MISE_CONFIG"
  [[ "$(stat -c '%a' "$AZDO_AUTH_MISE_CONFIG")" == 644 ]] \
    || die "Azure Artifacts mise configuration must have mode 0644: $AZDO_AUTH_MISE_CONFIG"
  cmp -s <(render_mise_config) "$AZDO_AUTH_MISE_CONFIG" \
    || die "Azure Artifacts mise configuration must use canonical template references: $AZDO_AUTH_MISE_CONFIG"
  [[ "$(stat -c '%a' "$maven_dir")" == 700 ]] \
    || die "Azure Artifacts Maven directory must have mode 0700: $maven_dir"
  [[ -f "$AZDO_AUTH_MAVEN_SETTINGS" && ! -L "$AZDO_AUTH_MAVEN_SETTINGS" ]] \
    || die "Azure Artifacts Maven settings must be a regular file: $AZDO_AUTH_MAVEN_SETTINGS"
  [[ "$(stat -c '%a' "$AZDO_AUTH_MAVEN_SETTINGS")" == 600 ]] \
    || die "Azure Artifacts Maven settings must have mode 0600: $AZDO_AUTH_MAVEN_SETTINGS"

  # shellcheck disable=SC2016
  "$MISE_BIN" exec -- sh -c '
    set -e
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
  ' || die "Mise environment verification failed"

  if ! "$MISE_BIN" exec -- python - "$AZDO_AUTH_MAVEN_SETTINGS" 2>/dev/null <<'PY'; then
import sys
import re
import xml.etree.ElementTree as ET

path = sys.argv[1]
with open(path, 'rb') as settings_file:
    if re.search(rb'<!DOCTYPE(?:\s|>)', settings_file.read(), re.IGNORECASE):
        raise SystemExit(1)
parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
root = ET.parse(path, parser=parser).getroot()
namespace = root.tag.partition('}')[0][1:] if root.tag.startswith('{') else ''

def tag(name):
    return f'{{{namespace}}}{name}' if namespace else name

servers = []
for section in root:
    if section.tag != tag('servers'):
        continue
    for server in section:
        if server.tag != tag('server'):
            continue
        values = {
            child.tag.rsplit('}', 1)[-1]: child.text
            for child in server
            if child.tag in {tag('id'), tag('username'), tag('password')}
        }
        if values.get('id') == 'Foundation':
            servers.append(values)

if len(servers) != 1:
    raise SystemExit(1)
server = servers[0]
if server != {
    'id': 'Foundation',
    'username': 'gewiss-resel',
    'password': '${env.AZDO_MAVEN_PAT}',
}:
    raise SystemExit(1)
PY
    die "Maven settings verification failed: $AZDO_AUTH_MAVEN_SETTINGS"
  fi

  printf 'PASS\n'
}

validate_secret_path() {
  local expected="$HOME/.config/mise/secrets/azure-artifacts.env"

  [[ "$AZDO_AUTH_SECRET_FILE" == "$expected" ]] \
    || die "AZDO_AUTH_SECRET_FILE must use the canonical HOME-relative secret path"
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --verify-only)
        VERIFY_ONLY=1
        ;;
      --pat-stdin)
        PAT_STDIN=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      -*)
        die "Unknown option"
        ;;
      *)
        die "Unexpected positional argument"
        ;;
    esac
    shift
  done

  (( !(DRY_RUN && VERIFY_ONLY) )) || die "--dry-run and --verify-only cannot be used together"
  (( !(PAT_STDIN && (DRY_RUN || VERIFY_ONLY)) )) || die "--pat-stdin cannot be used together with --dry-run or --verify-only"
}

main() {
  local pat

  parse_args "$@"
  validate_secret_path

  if (( VERIFY_ONLY )); then
    verify_configuration
    printf 'Azure Artifacts configuration is present.\n'
    return
  fi

  if (( DRY_RUN )); then
    printf 'Would write Azure Artifacts secret file: %s\n' "$AZDO_AUTH_SECRET_FILE"
    printf 'Would write Azure Artifacts mise configuration: %s\n' "$AZDO_AUTH_MISE_CONFIG"
    printf 'Would write Maven settings: %s\n' "$AZDO_AUTH_MAVEN_SETTINGS"
    return
  fi

  preflight_maven_settings

  if (( PAT_STDIN )); then
    IFS= read -r pat || [[ -n "$pat" ]] || die "Could not read PAT from standard input"
    pat="${pat%$'\r'}"
  else
    read -rsp 'Azure DevOps PAT: ' pat < /dev/tty || die "Could not read PAT from /dev/tty"
    printf '\n' > /dev/tty
  fi

  write_secret_file "$pat"
  write_mise_config
  configure_maven_settings
  printf '%s\n' \
    'Configured Azure Artifacts authentication through mise.' \
    'Run azure-artifacts/configure.sh --verify-only to verify structure.' \
    'Run the cold-cache work tests before removing legacy credentials.'
}

main "$@"
