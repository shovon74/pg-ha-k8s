# L3: Backup after failover (R4.6)

**Result: PASS**

- **What:** One node failover (`docker stop` of the primary's k3d agent, then `docker start`, from the L2 harness), then archiving on the new timeline, `pgbackrest check`, and a full backup with verify, with no configuration change.
- **Run:** 2026-11-25T13:35:33Z (UTC), 218 s
- **Reproduce:** `make test-backup-failover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Node failover run passed (RTO, RPO 0, one primary, old primary rejoined) | PASS |
| Leadership moved to another member on a higher timeline | PASS |
| The new primary archived a segment within 150 s | PASS |
| The latest archived segment is on the new timeline (00000010) | PASS |
| No archive failures on the new primary during the check | PASS |
| pgbackrest check passes against the new primary | PASS |
| Backup completed with verify status ok | PASS |
| The backup started on the new timeline (00000010), so it was taken from the new primary | PASS |

## Failover: one node-stop run of the L2 harness

Before: leader `pg-2`, timeline 15. The full failover evidence is in [`failover-node-run.md`](failover-node-run.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.XxUJ434hlE.fo
run 1: RTO=23.09 s gap=23.09 s acked=173 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.18s PASS
RESULT L2 node: PASS (min 23.09 s, median 23.09 s, max 23.09 s over 1 runs) -> docs/evidence/L3/failover-node-run.md
```

After: leader `pg-1`, timeline 16 (WAL prefix `00000010`).

## Archiving on the new timeline

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor 'select inet_server_addr(), archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'
10.42.4.6 15 0 00000010000000000000003A 2026-11-25 13:38:36.34497+00  
```

```console
$ JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-failover 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'
2026-11-25 13:38:39.535 P00   INFO: check repo1 (standby)
2026-11-25 13:38:39.545 P00   INFO: switch wal not performed because this is a standby
2026-11-25 13:38:39.545 P00   INFO: check repo1 configuration (primary)
2026-11-25 13:38:39.603 P00   INFO: check repo1 archive for WAL (primary)
2026-11-25 13:38:40.002 P00   INFO: WAL segment 00000010000000000000003B successfully archived to '/pg-ha/archive/main/17-1/0000001000000000/00000010000000000000003B-e034eb5cfb3c42f829af3016d9c82650c0f63587.zst' on repo1
2026-11-25 13:38:40.004 P00   INFO: check command end: completed successfully (594ms)
CHECK_OK
```

## Backup and verify after failover (no config change)

```console
$ scripts/pgbr-job.sh pg-backup-after-failover | grep -vE 'command begin'
2026-11-25T13:38:44Z full backup
2026-11-25 13:38:44.663 P00   INFO: backup start archive = 00000010000000000000003D, lsn = 0/3D000028
2026-11-25 13:39:01.277 P00   INFO: backup stop archive = 00000010000000000000003D, lsn = 0/3D000158
2026-11-25 13:39:01.762 P00   INFO: new backup label = 20261125-133844F
2026-11-25 13:39:01.915 P00   INFO: full backup size = 180MB, file total = 1288
2026-11-25T13:39:02Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
2026-11-25 13:39:02.154 P00   INFO: expire command end: completed successfully (103ms)
2026-11-25T13:39:02Z verify
status: ok
archiveId: 17-1, total WAL checked: 71, total valid WAL: 71
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261125-130110F, status: valid, total files checked: 1270, total valid files: 1270
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261125-130203F, status: valid, total files checked: 1283, total valid files: 1283
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261125-133844F, status: valid, total files checked: 1288, total valid files: 1288
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
2026-11-25T13:39:07Z VERIFY_OK
stanza: main
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 000000010000000000000001/00000010000000000000003D

        full backup: 20261125-130110F
            timestamp start/stop: 2026-11-25 13:01:10+00 / 2026-11-25 13:01:23+00
            wal start/stop: 000000010000000000000007 / 000000010000000000000007
            database size: 29.7MB, database backup size: 29.7MB
            repo1: backup set size: 3.6MB, backup size: 3.6MB

        full backup: 20261125-130203F
            timestamp start/stop: 2026-11-25 13:02:03+00 / 2026-11-25 13:02:17+00
            wal start/stop: 000000010000000000000010 / 000000010000000000000010
            database size: 179.4MB, database backup size: 179.4MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261125-133844F
            timestamp start/stop: 2026-11-25 13:38:44+00 / 2026-11-25 13:39:01+00
            wal start/stop: 00000010000000000000003D / 00000010000000000000003D
            database size: 180MB, database backup size: 180MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB
2026-11-25T13:39:08Z BACKUP_JOB_OK
```
