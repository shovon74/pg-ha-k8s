# L4: restore, PITR and restore verification

Generated from the per-part files in [`L4/`](L4/) each time a part runs. Timestamps are UTC.

Hand-written notes: [`L4-restore-history.md`](L4-restore-history.md).

| Part | Result | Checks passed | Details |
|---|---|---:|---|
| Full restore into an empty namespace (R5.1) | PASS | 10 of 10 | [`L4/restore-full.md`](L4/restore-full.md) |
| Point-in-time recovery (R5.3) | PASS | 7 of 7 | [`L4/pitr.md`](L4/pitr.md) |
| Restore test Job, on demand (R4.5, R5.4) | FAIL | 5 of 6 | [`L4/restore-test.md`](L4/restore-test.md) |
| Restore test Job, scheduled (R4.5) | PASS | 4 of 4 | [`L4/restore-scheduled.md`](L4/restore-scheduled.md) |

## Full restore into an empty namespace (R5.1)

- **What:** `make restore` with no target: the whole cluster restored from Garage into the empty `pg-restore` namespace through Patroni's custom bootstrap, to the end of the archive on the latest timeline. Compared with the source, then removed with `make restore-clean`.

| Check | Result |
|---|---|
| Timeline history files are present for every timeline switch up to 37 (found 36, need 36) | PASS |
| make restore completed: 1 leader, 2 streaming replicas, 1 sync standby in pg-restore | PASS |
| Row counts and checksums of the seeded tables match the source | PASS |
| The marker row written just before the restore is present | PASS |
| Restored cluster is on a new timeline above the source's (38 > 37) | PASS |
| archive_mode is off on the restored primary | PASS |
| The restored primary archived nothing | PASS |
| The source archive has no WAL on the restored timeline (00000026) | PASS |
| Passwords from this namespace's Secret work on the restored cluster (post_bootstrap reset) | PASS |
| make restore-clean deleted only the pg-restore namespace and its PVCs (12.64 s) | PASS |

## Point-in-time recovery (R5.3)

- **What:** Marker A committed, T recorded in UTC+6, marker B committed after archive_timeout and archived, then `make restore TARGET_TIME=T` into the empty `pg-restore` namespace. A must be present and B absent.

| Check | Result |
|---|---|
| The segment holding A was archived after T (within archive_timeout + margin) | PASS |
| The segment holding B was archived too, so recovery must stop at T rather than run out of WAL | PASS |
| make restore TARGET_TIME='2026-11-25 21:44:25+06' completed: 1 leader, 2 streaming replicas, 1 sync standby | PASS |
| Marker A (before T) is present | PASS |
| Marker B (after T) is absent | PASS |
| archive_mode is off on the restored primary | PASS |
| make restore-clean removed pg-restore (10.34 s) | PASS |

## Restore test Job, on demand (R4.5, R5.4)

- **What:** `make test-restore`: a backup with the fingerprint recorded as annotations, then a Job from the `pg-restore-test` CronJob template restores it into emptyDir, starts Postgres with no TCP listener, compares the fingerprint, runs `pg_amcheck --install-missing` on the scratch copy and exits non-zero on any failure. A negative run with one wrong expected value must fail.

| Check | Result |
|---|---|
| Backup with verify ok, fingerprint recorded as annotations | **FAIL** |
| The restore test Job succeeded (RESTORE_TEST_OK) | PASS |
| Every fingerprint value matched the one recorded at backup time | PASS |
| pg_amcheck ran on the scratch copy and reported no corruption | PASS |
| The Job template mounts no PVC and no Service selects it; Postgres has listen_addresses = '' | PASS |
| The Job failed (non-zero exit) with RESTORE_TEST_FAILED: fingerprint mismatch | PASS |

## Restore test Job, scheduled (R4.5)

- **What:** The `pg-restore-test` CronJob deployed with a short schedule (`*/5 * * * *`), a Job created by the CronJob itself (not `make`) checked for RESTORE_TEST_OK, then the default daily 21:00 UTC schedule restored.

| Check | Result |
|---|---|
| Deployed with RESTORE_TEST_SCHEDULE='*/5 * * * *' | PASS |
| The CronJob created a Job on its own schedule | PASS |
| The scheduled restore test succeeded (RESTORE_TEST_OK) | PASS |
| Default schedule restored (0 21 * * *) | PASS |
