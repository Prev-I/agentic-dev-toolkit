source "${BASH_SOURCE[0]%/*}/protocol.sh"
adapter_version() { printf '%s\n' "$PROTOCOL_VERSION"; }
