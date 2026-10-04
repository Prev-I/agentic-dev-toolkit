"""Execute the frozen verifier with a snapshot-backed loader, without editing it."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
source = root / 'records/opus55-gpt61-build-quality-screening/verify-results-v2.py'
reference = root / 'records/astra-build-followup/reference-snapshot'
spec = importlib.util.spec_from_file_location('frozen_verifier', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def snapshot(commit, target):
    if commit != module.REFERENCE:
        raise ValueError('Unknown snapshot request')
    entries = json.loads((reference / 'provenance.json').read_text())['files']
    if {entry['path'] for entry in entries} != set(module.FILES):
        raise ValueError('Snapshot inventory mismatch')
    for entry in entries:
        if entry['source_commit'] != commit or entry['source_ref'] != 'refs/pull/34/head':
            raise ValueError('Snapshot provenance mismatch')
        data = (reference / entry['path']).read_bytes()
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Snapshot hash mismatch')
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if blob != entry['source_blob']:
            raise ValueError('Git blob identity mismatch')
        # Optional parity check only: standard clones lack these PR-only objects.
        available = subprocess.run(['git', 'cat-file', '-e', entry['source_commit']], cwd=module.REPO,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if available:
            original = subprocess.check_output(['git', 'show', f"{entry['source_commit']}:{entry['path']}"], cwd=module.REPO)
            if original != data:
                raise ValueError('Snapshot differs from locally available Git object')
        else:
            print('NOTE: historical Git object unavailable; snapshot SHA-256 and blob identity verified', file=sys.stderr)
        destination = target / entry['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)


module.snapshot = snapshot
module.main()
