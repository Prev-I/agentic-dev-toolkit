#!/usr/bin/env bash
# Fake `opencode` for the screening sandbox tests. Only `serve --hostname H
# --port P` is supported: like fake-opencode-serve.sh, it answers GET
# /api/config like a 2.x server, then execs fake-api.py on port P (so the
# server's pid is this script's, and fake-api.py's).
#
# The server starts under `env -i`, so settings arrive only through a wrapper
# that exports FAKE_SCREEN_STATE=<dir> and execs this script:
#   FAKE_SCREEN_STATE/log          receives "serve pid=<pid> cwd=<cwd> home=<home>"
#   FAKE_SCREEN_STATE/models.json  served as GET /api/model, when present
#   FAKE_SCREEN_STATE/mode         `leak` adds a layer /etc/opencode-outside
# The layers are the config document ($XDG_CONFIG_HOME/opencode/opencode.json)
# and the working directory; the first GET /api/config answers 404, as a server
# still loading would. Fixtures are written under $XDG_CACHE_HOME, inside the
# sandbox. The API password is the OPENCODE_PASSWORD the fake was given.
set -Eeuo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state=${FAKE_SCREEN_STATE:?FAKE_SCREEN_STATE is not set}

[[ "${1:-}" == serve ]] || { printf 'fake-opencode-screening: only "serve" is supported\n' >&2; exit 2; }
port=''
shift
while (( $# )); do
  case "$1" in
    --port) port=${2:?}; shift 2 ;;
    --hostname) shift 2 ;;
    *) printf 'fake-opencode-screening: unknown flag %s\n' "$1" >&2; exit 2 ;;
  esac
done

mode=''
[[ ! -f "$state/mode" ]] || mode=$(<"$state/mode")
printf 'serve pid=%s cwd=%s home=%s\n' "$$" "$PWD" "$HOME" >>"$state/log"

fixtures="${XDG_CACHE_HOME:?}/fake-api"
mkdir -p "$fixtures"
python3 -B - "${XDG_CONFIG_HOME:?}/opencode/opencode.json" "$fixtures" "$PWD" "$mode" <<'PY'
import json
import os
import sys

cfg_path, fixtures, cwd, mode = sys.argv[1:]
with open(cfg_path) as f:
    cfg = json.load(f)
layers = [{"path": cfg_path, "type": "document", "info": cfg},
          {"path": cwd, "type": "directory", "info": None}]
if mode == "leak":
    layers.append({"path": "/etc/opencode-outside", "type": "directory", "info": None})
with open(os.path.join(fixtures, "api_config.json"), "w") as f:
    json.dump(layers, f)
open(os.path.join(fixtures, "api_config.lazy"), "w").close()
with open(os.path.join(fixtures, "api_info.json"), "w") as f:
    json.dump({"version": "2.3.0-fake"}, f)
PY
if [[ -f "$state/models.json" ]]; then
  cp "$state/models.json" "$fixtures/api_model.json"
fi
exec env FAKE_API_PASSWORD="${OPENCODE_PASSWORD:?}" python3 -B "$here/fake-api.py" "${port:?}" "$fixtures"
