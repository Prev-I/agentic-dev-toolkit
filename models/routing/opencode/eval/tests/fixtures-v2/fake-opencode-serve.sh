#!/usr/bin/env bash
# Fake `opencode` for the V1 -> V2 conversion test. Only `serve --hostname H
# --port P` is supported: it answers GET /api/config like a 2.x server, then
# execs fake-api.py on port P (so the server's pid is fake-api.py's).
#
# The config is read from $XDG_CONFIG_HOME/opencode/opencode.json. A V1 config
# is "translated" to the canned V2 document in $FAKE_SERVE_INFO; a V2 config
# translates to itself. The layers are that document and the working directory.
# The first GET /api/config answers 404, as a server still loading would.
# Fixtures are written under $XDG_CACHE_HOME, inside the sandbox.
#
# FAKE_SERVE_MODE:
#   differ  a V2 config does not translate to itself (the reload check fails)
#   leak    an extra layer outside the sandbox is reported
#   nodoc   no document layer is ever reported
# FAKE_SERVE_LOG, when set, receives the argv, the working directory and the
# names of the environment variables the fake was started with; a wrapper that
# sets FAKE_* variables records FAKE_SERVE_ENV_NAMES before setting them.
# The API password is the OPENCODE_PASSWORD the fake was given.
set -Eeuo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ "${1:-}" == serve ]] || { printf 'fake-opencode-serve: only "serve" is supported\n' >&2; exit 2; }
argv=("$@")
port=''
shift
while (( $# )); do
  case "$1" in
    --port) port=${2:?}; shift 2 ;;
    --hostname) shift 2 ;;
    *) printf 'fake-opencode-serve: unknown flag %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -n "${FAKE_SERVE_LOG:-}" ]]; then
  {
    printf 'argv:'; printf ' [%s]' "${argv[@]}"; printf '\n'
    printf 'cwd=%s\n' "$PWD"
    printf 'env=%s\n' "${FAKE_SERVE_ENV_NAMES:-}"
  } >>"$FAKE_SERVE_LOG"
fi

fixtures="${XDG_CACHE_HOME:?}/fake-api"
mkdir -p "$fixtures"
python3 -B - "${XDG_CONFIG_HOME:?}/opencode/opencode.json" "$fixtures" "$PWD" \
  "${FAKE_SERVE_INFO:?}" "${FAKE_SERVE_MODE:-}" <<'PY'
import json
import os
import sys

cfg_path, fixtures, cwd, canned, mode = sys.argv[1:]
with open(cfg_path) as f:
    cfg = json.load(f)
v1_keys = ("agent", "provider", "permission", "plugin",
           "disabled_providers", "autoupdate", "server")
if any(k in cfg for k in v1_keys):
    with open(canned) as f:
        info = json.load(f)
else:
    info = cfg
    if mode == "differ":
        info = dict(cfg, **{"x-reload-differs": True})
layers = []
if mode != "nodoc":
    layers.append({"path": cfg_path, "type": "document", "info": info})
layers.append({"path": cwd, "type": "directory", "info": None})
if mode == "leak":
    layers.append({"path": "/etc/opencode-outside", "type": "directory", "info": None})
with open(os.path.join(fixtures, "api_config.json"), "w") as f:
    json.dump(layers, f)
open(os.path.join(fixtures, "api_config.lazy"), "w").close()
with open(os.path.join(fixtures, "api_info.json"), "w") as f:
    json.dump({"version": "2.3.0-fake"}, f)
PY
exec env FAKE_API_PASSWORD="${OPENCODE_PASSWORD:?}" python3 -B "$here/fake-api.py" "${port:?}" "$fixtures"
