"""Reduce captured debug inventories; retain ordered Task evidence, no host paths."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
paths = list((root / 'resolved').glob('*.json')) + list((root / 'permissions').glob('*-resolved.json'))
for path in paths:
    data = json.loads(path.read_text())
    reduced = {key: data[key] for key in ('name', 'model', 'variant', 'mode')}
    reduced['tools'] = {'task': data['tools']['task']}
    reduced['permission'] = [rule for rule in data['permission'] if rule['permission'] == 'task']
    reduced['capture_projection'] = 'debug agent output reduced to model inventory and ordered Task rules; external-directory paths and prompt omitted'
    path.write_text(json.dumps(reduced, indent=2) + '\n')
