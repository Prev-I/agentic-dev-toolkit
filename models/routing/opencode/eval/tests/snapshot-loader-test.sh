#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/prerequisites.sh"
require_system_python
/usr/bin/python3 - "$root" <<'PY'
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('loader', root / 'tools/snapshot-verifier.py')
loader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader)
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    original = loader.reference
    # Exercise the normal-clone path even on a host with the PR objects.
    with patch.object(loader.subprocess, 'run') as run:
        run.return_value.returncode = 1
        loader.snapshot(loader.module.REFERENCE, tmp / 'output')
    for name in loader.module.FILES:
        assert (tmp / 'output' / name).read_bytes() == (original / name).read_bytes()
    shutil.copytree(original, tmp / 'reference')
    loader.reference = tmp / 'reference'
    manifest = loader.reference / 'provenance.json'
    baseline = manifest.read_text()
    for field, value in [('source_commit', '0' * 40), ('source_blob', '0' * 40), ('sha256', '0' * 64), ('path', '../escape')]:
        document = json.loads(baseline)
        document['files'][0][field] = value
        manifest.write_text(json.dumps(document))
        try:
            loader.snapshot(loader.module.REFERENCE, tmp / 'rejected')
        except ValueError:
            pass
        else:
            raise AssertionError(f'Accepted invalid {field}')
    manifest.write_text(baseline)
    first = loader.reference / loader.module.FILES[0]
    first.write_bytes(first.read_bytes() + b'corruption')
    try:
        loader.snapshot(loader.module.REFERENCE, tmp / 'corrupt')
    except ValueError:
        pass
    else:
        raise AssertionError('Accepted corrupted snapshot')
print('PASS: snapshot loader works without PR objects and rejects provenance/content corruption')
PY
