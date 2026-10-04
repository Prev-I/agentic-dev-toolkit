"""Create an input digest snapshot for this design-only freeze. No model calls."""
import hashlib
import json
from pathlib import Path

record = Path(__file__).resolve().parent
root = record.parent.parent
paths = [record / 'protocol.json', record / 'catalog-snapshot.json', Path(__file__).resolve(),
         root / 'records/gpt61-sol-build-screening/coding-prompt.txt',
         root / 'records/astra-build-followup/oracle.sh',
         root / 'records/sol-build/empty-path-check.sh',
         root / 'records/opus55-gpt61-build-quality-screening/verify-results-v2.py',
         root / 'records/opus55-gpt61-build-quality-screening/verify-results-v2.sh']
paths += sorted((root / 'records/astra-build-followup/base-snapshot').rglob('*'))
paths += sorted((root / 'records/opus55-gpt61-build-quality-screening/runs').glob('*-coding-*/dispatch/raw.jsonl'))
document = {'status': 'AWAITING_APPROVAL', 'files': [
    {'path': str(p.relative_to(root)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    for p in paths if p.is_file()
]}
target = record / 'freeze-manifest.json'
if target.exists():
    raise SystemExit('Refusing to rewrite existing freeze')
target.write_text(json.dumps(document, indent=2) + '\n')
