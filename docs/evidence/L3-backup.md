# L3: backup, archiving, retention and verification

Generated from the per-part files in [`L3/`](L3/) each time a part runs. Timestamps are UTC.

Hand-written notes: [`L3-backup-history.md`](L3-backup-history.md).

| Part | Result | Checks passed | Details |
|---|---|---:|---|
| Garage, pgBackRest, archiving and on-demand backup | PASS | 15 of 15 | [`L3/archive.md`](L3/archive.md) |
| Scheduled backup (R4.1) | PASS | 4 of 4 | [`L3/scheduled.md`](L3/scheduled.md) |
| Retention enforcement | PASS | 9 of 9 | [`L3/retention.md`](L3/retention.md) |
| Backup after failover (R4.6) | PASS | 8 of 8 | [`L3/failover.md`](L3/failover.md) |
| Garage restart while writing | PASS | 4 of 4 | [`L3/garage-restart.md`](L3/garage-restart.md) |

## Garage, pgBackRest, archiving and on-demand backup

- **What:** Garage from our manifests with an idempotent Admin API bootstrap, pgBackRest with every repo1-* setting in repo.conf and an encrypted repository, async WAL archiving added as Patroni conf.d/20-archive.yml, stanza and check as a Job over the TLS server, and `make backup` (full, expire, verify).

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

## Scheduled backup (R4.1)

- **What:** BACKUP_SCHEDULE set to `*/10 * * * *` through `make deploy`, one Job created by the CronJob controller itself runs full backup, expire and verify, then the default `0 20 * * *` (UTC) is restored.

| Check | Result |
|---|---|
| The CronJob controller created a Job on the short schedule (not a manual Job) | PASS |
| The scheduled Job completed | PASS |
| Its verify reported status ok | PASS |
| Schedule restored to the default (0 20 * * * UTC) | PASS |

## Retention enforcement

- **What:** Three full backups from the CronJob template with a temporary `PGBACKREST_REPO1_RETENTION_FULL=2` on those Jobs only, proving the oldest fulls and their WAL are expired, then a normal run with repo.conf's `repo1-retention-full=7` keeping every full.

| Check | Result |
|---|---|
| Backup 1 (20261126-154057F) completed with verify status ok | PASS |
| Backup 2 (20261126-154350F) completed with verify status ok | PASS |
| Backup 3 (20261126-154644F) completed with verify status ok | PASS |
| Exactly the 2 newest fulls remain | PASS |
| The oldest backup from before the test (20261126-153747F) and backup 1 (20261126-154057F) were expired | PASS |
| WAL older than the oldest kept backup was expired with it (archive min = its start WAL) | PASS |
| Archive min moved past the expired backup's start WAL (00000016000000000000004C) | PASS |
| repo.conf still says repo1-retention-full=7 and the CronJob sets no retention override | PASS |
| A normal run (retention 7) keeps all 3 fulls | PASS |

## Backup after failover (R4.6)

- **What:** One node failover (`docker stop` of the primary's k3d agent, then `docker start`, from the L2 harness), then archiving on the new timeline, `pgbackrest check`, and a full backup with verify, with no configuration change.

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

## Garage restart while writing

- **What:** `kubectl rollout restart deploy/garage` while the probe writes every 500 ms and about 5 MB of WAL is generated every 2 s. Measures when archiving succeeds again and when the .ready backlog drains, with no manual action. The bound is 120 s after Garage is Ready.

| Check | Result |
|---|---|
| Archiving succeeded again on its own within 120 s of Garage being Ready | PASS |
| The .ready backlog drained (no permanent stall) | PASS |
| Writes through pg-rw were not blocked by the outage (max gap under 3 s) | PASS |
| pgbackrest check passes after the restart | PASS |
