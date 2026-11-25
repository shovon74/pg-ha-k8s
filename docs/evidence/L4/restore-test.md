# L4: Restore test Job, on demand (R4.5, R5.4)

**Result: PASS**

- **What:** `make test-restore`: a backup with the fingerprint recorded as annotations, then a Job from the `pg-restore-test` CronJob template restores it into emptyDir, starts Postgres with no TCP listener, compares the fingerprint, runs `pg_amcheck --install-missing` on the scratch copy and exits non-zero on any failure. A negative run with one wrong expected value must fail.
- **Run:** 2026-11-25T15:43:06Z (UTC), 63 s
- **Reproduce:** `make test-restore`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`

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
2026-11-25T15:43:09Z fingerprint recorded as annotations: seeded=yes rows.pgbench_branches=10 sum.pgbench_branches=3530232442 rows.pgbench_tellers=100 sum.pgbench_tellers=9319411032 rows.pgbench_accounts=1000000 sum.pgbench_accounts=1637876347759 
2026-11-25 15:43:26.777 P00   INFO: new backup label = 20261125-154309F
2026-11-25T15:43:36Z VERIFY_OK
2026-11-25T15:43:37Z BACKUP_JOB_OK
```

## Restore test Job (pg-restore-test template)

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-manual-154341
2026-11-25T15:43:43Z restoring backup 20261125-154309F to its consistent end point (--type=immediate)
2026-11-25T15:43:49Z recovered and promoted in 7 s; consistent recovery state reached at 0/6B000088
2026-11-25T15:43:50Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        9319411032             9319411032             PASS
2026-11-25T15:43:50Z pg_amcheck --install-missing (scratch instance only)
  3/831 relations (0%), 19238/21684 pages (88%)
831/831 relations (100%), 21684/21684 pages (100%)
2026-11-25T15:43:52Z RESTORE_TEST_OK backup=20261125-154309F total=10s
```

Job wall time 13.43 s, including scheduling.

## Negative run: a wrong expected value must fail the Job

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-negative '' RESTORE_TEST_INJECT_MISMATCH=1
2026-11-25T15:43:57Z restoring backup 20261125-154309F to its consistent end point (--type=immediate)
2026-11-25T15:43:57Z TEST HOOK: one expected value replaced
2026-11-25T15:44:03Z recovered and promoted in 7 s; consistent recovery state reached at 0/6B000088
2026-11-25T15:44:04Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        injected-mismatch      9319411032             FAIL
2026-11-25T15:44:04Z RESTORE_TEST_FAILED: fingerprint mismatch
2026-11-25 15:44:01.778 GMT [23] LOG:  listening on Unix socket "/tmp/.s.PGSQL.5432"
2026-11-25 15:44:01.790 GMT [26] LOG:  database system was interrupted; last known up at 2026-11-25 15:43:09 GMT
2026-11-25 15:44:01.919 GMT [26] LOG:  starting backup recovery with redo LSN 0/6A000028, checkpoint LSN 0/6A000080, on timeline ID 33
2026-11-25 15:44:01.944 GMT [26] LOG:  restored log file "00000021.history" from archive
2026-11-25 15:44:02.007 GMT [26] LOG:  restored log file "00000021000000000000006A" from archive
2026-11-25 15:44:02.039 GMT [26] LOG:  starting point-in-time recovery to earliest consistent point
2026-11-25 15:44:02.045 GMT [26] LOG:  redo starts at 0/6A000028
2026-11-25 15:44:02.107 GMT [26] LOG:  restored log file "00000021000000000000006B" from archive
2026-11-25 15:44:02.180 GMT [26] LOG:  completed backup recovery with redo LSN 0/6A000028 and end LSN 0/6B000088
2026-11-25 15:44:02.180 GMT [26] LOG:  consistent recovery state reached at 0/6B000088
2026-11-25 15:44:02.180 GMT [26] LOG:  recovery stopping after reaching consistency
2026-11-25 15:44:02.180 GMT [26] LOG:  redo done at 0/6B000088 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.13 s
2026-11-25 15:44:02.180 GMT [23] LOG:  database system is ready to accept read-only connections
2026-11-25 15:44:02.241 GMT [26] LOG:  restored log file "00000021000000000000006B" from archive
2026-11-25 15:44:02.302 GMT [26] LOG:  selected new timeline ID: 34
2026-11-25 15:44:02.380 GMT [26] LOG:  restored log file "00000021.history" from archive
2026-11-25 15:44:02.387 GMT [26] LOG:  archive recovery complete
2026-11-25 15:44:02.390 GMT [24] LOG:  checkpoint starting: end-of-recovery immediate wait
2026-11-25 15:44:02.406 GMT [24] LOG:  checkpoint complete: wrote 3 buffers (0.0%); 0 WAL file(s) added, 0 removed, 1 recycled; write=0.004 s, sync=0.002 s, total=0.020 s; sync files=2, longest=0.001 s, average=0.001 s; distance=16384 kB, estimate=16384 kB; lsn=0/6B000088, redo lsn=0/6B000088
2026-11-25 15:44:02.418 GMT [23] LOG:  database system is ready to accept connections
[exit code 1]
```
