# L4: Restore test Job, on demand (R4.5, R5.4)

**Result: PASS**

- **What:** `make test-restore`: a backup with the fingerprint recorded as annotations, then a Job from the `pg-restore-test` CronJob template restores it into emptyDir, starts Postgres with no TCP listener, compares the fingerprint, runs `pg_amcheck --install-missing` on the scratch copy and exits non-zero on any failure. A negative run with one wrong expected value must fail.
- **Run:** 2026-11-26T14:10:21Z (UTC), 71 s
- **Reproduce:** `make test-restore`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Backup with verify ok, fingerprint recorded as annotations | PASS |
| The restore test Job succeeded (RESTORE_TEST_OK) | PASS |
| Every fingerprint value matched the one recorded at backup time | PASS |
| pg_amcheck ran on the scratch copy and reported no corruption | PASS |
| The Job template mounts no PVC and no Service selects it; Postgres has listen_addresses = '' | PASS |
| The Job failed (non-zero exit) with RESTORE_TEST_FAILED: fingerprint mismatch | PASS |

## Backup with fingerprint annotations

```console
$ scripts/pgbr-job.sh pg-backup-l4 | grep -E 'fingerprint recorded|new backup label|VERIFY_OK|BACKUP_JOB_OK|FAILED'
2026-11-26T14:10:24Z fingerprint recorded as annotations: seeded=yes rows.pgbench_branches=10 sum.pgbench_branches=3530232442 rows.pgbench_tellers=100 sum.pgbench_tellers=9319411032 rows.pgbench_accounts=1000000 sum.pgbench_accounts=1637876347759 
2026-11-26 14:10:42.686 P00   INFO: new backup label = 20261126-141025F
2026-11-26T14:10:58Z VERIFY_OK
2026-11-26T14:10:59Z BACKUP_JOB_OK
```

## Restore test Job (pg-restore-test template)

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-manual-141102
2026-11-26T14:11:04Z restoring backup 20261126-141025F to its consistent end point (--type=immediate)
2026-11-26T14:11:11Z recovered and promoted in 8 s; consistent recovery state reached at 0/C1000190
2026-11-26T14:11:13Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        9319411032             9319411032             PASS
2026-11-26T14:11:13Z pg_amcheck --install-missing (scratch instance only)
  3/835 relations (0%), 19238/21726 pages (88%)
835/835 relations (100%), 21726/21726 pages (100%)
2026-11-26T14:11:14Z RESTORE_TEST_OK backup=20261126-141025F total=11s
```

Job wall time 15.73 s, including scheduling.

## Negative run: a wrong expected value must fail the Job

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-negative '' RESTORE_TEST_INJECT_MISMATCH=1
2026-11-26T14:11:20Z restoring backup 20261126-141025F to its consistent end point (--type=immediate)
2026-11-26T14:11:20Z TEST HOOK: one expected value replaced
2026-11-26T14:11:27Z recovered and promoted in 7 s; consistent recovery state reached at 0/C1000190
2026-11-26T14:11:29Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        injected-mismatch      9319411032             FAIL
2026-11-26T14:11:29Z RESTORE_TEST_FAILED: fingerprint mismatch
2026-11-26 14:11:26.054 GMT [23] LOG:  starting PostgreSQL 17.12 (Debian 17.12-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
2026-11-26 14:11:26.058 GMT [23] LOG:  listening on Unix socket "/tmp/.s.PGSQL.5432"
2026-11-26 14:11:26.071 GMT [26] LOG:  database system was interrupted; last known up at 2026-11-26 14:10:25 GMT
2026-11-26 14:11:26.246 GMT [26] LOG:  starting backup recovery with redo LSN 0/C1000060, checkpoint LSN 0/C10000B8, on timeline ID 43
2026-11-26 14:11:26.276 GMT [26] LOG:  restored log file "0000002B.history" from archive
2026-11-26 14:11:26.340 GMT [26] LOG:  restored log file "0000002B00000000000000C1" from archive
2026-11-26 14:11:26.371 GMT [26] LOG:  starting point-in-time recovery to earliest consistent point
2026-11-26 14:11:26.378 GMT [26] LOG:  redo starts at 0/C1000060
2026-11-26 14:11:26.423 GMT [26] LOG:  completed backup recovery with redo LSN 0/C1000060 and end LSN 0/C1000190
2026-11-26 14:11:26.423 GMT [26] LOG:  consistent recovery state reached at 0/C1000190
2026-11-26 14:11:26.423 GMT [26] LOG:  recovery stopping after reaching consistency
2026-11-26 14:11:26.423 GMT [26] LOG:  redo done at 0/C1000190 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.04 s
2026-11-26 14:11:26.423 GMT [23] LOG:  database system is ready to accept read-only connections
2026-11-26 14:11:26.485 GMT [26] LOG:  restored log file "0000002B00000000000000C1" from archive
2026-11-26 14:11:26.549 GMT [26] LOG:  selected new timeline ID: 44
2026-11-26 14:11:26.627 GMT [26] LOG:  restored log file "0000002B.history" from archive
2026-11-26 14:11:26.632 GMT [26] LOG:  archive recovery complete
2026-11-26 14:11:26.636 GMT [24] LOG:  checkpoint starting: end-of-recovery immediate wait
2026-11-26 14:11:26.657 GMT [24] LOG:  checkpoint complete: wrote 3 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.005 s, sync=0.003 s, total=0.025 s; sync files=2, longest=0.002 s, average=0.002 s; distance=0 kB, estimate=0 kB; lsn=0/C1000190, redo lsn=0/C1000190
2026-11-26 14:11:26.671 GMT [23] LOG:  database system is ready to accept connections
[exit code 1]
```
