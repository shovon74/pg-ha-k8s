# L3: Garage, pgBackRest, archiving and on-demand backup

**Result: PASS**

- **What:** Garage from our manifests with an idempotent Admin API bootstrap, pgBackRest with every repo1-* setting in repo.conf and an encrypted repository, async WAL archiving added as Patroni conf.d/20-archive.yml, stanza and check as a Job over the TLS server, and `make backup` (full, expire, verify).
- **Run:** 2026-11-26T15:36:36Z (UTC), 96 s
- **Reproduce:** `make test-archive`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Garage is Ready on the infra node with its PVC bound | PASS |
| Garage runs single node with metadata and data fsync on | PASS |
| Bootstrap Job is idempotent: a rerun keeps layout, key and bucket | PASS |
| No repo1-* setting outside repo.conf (config lines or CLI options) | PASS |
| No credential value in any live ConfigMap, CronJob or rendered manifest | PASS |
| Repository encryption is aes-256-cbc, with the passphrase only in a Secret | PASS |
| Jobs list pg1..pg3 by headless-service DNS over TLS | PASS |
| Archiving is asynchronous with a 2 GiB queue cap (ADR-005) | PASS |
| archive_mode on with archive-push, restore_command via archive-get, and 10-base.yml settings kept (ssl on) | PASS |
| A new WAL segment was archived within 120 s (archive_timeout 60 s) | PASS |
| pg_stat_archiver: no new failures during the test | PASS |
| pg_stat_archiver: last failure (if any) is older than the last successful archive | PASS |
| stanza-create reruns cleanly on the existing stanza, and pgbackrest check passes | PASS |
| make backup completed: full backup, expire, verify status ok | PASS |
| The backup job script fails unless verify reports status ok (not only exit 0) | PASS |

## Garage (ADR-014)

```console
$ kubectl -n pg-ha get deploy,pvc,svc -l app.kubernetes.io/name=garage -o wide; kubectl -n pg-ha get pvc garage-data; kubectl -n pg-ha get pod -l app.kubernetes.io/name=garage -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image
No resources found in pg-ha namespace.
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
garage-data   Bound    pvc-750e168c-cc9a-492d-a8db-f01139e43335   5Gi        RWO            local-path     <unset>                 50m
POD                       NODE                 READY   IMAGE
garage-78b588844b-769mb   k3d-pg-ha-server-0   true    dxflrs/garage:v2.5.0@sha256:677e5b758e4425a325b811c425c026bf35a4bf42f7ddbaa773de3f4fd779a5a5
```

```console
$ printf '%s\n' "$BOOT"
curl: (7) Failed to connect to garage:3903 after 2 ms: Could not connect to server
layout: version 1 exists, kept
key: exists, kept
bucket: exists, kept
grant: read and write on bucket pgbackrest
BOOTSTRAP_OK
```

## pgBackRest configuration (ADR-009)

```console
$ cat deploy/pg/pgbackrest/repo.conf | grep -v '^#'
[global]
repo1-type=s3
repo1-s3-endpoint=http://garage.pg-ha.svc.cluster.local:3900
repo1-s3-bucket=pgbackrest
repo1-s3-region=garage
repo1-s3-uri-style=path
repo1-path=/pg-ha
repo1-cipher-type=aes-256-cbc
repo1-retention-full=7
```

```console
$ grep -rnE '^[[:space:]]*repo1-|--repo1-' deploy scripts tests --exclude=repo.conf --exclude=l3-archive.sh --exclude-dir=spikes || echo 'no repo1-* setting outside repo.conf'
no repo1-* setting outside repo.conf
```

## WAL archiving (Patroni conf.d/20-archive.yml)

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select name, setting from pg_settings where name in ('archive_mode','archive_command','archive_timeout','restore_command','ssl') order by 1"
archive_command pgbackrest --stanza=main archive-push "%p"
archive_mode on
archive_timeout 60
restore_command pgbackrest --stanza=main --no-archive-async archive-get %f "%p"
ssl on
```

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor 'select archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'
4 0 000000160000000000000042 2026-11-26 15:36:35.520598+00  
```

Failures counted before the stanza existed are expected: Postgres starts archiving before the stanza Job runs and retries each segment until it succeeds. The checks below therefore require no failure during this test, and that the last failure (if any) is older than the last successful archive. The pre-stanza failures are recorded in the history file.

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor 'select archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'
5 0 000000160000000000000043 2026-11-26 15:37:35.412447+00  
```

## Stanza (idempotent) and pgbackrest check, from Jobs over TLS

```console
$ JOB_WAIT=300 scripts/pgbr-job.sh pg-stanza-create 'pgbackrest --stanza=main --log-level-console=info stanza-create && pgbackrest --stanza=main --log-level-console=info check && echo STANZA_OK' | grep -vE 'command begin'
2026-11-26 15:37:38.960 P00   INFO: stanza-create for stanza 'main' on repo1
2026-11-26 15:37:38.973 P00   INFO: stanza 'main' already exists on repo1 and is valid
2026-11-26 15:37:38.974 P00   INFO: stanza-create command end: completed successfully (1242ms)
2026-11-26 15:37:39.083 P00   INFO: check repo1 (standby)
2026-11-26 15:37:39.091 P00   INFO: switch wal not performed because this is a standby
2026-11-26 15:37:39.092 P00   INFO: check repo1 configuration (primary)
2026-11-26 15:37:39.219 P00   INFO: check repo1 archive for WAL (primary)
2026-11-26 15:37:39.527 P00   INFO: WAL segment 000000160000000000000044 successfully archived to '/pg-ha/archive/main/17-1/0000001600000000/000000160000000000000044-44f024aac425c7d2a349afee49b094f9cbe0c4a7.zst' on repo1
2026-11-26 15:37:39.529 P00   INFO: check command end: completed successfully (543ms)
STANZA_OK
```

## On-demand backup: make backup (full, expire, verify)

```console
$ scripts/pgbr-job.sh pg-backup-manual-20261126153743 | grep -vE 'command begin'
2026-11-26T15:37:45Z pg-rw reachable after 3 attempts
2026-11-26T15:37:47Z fingerprint recorded as annotations: seeded=yes rows.pgbench_branches=10 sum.pgbench_branches=3530232442 rows.pgbench_tellers=100 sum.pgbench_tellers=9319411032 rows.pgbench_accounts=1000000 sum.pgbench_accounts=1637876347759 
2026-11-26T15:37:47Z full backup
2026-11-26 15:37:47.662 P00   INFO: backup start archive = 000000160000000000000046, lsn = 0/46000028
2026-11-26 15:38:01.820 P00   INFO: backup stop archive = 000000160000000000000046, lsn = 0/46000158
2026-11-26 15:38:02.062 P00   INFO: new backup label = 20261126-153747F
2026-11-26 15:38:02.219 P00   INFO: full backup size = 180.1MB, file total = 1293
2026-11-26T15:38:02Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
2026-11-26 15:38:02.342 P00   INFO: expire command end: completed successfully (50ms)
2026-11-26T15:38:02Z verify
status: ok
archiveId: 17-1, total WAL checked: 82, total valid WAL: 82
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-153747F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
2026-11-26T15:38:06Z VERIFY_OK
stanza: main
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 000000010000000000000001/000000160000000000000046

        full backup: 20261126-153747F
            timestamp start/stop: 2026-11-26 15:37:47+00 / 2026-11-26 15:38:01+00
            wal start/stop: 000000160000000000000046 / 000000160000000000000046
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB
2026-11-26T15:38:06Z BACKUP_JOB_OK
```
