# L3: Backup after failover (R4.6)

**Result: PASS**

- **What:** One node failover (`docker stop` of the primary's k3d agent, then `docker start`, from the L2 harness), then archiving on the new timeline, `pgbackrest check`, and a full backup with verify, with no configuration change.
- **Run:** 2026-11-26T15:48:32Z (UTC), 221 s
- **Reproduce:** `make test-backup-failover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Node failover run passed (RTO, RPO 0, one primary, old primary rejoined) | PASS |
| Leadership moved to another member on a higher timeline | PASS |
| The new primary archived a segment within 150 s | PASS |
| The latest archived segment is on the new timeline (00000017) | PASS |
| No archive failures on the new primary during the check | PASS |
| pgbackrest check passes against the new primary | PASS |
| Backup completed with verify status ok | PASS |
| The backup started on the new timeline (00000017), so it was taken from the new primary | PASS |

## Failover: one node-stop run of the L2 harness

Before: leader `pg-0`, timeline 22. The full failover evidence is in [`failover-node-run.md`](failover-node-run.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.RVFnIClC7O.fo
run 1: RTO=22.83 s gap=22.93 s acked=172 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.42s PASS
RESULT L2 node: PASS (min 22.83 s, median 22.83 s, max 22.83 s over 1 runs) -> docs/evidence/L3/failover-node-run.md
```

After: leader `pg-2`, timeline 23 (WAL prefix `00000017`).

## Archiving on the new timeline

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor 'select inet_server_addr(), archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'
10.42.1.8 25 0 000000170000000000000055 2026-11-26 15:51:35.102767+00  
```

```console
$ JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-failover 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'
2026-11-26 15:51:38.871 P00   INFO: check repo1 (standby)
2026-11-26 15:51:38.882 P00   INFO: switch wal not performed because this is a standby
2026-11-26 15:51:38.883 P00   INFO: check repo1 configuration (primary)
2026-11-26 15:51:38.950 P00   INFO: check repo1 archive for WAL (primary)
2026-11-26 15:51:39.361 P00   INFO: WAL segment 000000170000000000000056 successfully archived to '/pg-ha/archive/main/17-1/0000001700000000/000000170000000000000056-e72355b38f687cece23f1d6af09e809553398b90.zst' on repo1
2026-11-26 15:51:39.363 P00   INFO: check command end: completed successfully (2520ms)
CHECK_OK
```

## Backup and verify after failover (no config change)

```console
$ scripts/pgbr-job.sh pg-backup-after-failover | grep -vE 'command begin'
2026-11-26T15:51:44Z pg-rw reachable after 2 attempts
2026-11-26T15:51:46Z fingerprint recorded as annotations: seeded=yes rows.pgbench_branches=10 sum.pgbench_branches=3530232442 rows.pgbench_tellers=100 sum.pgbench_tellers=9319411032 rows.pgbench_accounts=1000000 sum.pgbench_accounts=1637876347759 
2026-11-26T15:51:46Z full backup
2026-11-26 15:51:46.770 P00   INFO: backup start archive = 000000170000000000000058, lsn = 0/58000028
2026-11-26 15:52:03.796 P00   INFO: backup stop archive = 000000170000000000000058, lsn = 0/58000158
2026-11-26 15:52:04.047 P00   INFO: new backup label = 20261126-155146F
2026-11-26 15:52:04.233 P00   INFO: full backup size = 180.1MB, file total = 1293
2026-11-26T15:52:04Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
2026-11-26 15:52:04.554 P00   INFO: expire command end: completed successfully (149ms)
2026-11-26T15:52:04Z verify
status: ok
archiveId: 17-1, total WAL checked: 11, total valid WAL: 11
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-154350F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-154644F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-154755F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-155146F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
2026-11-26T15:52:10Z VERIFY_OK
stanza: main
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 00000016000000000000004E/000000170000000000000058

        full backup: 20261126-154350F
            timestamp start/stop: 2026-11-26 15:43:50+00 / 2026-11-26 15:44:07+00
            wal start/stop: 00000016000000000000004E / 00000016000000000000004E
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261126-154644F
            timestamp start/stop: 2026-11-26 15:46:44+00 / 2026-11-26 15:47:00+00
            wal start/stop: 000000160000000000000050 / 000000160000000000000050
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261126-154755F
            timestamp start/stop: 2026-11-26 15:47:55+00 / 2026-11-26 15:48:14+00
            wal start/stop: 000000160000000000000052 / 000000160000000000000052
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261126-155146F
            timestamp start/stop: 2026-11-26 15:51:46+00 / 2026-11-26 15:52:03+00
            wal start/stop: 000000170000000000000058 / 000000170000000000000058
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB
2026-11-26T15:52:10Z BACKUP_JOB_OK
```
