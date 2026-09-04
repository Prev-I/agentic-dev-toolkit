# Superseded — pre-I2-fix R-API/R-BOUNDARY dispatch evidence

Archived here 2026-09-04, not deleted. These are the R-API and R-BOUNDARY
dispatches from the reviewer gate run that was originally reported as
"5/5 PASS". Both cases' sandbox override files at dispatch time
(`cases/R-API/api.sh`, `cases/R-BOUNDARY/pagination.sh`) still carried the
OLD pre-repair vulnerable patterns (see I2 in
`docs/evidence/2026-09-04-phase-r-execution.md`), so the "blocking" findings
captured here are genuine findings about a different, reintroduced
vulnerability — not detections of either case's seeded ground-truth defect.

Preserved for provenance and audit history. Not used as adjudication
evidence for the Reviewer gate — see `../R-API/` and `../R-BOUNDARY/` for
the post-repair rerun.
