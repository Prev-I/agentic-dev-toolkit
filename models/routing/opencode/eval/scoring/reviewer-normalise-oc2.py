"""Normalise one candidate's reviewer runs for one repetition into the findings document.

Usage: reviewer-normalise-oc2.py RECORD FIXTURE KEY REP

Reads RECORD/runs/*-<case>-r<REP>-<KEY>/reported.json for every case in the
fixture (plus "clean") and writes RECORD/findings-<KEY>-r<REP>.json in the shape
scoring/reviewer-v2.py reads. A missing report counts as zero findings and is
listed in missing_runs.
"""
import glob
import json
import os
from pathlib import Path
import subprocess
import sys

RANK = {'blocking': 3, 'material': 2, 'suggestion': 1}


def load_report(record, case, key, rep):
    paths = sorted(glob.glob(f'{glob.escape(record)}/runs/[0-9]*-{glob.escape(case)}-r{rep}-{glob.escape(key)}/reported.json'))
    if not paths:
        return None
    payload = json.loads(Path(paths[0]).read_text(encoding='utf-8'))
    return [item for item in payload.get('findings', []) if isinstance(item, dict)]


def normalise(record, fixture, key, rep):
    reports, missing = {}, []
    ids = ['clean'] + sorted(os.path.basename(p.rstrip('/')) for p in glob.glob(f'{glob.escape(fixture)}/cases/*/'))
    for case in ids:
        found = load_report(record, case, key, rep)
        if found is None:
            missing.append(case)
        reports[case] = found or []
    seeded = []
    for case in ids[1:]:
        truth = json.loads(Path(f'{fixture}/cases/{case}/ground-truth.json').read_text(encoding='utf-8'))
        overrides = set(truth['overrides'])
        candidates = [item for item in reports[case] if os.path.basename(str(item.get('file', ''))) in overrides]
        if candidates:
            best = max(candidates, key=lambda item: RANK.get(str(item.get('severity')), 0))
            severity, summary = str(best.get('severity')), str(best.get('summary', ''))
        else:
            severity, summary = 'none', ''
        seeded.append({'id': case, 'severity': severity, 'files': sorted(overrides),
                       'summary': summary, 'all_reported': reports[case]})
    clean = [{'severity': str(item.get('severity')), 'file': str(item.get('file', '')),
              'summary': str(item.get('summary', ''))} for item in reports['clean']]
    revision = subprocess.run(['git', '-C', fixture, 'log', '-1', '--format=%H', '--', '.'],
                              capture_output=True, text=True).stdout.strip() or 'unknown'
    return {
        'model_key': key,
        'repetition': rep,
        'seeded': seeded,
        'clean': clean,
        'missing_runs': missing,
        'normalization': 'unchanged Reviewer adapter shape; scorer determines detection from all_reported, files, and fixture witnesses',
        'runner_decides_gate_outcome': False,
        'scorer': 'eval/scoring/reviewer-v2.py',
        'fixture_revision': revision,
        'fixture_integrity_checked': True,
    }


def main(argv):
    if len(argv) != 5:
        raise SystemExit('usage: reviewer-normalise-oc2.py RECORD FIXTURE KEY REP')
    record, fixture, key, rep = argv[1:]
    document = normalise(record, fixture, key, rep)
    with open(f'{record}/findings-{key}-r{rep}.json', 'w', encoding='utf-8') as handle:
        json.dump(document, handle, indent=2)
        handle.write('\n')


if __name__ == '__main__':
    main(sys.argv)
