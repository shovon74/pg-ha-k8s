# L4: Point-in-time recovery (R5.3)

**Result: PASS**

- **What:** Marker A committed, T recorded in UTC+6, marker B committed after archive_timeout and archived, then `make restore TARGET_TIME=T` into the empty `pg-restore` namespace. A must be present and B absent.
- **Run:** 2026-11-26T15:55:26Z (UTC), 115 s
- **Reproduce:** `make test-pitr`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| The segment holding A was archived after T (within archive_timeout + margin) | PASS |
| The segment holding B was archived too, so recovery must stop at T rather than run out of WAL | PASS |
| make restore TARGET_TIME='2026-11-26 21:55:28+06' completed: 1 leader, 2 streaming replicas, 1 sync standby | PASS |
| Marker A (before T) is present | PASS |
| Marker B (after T) is absent | PASS |
| archive_mode is off on the restored primary | PASS |
| make restore-clean removed pg-restore (10.98 s) | PASS |

## Markers around T

Marker A `A-1795708526` committed at 15:55:27.087613 UTC. Target T = `2026-11-26 21:55:28+06` (2026-11-26 15:55:28 UTC). Source leader `pg-2`, timeline 23.

Marker B `B-1795708526` committed at 15:56:34.094891 UTC, 66.1 s after T, then the segment was closed by a WAL fill.

```console
$ q pg-rw.pg-ha.svc.cluster.local app "select id, t from pitr_marker where id like '%-1795708526' order by t"
A-1795708526 2026-11-26 15:55:27.087613+00
B-1795708526 2026-11-26 15:56:34.094891+00
```

## make restore TARGET_TIME=T

```console
$ NS=pg-restore TARGET_TIME='2026-11-26 21:55:28+06' scripts/restore.sh
Restoring into namespace pg-restore: target 2026-11-26 21:55:28+06, timeline latest
  pg-0 replica streaming timeline 24
  pg-1 sync_standby streaming timeline 24
  pg-2 leader running timeline 24
RESTORE_OK namespace=pg-restore target=2026-11-26 21:55:28+06 primary_ready=20.5s cluster_healthy=32.1s
```

```console
$ kubectl -n pg-restore logs pg-2 -c postgres | grep -E 'starting point-in-time recovery|recovery stopping|last completed transaction|selected new timeline|archive recovery complete|restore backup set|post-bootstrap' | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -10
2026-11-26 15:56:46.801 P00   INFO: repo1: restore backup set 20261126-155146F, recovery will start at 2026-11-26 15:51:46
2026-11-26 15:56:52.480 UTC [39] LOG:  starting point-in-time recovery to 2026-11-26 15:55:28+00
2026-11-26 15:56:54.181 UTC [39] LOG:  recovery stopping before commit of transaction 4242, time 2026-11-26 15:56:34.095234+00
2026-11-26 15:56:54.181 UTC [39] LOG:  last completed transaction was at log time 2026-11-26 15:55:27.088274+00
2026-11-26 15:56:54.211 UTC [39] LOG:  selected new timeline ID: 24
2026-11-26 15:56:54.297 UTC [39] LOG:  archive recovery complete
post-bootstrap: restored cluster, passwords of monitor, backup, app and app_ro reset
```

Backup set used: `20261126-155146F`. Recovery target timeline `latest`; the source was on timeline 23 at T.

## Result

```console
$ q pg-rw.pg-restore.svc.cluster.local app "select id, t from pitr_marker where id like '%-1795708526' order by t"
A-1795708526 2026-11-26 15:55:27.087613+00
```

End to end: 32.49 s from `make restore` to a healthy restored cluster.

| PITR restore end to end (s) | Target T | Source timeline |
|---:|---|---:|
| 32.49 | 2026-11-26 21:55:28+06 | 23 |
