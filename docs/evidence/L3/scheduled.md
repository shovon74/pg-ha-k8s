# L3: Scheduled backup (R4.1)

**Result: PASS**

- **What:** BACKUP_SCHEDULE set to `*/10 * * * *` through `make deploy`, one Job created by the CronJob controller itself runs full backup, expire and verify, then the default `0 20 * * *` (UTC) is restored.
- **Run:** 2026-11-25T07:18:06Z (UTC), 174 s
- **Reproduce:** `make test-backup-schedule`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`

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

Schedule set to `*/10 * * * *` (UTC) at 07:18:20 UTC.

## The scheduled Job

```console
$ kubectl -n pg-ha get job pg-backup-29926520 -o json | jq -r '{name: .metadata.name, created: .metadata.creationTimestamp, owner: [.metadata.ownerReferences[] | .kind + "/" + .name][0], manual: (.metadata.annotations["cronjob.kubernetes.io/instantiate"] // "no"), scheduled_at: (.metadata.annotations["batch.kubernetes.io/cronjob-scheduled-timestamp"] // "-"), completed: .status.completionTime, succeeded: .status.succeeded}'
{
  "name": "pg-backup-29926520",
  "created": "2026-11-25T07:20:00Z",
  "owner": "CronJob/pg-backup",
  "manual": "no",
  "scheduled_at": "2026-11-25T07:20:00Z",
  "completed": "2026-11-25T07:20:40Z",
  "succeeded": 1
}
```

```console
$ kubectl -n pg-ha logs job/pg-backup-29926520 | grep -vE 'command begin'
2026-11-25T07:20:01Z full backup
2026-11-25 07:20:02.493 P00   INFO: backup start archive = 0000001C0000000000000012, lsn = 0/12000028
2026-11-25 07:20:31.262 P00   INFO: backup stop archive = 0000001C0000000000000012, lsn = 0/12000158
2026-11-25 07:20:31.874 P00   INFO: new backup label = 20261125-072002F
2026-11-25 07:20:32.408 P00   INFO: full backup size = 180.2MB, file total = 1292
2026-11-25T07:20:32Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
2026-11-25 07:20:32.836 P00   INFO: expire command end: completed successfully (234ms)
2026-11-25T07:20:32Z verify
status: ok
archiveId: 17-1, total WAL checked: 12, total valid WAL: 12
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261125-071559F, status: valid, total files checked: 1292, total valid files: 1292
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261125-072002F, status: valid, total files checked: 1292, total valid files: 1292
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
2026-11-25T07:20:38Z VERIFY_OK
stanza: main
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 000000010000000000000004/0000001C0000000000000012

        full backup: 20261125-071559F
            timestamp start/stop: 2026-11-25 07:15:59+00 / 2026-11-25 07:16:14+00
            wal start/stop: 0000001C000000000000000F / 0000001C000000000000000F
            database size: 180.2MB, database backup size: 180.2MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB

        full backup: 20261125-072002F
            timestamp start/stop: 2026-11-25 07:20:02+00 / 2026-11-25 07:20:31+00
            wal start/stop: 0000001C0000000000000012 / 0000001C0000000000000012
            database size: 180.2MB, database backup size: 180.2MB
            repo1: backup set size: 10.4MB, backup size: 10.4MB
2026-11-25T07:20:38Z BACKUP_JOB_OK
```

## Default schedule restored

```console
$ kubectl -n pg-ha get cronjob pg-backup -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone,LAST:.status.lastScheduleTime
NAME        SCHEDULE     TZ        LAST
pg-backup   0 20 * * *   Etc/UTC   2026-11-25T07:20:00Z
```
