#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

validate_breakglass() {
  local file=$1
  python3 - "$file" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))["breakglass"]
except (OSError, KeyError, TypeError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if data.get("mode") == "primary" and
                 data.get("model") == "openai/gpt-5.6-sol" and
                 data.get("variant") == "max" else 1)
PY
}
