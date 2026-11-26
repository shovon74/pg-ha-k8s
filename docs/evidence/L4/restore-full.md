# L4: Full restore into an empty namespace (R5.1)

**Result: FAIL**

- **What:** `make restore` with no target: the whole cluster restored from Garage into the empty `pg-restore` namespace through Patroni's custom bootstrap, to the end of the archive on the latest timeline. Compared with the source, then removed with `make restore-clean`.
- **Run:** 2026-11-26T15:54:16Z (UTC), 69 s
- **Reproduce:** `make test-restore-full`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Timeline history files are present for every timeline switch up to 23 (found 2, need 22) | **FAIL** |
| make restore completed: 1 leader, 2 streaming replicas, 1 sync standby in pg-restore | PASS |
| Row counts and checksums of the seeded tables match the source | PASS |
| The marker row written just before the restore is present | PASS |
| Restored cluster is on a new timeline above the source's (24 > 23) | PASS |
| archive_mode is off on the restored primary | PASS |
| The restored primary archived nothing | PASS |
| The source archive has no WAL on the restored timeline (00000018) | PASS |
| Passwords from this namespace's Secret work on the restored cluster (post_bootstrap reset) | PASS |
| make restore-clean deleted only the pg-restore namespace and its PVCs (10.71 s) | PASS |

## Before: source and repository

Source leader `pg-2` on timeline 23. Source fingerprint (rows and hashtext sums of the seeded tables): rows.pgbench_accounts=1000000 rows.pgbench_branches=10 rows.pgbench_tellers=100 sum.pgbench_accounts=1637876347759 sum.pgbench_branches=3530232442 sum.pgbench_tellers=9319411032.

History files in the repository archive: 2 (00000016.history to 00000017.history). WAL directories: 0000001600000000 0000001700000000.

Marker row `full-1795708469` written and archived before the restore.

## make restore (latest)

```console
$ NS=pg-restore scripts/restore.sh
Restoring into namespace pg-restore: target latest (end of the archive), timeline latest
  pg-0 replica streaming timeline 24
  pg-1 leader running timeline 24
  pg-2 sync_standby streaming timeline 24
RESTORE_OK namespace=pg-restore target=latest primary_ready=22.5s cluster_healthy=33.8s
```

Restore wall time 34.15 s. Restored leader `pg-1` on timeline 24.

```console
$ kubectl -n pg-restore logs pg-1 -c postgres | grep -E 'Running custom bootstrap|restore-bootstrap|restore command end|recovery stopping|redo done|selected new timeline|archive recovery complete|post-bootstrap|bootstrap from leader|replica has been created' | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -14
2026-11-26 15:54:40,765 INFO: Running custom bootstrap script: sh /etc/patroni/scripts/restore-bootstrap.sh '' 'latest'
2026-11-26 15:54:46.488 P00   INFO: restore command end: completed successfully (5688ms)
restore-bootstrap: restore done, recovery is driven by Patroni's recovery_conf
2026-11-26 15:54:49.516 UTC [40] LOG:  redo done at 0/60FFFE50 system usage: CPU: user: 0.42 s, system: 0.25 s, elapsed: 2.10 s
2026-11-26 15:54:49.937 UTC [40] LOG:  selected new timeline ID: 24
2026-11-26 15:54:50.029 UTC [40] LOG:  archive recovery complete
post-bootstrap: restored cluster, passwords of monitor, backup, app and app_ro reset
```

## Restored data and isolation

```console
$ join -t= /tmp/tmp.LklJRShuKs/src /tmp/tmp.LklJRShuKs/dst | awk -F= '{printf "%-24s source %-22s restored %-22s %s\n", $1, $2, $3, ($2 == $3 ? "match" : "MISMATCH")}'
rows.pgbench_accounts    source 1000000                restored 1000000                match
rows.pgbench_branches    source 10                     restored 10                     match
rows.pgbench_tellers     source 100                    restored 100                    match
sum.pgbench_accounts     source 1637876347759          restored 1637876347759          match
sum.pgbench_branches     source 3530232442             restored 3530232442             match
sum.pgbench_tellers      source 9319411032             restored 9319411032             match
```

```console
$ q pg-rw.pg-restore.svc.cluster.local monitor "select name, setting from pg_settings where name in ('archive_mode', 'archive_command') order by 1"
archive_command (disabled)
archive_mode off
```

## make restore-clean

```console
$ NS=pg-restore scripts/restore-clean.sh
persistentvolumeclaim "data-pg-0" deleted from pg-restore namespace
persistentvolumeclaim "data-pg-1" deleted from pg-restore namespace
persistentvolumeclaim "data-pg-2" deleted from pg-restore namespace
namespace "pg-restore" deleted
deleted namespace pg-restore and its PVCs
```

| Restore wall time (s) | Restored timeline | Source timeline | History files |
|---:|---:|---:|---:|
| 34.15 | 24 | 23 | 2 |
