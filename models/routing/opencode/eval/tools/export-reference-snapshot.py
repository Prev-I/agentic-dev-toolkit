"""One-time artifact export; tests never require historical Git objects."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
repo = root.parents[3]
target = root / 'records/astra-build-followup/reference-snapshot'
commit = '55da937fb7233717c9924aa59c1e36773afbde29'
source_ref = 'refs/pull/34/head'
files = ['environments/linux/install.sh', 'tests/install.sh', 'instructions/adapters/claude-code/CLAUDE.md']
if target.exists():
    raise SystemExit('Refusing to overwrite snapshot')
entries = []
for name in files:
    data = subprocess.check_output(['git', 'show', f'{commit}:{name}'], cwd=repo)
    path = target / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    entries.append({'path': name, 'source_commit': commit, 'source_ref': source_ref,
                    'source_blob': subprocess.check_output(['git', 'rev-parse', f'{commit}:{name}'], cwd=repo, text=True).strip(),
                    'sha256': hashlib.sha256(data).hexdigest()})
(target / 'provenance.json').write_text(json.dumps({'files': entries}, indent=2) + '\n')
