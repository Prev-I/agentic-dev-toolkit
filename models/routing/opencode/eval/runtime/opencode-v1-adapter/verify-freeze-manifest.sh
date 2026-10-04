#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

verify_freeze_manifest() {
  local eval_root=$1 manifest=$2
  python3 - "$eval_root" "$manifest" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
bundle_root = root.parent
document = json.load(open(sys.argv[2], encoding="utf-8"))
for item in document["files"]:
    path = (root / item["path"]).resolve()
    if not path.is_relative_to(bundle_root) or not path.is_file():
        raise SystemExit(f"invalid freeze path: {item['path']}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != item["sha256"]:
        raise SystemExit(f"freeze digest mismatch: {item['path']}")
PY
}
