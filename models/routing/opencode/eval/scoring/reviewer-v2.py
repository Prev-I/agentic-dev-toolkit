"""Strict v2 attribution; never apply to historical v1 findings."""
import json
from pathlib import Path
import sys


def attribute(fixture, findings):
    oracle = json.loads((fixture / 'oracle.json').read_text())
    material = set(oracle['material_severities'])
    classification = {}
    seen = set()
    for item in findings['seeded']:
        case = item['id']
        if case in seen or case not in oracle['expected_ids']:
            raise ValueError('duplicate or unknown case')
        seen.add(case)
        truth = json.loads((fixture / 'cases' / case / 'ground-truth.json').read_text())
        if set(item['files']) != set(truth['overrides']):
            raise ValueError('override mismatch')
        matches = [f for f in item['all_reported'] if Path(str(f.get('file', ''))).name in truth['overrides']
                   and f.get('severity') in material]
        if 'witness' in truth:
            witness = truth['witness']
            if not isinstance(witness, str) or not witness:
                raise ValueError('empty or malformed witness')
            if not any(witness in (fixture / 'cases' / case / name).read_text() for name in truth['overrides']):
                raise ValueError('stale witness')
            if any(witness in (fixture / 'clean' / name).read_text() for name in truth['overrides']):
                raise ValueError('witness also in clean')
            matches = [f for f in matches if isinstance(f.get('evidence'), str) and witness in f['evidence']]
        classification[case] = 'detected' if len(matches) == 1 else 'missed' if not matches else 'ambiguous'
    if seen != set(oracle['expected_ids']):
        raise ValueError('incomplete corpus')
    clean = sum(f.get('severity') in material for f in findings['clean'])
    gate = 'pass' if all(v == 'detected' for v in classification.values()) and clean == 0 else 'block'
    return {'classification': 'POST_RUN_DIAGNOSTIC', 'adjudicates': False,
            'attribution': classification, 'clean_material_findings': clean, 'gate': gate}


if __name__ == '__main__':
    fixture = Path(sys.argv[1])
    if fixture.name != 'reviewer-seeded-defects-v2':
        raise SystemExit('v2 scorer requires the v2 fixture')
    try:
        print(json.dumps(attribute(fixture, json.loads(Path(sys.argv[2]).read_text())), indent=2))
    except (KeyError, ValueError, OSError, TypeError) as error:
        raise SystemExit(f'v2 attribution fails closed: {error}')
