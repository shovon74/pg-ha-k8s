# Runbook: point-in-time recovery (PITR)

Restores the cluster as it was at a given moment into the empty namespace `pg-restore` (ADR-010, R5.3). The source cluster is not touched. Read [`restore.md`](restore.md) first: the steps and checks are the same, plus a target time.

## 1. Choose the target time, with an offset

The VM runs in UTC and the lead works in UTC+6, so **a timezone offset is required**. The script refuses a time without one.

```text
2026-11-25 21:40:00+06     same moment as 2026-11-25 15:40:00+00
```

Recovery stops at the last transaction committed **at or before** the target. A transaction committed after it is not restored.

The target must be later than the end of some backup, and WAL up to the target must be in the archive. To check the backups and the archive range:

```bash
scripts/pgbr-job.sh pg-info 'pgbackrest --stanza=main info'
```

The last archived WAL is at most `archive_timeout` (60 s) behind the primary on a quiet system, so for a target in the last minute or so, wait first.

## 2. Restore

```bash
make restore-clean                       # only if pg-restore exists
make restore NS=pg-restore TARGET_TIME='2026-11-25 21:40:00+06'
```

pgBackRest picks the newest backup that ends before the target. Patroni recovers along timeline `latest` (override with `TARGET_TIMELINE=<n>`), stops at the target and promotes. The replicas then clone from the restored primary. `archive_mode` is off, so nothing is written to the source repository.

## 3. Confirm where recovery stopped

```bash
kubectl -n pg-restore logs pg-0 -c postgres | grep -E 'starting point-in-time recovery|recovery stopping|last completed transaction'
```

Expected lines:

- `starting point-in-time recovery to 2026-11-25 15:40:00+00`
- `recovery stopping before commit of transaction ..., time ...`
- `last completed transaction was at log time ...`

Then check your own data through `pg-rw.pg-restore.svc.cluster.local`.

## 4. Use or discard

- To extract data, read it from `pg-restore` and copy it to the source with your own tooling. This runbook never writes to the source.
- To discard it:

```bash
make restore-clean
```

## Proof

`make test-pitr` commits marker A, records T in UTC+6, commits marker B after `archive_timeout`, restores to T, and requires A present and B absent. Evidence: `docs/evidence/L4/pitr.md`.
