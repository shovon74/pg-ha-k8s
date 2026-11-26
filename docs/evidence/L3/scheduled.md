# L3: Scheduled backup (R4.1)

**Result: PASS**

- **What:** BACKUP_SCHEDULE set to `*/10 * * * *` through `make deploy`, one Job created by the CronJob controller itself runs full backup, expire and verify, then the default `0 20 * * *` (UTC) is restored.
- **Run:** 2026-11-26T15:38:12Z (UTC), 156 s
- **Reproduce:** `make test-backup-schedule`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| The CronJob controller created a Job on the short schedule (not a manual Job) | PASS |
| The scheduled Job completed | PASS |
| Its verify reported status ok | PASS |
| Schedule restored to the default (0 20 * * * UTC) | PASS |

## Short schedule for the evidence run

```console
$ kubectl -n pg-ha get cronjob pg-backup -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone,LAST:.status.lastScheduleTime
NAME        SCHEDULE       TZ        LAST
pg-backup   */10 * * * *   Etc/UTC   <none>
```

Schedule set to `*/10 * * * *` (UTC) at 15:38:28 UTC.

## The scheduled Job

```console
$ kubectl -n pg-ha get job pg-backup-29928460 -o json | jq -r '{name: .metadata.name, created: .metadata.creationTimestamp, owner: [.metadata.ownerReferences[] | .kind + "/" + .name][0], manual: (.metadata.annotations["cronjob.kubernetes.io/instantiate"] // "no"), scheduled_at: (.metadata.annotations["batch.kubernetes.io/cronjob-scheduled-timestamp"] // "-"), completed: .status.completionTime, succeeded: .status.succeeded}'
{
  "name": "pg-backup-29928460",
  "created": "2026-11-26T15:40:00Z",
  "owner": "CronJob/pg-backup",
  "manual": "no",
  "scheduled_at": "2026-11-26T15:40:00Z",
  "completed": "2026-11-26T15:40:26Z",
  "succeeded": 1
}
```

```console
$ kubectl -n pg-ha logs job/pg-backup-29928460 | grep -vE 'command begin'
2026-11-26T15:40:01Z pg-rw reachable after 2 attempts
2026-11-26T15:40:02Z fingerprint recorded as annotations: seeded=yes rows.pgbench_branches=10 sum.pgbench_branches=3530232442 rows.pgbench_tellers=100 sum.pgbench_tellers=9319411032 rows.pgbench_accounts=1000000 sum.pgbench_accounts=1637876347759 
2026-11-26T15:40:02Z full backup
2026-11-26 15:40:03.296 P00   INFO: backup start archive = 000000160000000000000049, lsn = 0/49000028
2026-11-26 15:40:17.991 P00   INFO: backup stop archive = 000000160000000000000049, lsn = 0/49000158
2026-11-26 15:40:18.236 P00   INFO: new backup label = 20261126-154002F
2026-11-26 15:40:18.385 P00   INFO: full backup size = 180.1MB, file total = 1293
2026-11-26T15:40:18Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
2026-11-26 15:40:18.558 P00   INFO: expire command end: completed successfully (76ms)
2026-11-26T15:40:18Z verify
status: ok
archiveId: 17-1, total WAL checked: 85, total valid WAL: 85
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-153747F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261126-154002F, status: valid, total files checked: 1293, total valid files: 1293
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
2026-11-26T15:40:23Z VERIFY_OK
stanza: main
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 000000010000000000000001/000000160000000000000049

        full backup: 20261126-153747F
            timestamp start/stop: 2026-11-26 15:37:47+00 / 2026-11-26 15:38:01+00
            wal start/stop: 000000160000000000000046 / 000000160000000000000046
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261126-154002F
            timestamp start/stop: 2026-11-26 15:40:02+00 / 2026-11-26 15:40:17+00
            wal start/stop: 000000160000000000000049 / 000000160000000000000049
            database size: 180.1MB, database backup size: 180.1MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB
2026-11-26T15:40:23Z BACKUP_JOB_OK
```

## Default schedule restored

```console
$ kubectl -n pg-ha get cronjob pg-backup -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone,LAST:.status.lastScheduleTime
NAME        SCHEDULE     TZ        LAST
pg-backup   0 20 * * *   Etc/UTC   2026-11-26T15:40:00Z
```
