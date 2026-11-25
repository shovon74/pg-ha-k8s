# L4: Point-in-time recovery (R5.3)

**Result: PASS**

- **What:** Marker A committed, T recorded in UTC+6, marker B committed after archive_timeout and archived, then `make restore TARGET_TIME=T` into the empty `pg-restore` namespace. A must be present and B absent.
- **Run:** 2026-11-25T15:44:22Z (UTC), 111 s
- **Reproduce:** `make test-pitr`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| The segment holding A was archived after T (within archive_timeout + margin) | PASS |
| The segment holding B was archived too, so recovery must stop at T rather than run out of WAL | PASS |
| make restore TARGET_TIME='2026-11-25 21:44:25+06' completed: 1 leader, 2 streaming replicas, 1 sync standby | PASS |
| Marker A (before T) is present | PASS |
| Marker B (after T) is absent | PASS |
| archive_mode is off on the restored primary | PASS |
| make restore-clean removed pg-restore (10.34 s) | PASS |

## Markers around T

Marker A `A-1795621463` committed at 15:44:23.900560 UTC. Target T = `2026-11-25 21:44:25+06` (2026-11-25 15:44:25 UTC). Source leader `pg-2`, timeline 33.

Marker B `B-1795621463` committed at 15:45:30.961044 UTC, 66.0 s after T, then the segment was closed by a WAL fill.

```console
$ q pg-rw.pg-ha.svc.cluster.local app "select id, t from pitr_marker where id like '%-1795621463' order by t"
A-1795621463 2026-11-25 15:44:23.90056+00
B-1795621463 2026-11-25 15:45:30.961044+00
```

## make restore TARGET_TIME=T

```console
$ NS=pg-restore TARGET_TIME='2026-11-25 21:44:25+06' scripts/restore.sh
Restoring into namespace pg-restore: target 2026-11-25 21:44:25+06, timeline latest
  pg-0 replica streaming timeline 34
  pg-1 sync_standby streaming timeline 34
  pg-2 leader running timeline 34
RESTORE_OK namespace=pg-restore target=2026-11-25 21:44:25+06 primary_ready=16.1s cluster_healthy=27.6s
```

```console
$ kubectl -n pg-restore logs pg-2 -c postgres | grep -E 'starting point-in-time recovery|recovery stopping|last completed transaction|selected new timeline|archive recovery complete|restore backup set|post-bootstrap' | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -10
2026-11-25 15:45:41.825 P00   INFO: repo1: restore backup set 20261125-154309F, recovery will start at 2026-11-25 15:43:09
2026-11-25 15:45:47.389 UTC [39] LOG:  starting point-in-time recovery to 2026-11-25 15:44:25+00
2026-11-25 15:45:47.868 UTC [39] LOG:  recovery stopping before commit of transaction 4608, time 2026-11-25 15:45:30.961369+00
2026-11-25 15:45:47.868 UTC [39] LOG:  last completed transaction was at log time 2026-11-25 15:44:23.901882+00
2026-11-25 15:45:47.894 UTC [39] LOG:  selected new timeline ID: 34
2026-11-25 15:45:47.997 UTC [39] LOG:  archive recovery complete
post-bootstrap: restored cluster, passwords of monitor, backup, app and app_ro reset
```

Backup set used: `20261125-154309F`. Recovery target timeline `latest`; the source was on timeline 33 at T.

## Result

```console
$ q pg-rw.pg-restore.svc.cluster.local app "select id, t from pitr_marker where id like '%-1795621463' order by t"
A-1795621463 2026-11-25 15:44:23.90056+00
```

End to end: 27.99 s from `make restore` to a healthy restored cluster.

| PITR restore end to end (s) | Target T | Source timeline |
|---:|---|---:|
| 27.99 | 2026-11-25 21:44:25+06 | 33 |
