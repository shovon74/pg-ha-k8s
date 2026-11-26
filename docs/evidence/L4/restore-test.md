# L4: Restore test Job, on demand (R4.5, R5.4)

**Result: FAIL**

- **What:** `make test-restore`: a backup with the fingerprint recorded as annotations, then a Job from the `pg-restore-test` CronJob template restores it into emptyDir, starts Postgres with no TCP listener, compares the fingerprint, runs `pg_amcheck --install-missing` on the scratch copy and exits non-zero on any failure. A negative run with one wrong expected value must fail.
- **Run:** 2026-11-25T17:25:44Z (UTC), 35 s
- **Reproduce:** `make test-restore`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Backup with verify ok, fingerprint recorded as annotations | **FAIL** |
| The restore test Job succeeded (RESTORE_TEST_OK) | PASS |
| Every fingerprint value matched the one recorded at backup time | PASS |
| pg_amcheck ran on the scratch copy and reported no corruption | PASS |
| The Job template mounts no PVC and no Service selects it; Postgres has listen_addresses = '' | PASS |
| The Job failed (non-zero exit) with RESTORE_TEST_FAILED: fingerprint mismatch | PASS |

## Backup with fingerprint annotations

```console
$ scripts/pgbr-job.sh pg-backup-l4 | grep -E 'fingerprint recorded|new backup label|VERIFY_OK|BACKUP_JOB_OK|FAILED'
2026-11-25T17:25:45Z FINGERPRINT_FAILED
[exit code 1]
```

## Restore test Job (pg-restore-test template)

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-manual-172549
2026-11-25T17:25:51Z restoring backup 20261125-154309F to its consistent end point (--type=immediate)
2026-11-25T17:25:58Z recovered and promoted in 8 s; consistent recovery state reached at 0/6B000088
2026-11-25T17:26:00Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        9319411032             9319411032             PASS
2026-11-25T17:26:00Z pg_amcheck --install-missing (scratch instance only)
  3/831 relations (0%), 19238/21684 pages (88%)
831/831 relations (100%), 21684/21684 pages (100%)
2026-11-25T17:26:01Z RESTORE_TEST_OK backup=20261125-154309F total=11s
```

Job wall time 15.58 s, including scheduling.

## Negative run: a wrong expected value must fail the Job

```console
$ CRONJOB=pg-restore-test scripts/pgbr-job.sh pg-restore-test-negative '' RESTORE_TEST_INJECT_MISMATCH=1
2026-11-25T17:26:08Z restoring backup 20261125-154309F to its consistent end point (--type=immediate)
2026-11-25T17:26:08Z TEST HOOK: one expected value replaced
2026-11-25T17:26:14Z recovered and promoted in 8 s; consistent recovery state reached at 0/6B000088
2026-11-25T17:26:15Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        injected-mismatch      9319411032             FAIL
2026-11-25T17:26:15Z RESTORE_TEST_FAILED: fingerprint mismatch
2026-11-25 17:26:13.110 GMT [26] LOG:  completed backup recovery with redo LSN 0/6A000028 and end LSN 0/6B000088
2026-11-25 17:26:13.110 GMT [26] LOG:  consistent recovery state reached at 0/6B000088
2026-11-25 17:26:13.110 GMT [26] LOG:  recovery stopping after reaching consistency
2026-11-25 17:26:13.110 GMT [26] LOG:  redo done at 0/6B000088 system usage: CPU: user: 0.00 s, system: 0.01 s, elapsed: 0.49 s
2026-11-25 17:26:13.110 GMT [23] LOG:  database system is ready to accept read-only connections
2026-11-25 17:26:13.171 GMT [26] LOG:  restored log file "00000021000000000000006B" from archive
2026-11-25 17:26:13.239 GMT [26] LOG:  restored log file "00000022.history" from archive
2026-11-25 17:26:13.271 GMT [26] LOG:  restored log file "00000023.history" from archive
2026-11-25 17:26:13.302 GMT [26] LOG:  restored log file "00000024.history" from archive
2026-11-25 17:26:13.329 GMT [26] LOG:  restored log file "00000025.history" from archive
2026-11-25 17:26:13.356 GMT [26] LOG:  restored log file "00000026.history" from archive
2026-11-25 17:26:13.382 GMT [26] LOG:  restored log file "00000027.history" from archive
2026-11-25 17:26:13.415 GMT [26] LOG:  restored log file "00000028.history" from archive
2026-11-25 17:26:13.450 GMT [26] LOG:  restored log file "00000029.history" from archive
2026-11-25 17:26:13.484 GMT [26] LOG:  selected new timeline ID: 42
2026-11-25 17:26:13.569 GMT [26] LOG:  restored log file "00000021.history" from archive
2026-11-25 17:26:13.578 GMT [26] LOG:  archive recovery complete
2026-11-25 17:26:13.581 GMT [24] LOG:  checkpoint starting: end-of-recovery immediate wait
2026-11-25 17:26:13.604 GMT [24] LOG:  checkpoint complete: wrote 3 buffers (0.0%); 0 WAL file(s) added, 0 removed, 1 recycled; write=0.006 s, sync=0.002 s, total=0.026 s; sync files=2, longest=0.001 s, average=0.001 s; distance=16384 kB, estimate=16384 kB; lsn=0/6B000088, redo lsn=0/6B000088
2026-11-25 17:26:13.642 GMT [23] LOG:  database system is ready to accept connections
[exit code 1]
```
