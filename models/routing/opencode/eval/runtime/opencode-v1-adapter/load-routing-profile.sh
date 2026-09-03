#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

load_routing_profile() {
  python3 - "$1" <<'PY'
import json
import re
import sys

raw = open(sys.argv[1], encoding="utf-8").read()
out = []
index = 0
size = len(raw)
in_string = False
escaped = False
while index < size:
    char = raw[index]
    if in_string:
        out.append(char)
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = False
        index += 1
        continue
    if char == '"':
        in_string = True
        out.append(char)
        index += 1
        continue
    if char == "/" and index + 1 < size and raw[index + 1] == "/":
        while index < size and raw[index] != "\n":
            index += 1
        continue
    if char == "/" and index + 1 < size and raw[index + 1] == "*":
        index += 2
        while index + 1 < size and not (raw[index] == "*" and raw[index + 1] == "/"):
            index += 1
        index += 2
        continue
    out.append(char)
    index += 1
text = re.sub(r",(\s*[}\]])", r"\1", "".join(out))
try:
    document = json.loads(text)
except json.JSONDecodeError as error:
    raise SystemExit(f"malformed JSONC: {error}")
json.dump(document, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
}
