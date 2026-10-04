# Offline suite reproducibility

`bash models/routing/opencode/eval/run-tests.sh` runs every test, reports
PASS/FAIL/SKIP counts and lists non-passing tests. A failure never prevents later
tests from executing. `--strict` also rejects skips. Counts are per test file;
a partial root-only skip makes that file SKIP even though other assertions run.
Exit 77 is a skip only with an explicit `SKIP:` reason; bare 77 is a failure.

Basic host tools are Bash, coreutils, git, patch, setsid (util-linux), grep and
Python 3. `/usr/bin/python3` with tomllib is required by system-interpreter
checks. Missing general suite tools result in explicit skips. Installer replay
and verifier controls additionally require direnv; a clean Ubuntu container
without it skips those tests instead of reporting candidate failure. WSL is not
a universal prerequisite: host-dependent branches are retained, the verifier's
headless credential stub is documented in the diagnostic record, and no new
stub or ADT_FORCE_WSL override suppresses coverage.

`reference-snapshot/` beside the existing base stores the three files from
`55da937` (`refs/pull/34/head`; PR #34 base was `7605022`). Provenance lists
source commit, ref, blob id and SHA-256. `tools/snapshot-verifier.py` supplies a
snapshot loader to the immutable verifier v2. It verifies inventory, hashes and
Git blob identity. Locally available historical objects get an additional
byte-parity check; absent objects produce NOTE, not error or SKIP. The frozen
verifier and General freeze manifest are not modified. Its old direct entry
point still needs the historical Git object; portable tests use the helper.

Container baseline: `ubuntu:24.04` plus git, python3 and patch (required to clone
and execute the portable subset); direnv is intentionally not installed. Clone
with `git clone --no-local --single-branch --branch chore/eval-reproducibility`
from the local Git source, using normal upload-pack negotiation, not copying
the object database. Assert `git cat-file -e 55da937` fails. Run as root, then
as an ordinary user from a writable clone. Root skips only unreadable-file
permission assertions; other fixture assertions still execute.

## Verified 2026-10-04 — POST_RUN_DIAGNOSTIC

Execution revision: `bfbf99b` (documentation added afterwards).

| Environment | Invocation | PASS | FAIL | SKIP |
|---|---|---:|---:|---:|
| Configured WSL workstation, ordinary user | `run-tests.sh --strict` | 57 | 0 | 0 |
| Ubuntu 24.04, fresh single-branch clone, root | `run-tests.sh` | 54 | 0 | 3 |
| Same clone, owned by ordinary user `eval` | `run-tests.sh` | 55 | 0 | 2 |

Container skips:

- `build-verifier-v2-test.sh`: direnv is absent, so installer controls cannot run.
- `gpt61-sol-build-screening-test.sh`: installer replay requires direnv; record
  hashes, retained evidence, accounting and adjudication still execute.
- Root only, `reviewer-fixture-v2-test.sh`: historical and per-variant
  unreadable-counter proofs require non-root; all other assertions execute.

The normal-clone check confirmed `55da937` is absent. `snapshot-loader-test.sh`
nevertheless validates exported bytes, blob identity and rejection of modified
content/provenance. On WSL the full verifier positive and negative controls pass.
Earlier container runs found missing direnv and a cwd-dependent test; these were
corrected before the final runs above. No inference probe was dispatched.

Reviewer gate: independent static review requested corrections to provenance
binding, exit-77 classification, runner coverage and overly broad prerequisite
gates. The corrections are implemented and exercised by the final suite. The
proposed WSL gate was removed after source inspection; real direnv absence was
confirmed by container replay. The test for corrupted snapshots covers the
standard-clone path independently of installer prerequisites. Deferred polish:
the test-directory override remains a documented internal test hook; provenance
export remains a one-time helper rather than a supported CLI.

## Prepared pull request

Title: `test: make offline routing evaluation reproducible`

Summary:
- Store a provenance-backed reference snapshot for PR-only commit `55da937`
  and use a loader beside the immutable verifier.
- Run every test with PASS/FAIL/SKIP aggregation, strict skip rejection and
  explicit host prerequisites; preserve portable and non-permission assertions.
- Add runner and snapshot-corruption regressions, and anchor suite cwd.

Validation: WSL strict 57/0/0; Ubuntu 24.04 root 54/0/3; non-root 55/0/2.
Skips and evidence boundaries are listed above. Frozen records, historical
adjudications and global routing are unchanged. Branch is prepared locally.
