"""Offline verifier v2. All outputs are POST_RUN_DIAGNOSTIC, never adjudication."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

RECORD = Path(__file__).resolve().parent
EVAL = RECORD.parent.parent
REPO = EVAL.parents[3]
BASE = EVAL / 'records/astra-build-followup/base-snapshot'
FILES = ['environments/linux/install.sh', 'tests/install.sh',
         'instructions/adapters/claude-code/CLAUDE.md']
REFERENCE = '55da937fb7233717c9924aa59c1e36773afbde29'
BROKEN = '7605022b86dd9f4040f272cca59224f2e568a943'


def snapshot(commit, target):
    for name in FILES:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(subprocess.check_output(['git', 'show', f'{commit}:{name}'], cwd=REPO))


def run(command, workspace, log):
    """Fresh HOME, fixed cwd and trusted Python for each individual check."""
    with tempfile.TemporaryDirectory(prefix='verifier-v2-home-') as tmp:
        home = Path(tmp)
        bin_dir = home / 'bin'
        bin_dir.mkdir()
        credential = home / '.local/bin/git-credential-manager-wsl'
        credential.parent.mkdir(parents=True)
        # No credential access: satisfy the historical suite's independent
        # verify-only prerequisite without disabling any WSL branch.
        credential.write_text('#!/bin/bash\nprintf "never|GCM_INTERACTIVE\\n"\n')
        credential.chmod(0o755)
        # Capture Python stderr separately even if the historical test redirects it.
        wrapper = bin_dir / 'python3'
        wrapper.write_text('#!/bin/bash\n/usr/bin/python3 "$@" 2>"$EVAL_PYTHON_STDERR.tmp"\ns=$?\n/bin/cat "$EVAL_PYTHON_STDERR.tmp" >>"$EVAL_PYTHON_STDERR"\n/bin/cat "$EVAL_PYTHON_STDERR.tmp" >&2\nexit "$s"\n')
        wrapper.chmod(0o755)
        env = {'HOME': str(home), 'PATH': f'{bin_dir}:/usr/bin:/bin', 'LANG': 'C.UTF-8',
               'USER': 'eval', 'XDG_CONFIG_HOME': str(home / '.config'),
               'EVAL_PYTHON_STDERR': str(log.with_suffix('.python-stderr.log'))}
        result = subprocess.run(command, cwd=workspace, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log.write_bytes(b'classification: POST_RUN_DIAGNOSTIC\n' + result.stdout)
        log.with_suffix('.stderr.log').write_bytes(result.stderr)
        return result.returncode


def evaluate(workspace, output):
    output.mkdir(parents=True)
    candidate_tests = (workspace / 'tests/install.sh').read_bytes()
    installer = (workspace / 'environments/linux/install.sh').read_bytes()
    result = {'classification': 'POST_RUN_DIAGNOSTIC'}
    result['oracle'] = run(['bash', str(EVAL / 'records/astra-build-followup/oracle.sh'), str(workspace)], workspace, output / 'oracle.log')
    result['empty_path'] = run(['bash', str(EVAL / 'records/sol-build/empty-path-check.sh'), str(workspace)], workspace, output / 'empty-path.log')
    (workspace / 'tests/install.sh').write_bytes((BASE / 'tests/install.sh').read_bytes())
    result['immutable_suite'] = run(['setsid', 'bash', 'tests/install.sh'], workspace, output / 'immutable-suite.log')
    (workspace / 'tests/install.sh').write_bytes(candidate_tests)
    result['candidate_suite'] = run(['setsid', 'bash', 'tests/install.sh'], workspace, output / 'candidate-suite.log')
    for name in ('environments/linux/install.sh', 'tests/install.sh'):
        result['syntax_' + name] = run(['bash', '-n', name], workspace, output / (Path(name).stem + '-syntax.log'))
    (workspace / 'environments/linux/install.sh').write_bytes((BASE / 'environments/linux/install.sh').read_bytes())
    result['mutation_suite'] = run(['setsid', 'bash', 'tests/install.sh'], workspace, output / 'mutation-suite.log')
    text = (output / 'mutation-suite.log').read_text() + (output / 'mutation-suite.stderr.log').read_text()
    # Attribute only PATH-specific behavioral failures, never the TOML/setup failure.
    path_failure = any(line.startswith('FAIL:') and any(word in line.lower() for word in ('path', 'bootstrap', 'managed director', 'refresh', 'directory already')) for line in text.splitlines())
    result['mutation_classification'] = ('NOT_DETECTED' if result['mutation_suite'] == 0 else
                                         'BEHAVIORAL_ASSERTION' if path_failure else 'HARNESS_ERROR')
    (workspace / 'environments/linux/install.sh').write_bytes(installer)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--controls-only', action='store_true')
    parser.add_argument('--out', type=Path, default=RECORD / 'post-run-diagnostic')
    args = parser.parse_args()
    args.out = args.out.resolve()
    if args.out.exists():
        raise SystemExit('Refusing to overwrite diagnostic output')
    args.out.mkdir(parents=True)
    doc = {'classification': 'POST_RUN_DIAGNOSTIC', 'adjudicates': False,
           'python_executable': str(Path(sys.executable).resolve()),
           'reference_commit': REFERENCE, 'broken_commit': BROKEN, 'attempts': []}
    with tempfile.TemporaryDirectory(prefix='verifier-v2-control-') as tmp:
        work = Path(tmp)
        snapshot(REFERENCE, work)
        doc['reference'] = evaluate(work, args.out / 'reference-control')
        # evaluate() uses the same candidate reference tests against the broken installer.
        ref = doc['reference']
        doc['controls_passed'] = all(ref[k] == 0 for k in ('oracle', 'empty_path', 'immutable_suite', 'candidate_suite', 'syntax_environments/linux/install.sh', 'syntax_tests/install.sh')) and ref['mutation_classification'] == 'BEHAVIORAL_ASSERTION'
    (args.out / 'summary.json').write_text(json.dumps(doc, indent=2) + '\n')
    if not doc['controls_passed']:
        raise SystemExit('Positive/negative control failed; no retained patch evaluated')
    if not args.controls_only:
        for patch in sorted((RECORD / 'runs').glob('*-coding-*/work-product.patch')):
            with tempfile.TemporaryDirectory(prefix='verifier-v2-candidate-') as tmp:
                work = Path(tmp)
                shutil.copytree(BASE, work, dirs_exist_ok=True)
                output = args.out / patch.parent.name
                output.mkdir()
                status = run(['patch', '--batch', '-p1', '-i', str(patch)], work, output / 'patch-apply.log')
                result = {'classification': 'POST_RUN_DIAGNOSTIC', 'label': patch.parent.name,
                          'patch_sha256': hashlib.sha256(patch.read_bytes()).hexdigest(), 'patch_apply': status}
                if status == 0:
                    result.update(evaluate(work, output / 'checks'))
                doc['attempts'].append(result)
    (args.out / 'summary.json').write_text(json.dumps(doc, indent=2) + '\n')


if __name__ == '__main__':
    main()
