#!/usr/bin/env bash
# Ported from the V1 file of the same name, for OpenCode 2. Changes: paths
# resolve under REPO_ROOT (and must stay inside it) or, with a record: prefix,
# under RECORD_DIR; write_freeze_manifest produces the manifest.
set -Eeuo pipefail
IFS=$'\n\t'

verify_freeze_manifest() {
  local repo_root=$1 manifest=$2 record_dir=${3:-}
  python3 -I -B - "$repo_root" "$manifest" "$record_dir" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
record = Path(sys.argv[3]).resolve() if sys.argv[3] else None
document = json.load(open(sys.argv[2], encoding="utf-8"))
for item in document["files"]:
    name = item["path"]
    if name.startswith("record:"):
        base, rel = record, name[len("record:"):]
    else:
        base, rel = repo, name
    if base is None:
        raise SystemExit(f"invalid freeze path: {name}")
    path = (base / rel).resolve()
    if not path.is_relative_to(base) or not path.is_file():
        raise SystemExit(f"invalid freeze path: {name}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
        raise SystemExit(f"freeze digest mismatch: {name}")
PY
}

write_freeze_manifest() {
  local repo_root=$1 record_dir=$2 experiment_id=$3 out=$4
  shift 4
  python3 -I -B - "$repo_root" "$record_dir" "$experiment_id" "$out" "$@" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
record = Path(sys.argv[2]).resolve()
files = []
for raw in sys.argv[5:]:
    path = Path(raw).resolve()
    if path.is_relative_to(record):
        name = "record:" + path.relative_to(record).as_posix()
    else:
        name = path.relative_to(repo).as_posix()
    files.append({"path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
document = {"experiment_id": sys.argv[3], "status": "PRE_DISPATCH_FREEZE", "files": files}
with open(sys.argv[4], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}
