# L2 failure mode: storage

**Result: PASS**

- **Fault:** The primary's data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container's mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.
- **Run:** 2026-11-24T18:33:31Z (UTC), 355 s
- **Reproduce:** `make failover-storage`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 2.44 | 2.66 | 213 | 0 | 1 | pg_rewind | 20.95 | PASS |
| 2 | pg-0 | pg-1 | 1.79 | 2.12 | 212 | 0 | 1 | pg_rewind | 22.17 | PASS |
| 3 | pg-1 | pg-2 | 3.94 | 4.03 | 207 | 0 | 1 | pg_rewind | 24.45 | PASS |

RTO: min 1.79 s, median 2.44 s, max 3.94 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 2.44 s) | PASS |
| run 1: RPO 0, all 213 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 1.79 s) | PASS |
| run 2: RPO 0, all 212 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-2) | PASS |
| run 3: writes resumed on the new primary (RTO 3.94 s) | PASS |
| run 3: RPO 0, all 207 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |

## Run 1

Fault at 18:33:45.112 UTC on primary `pg-2` (10.42.2.7, node `k3d-pg-ha-agent-0`, timeline 13). Sync standby before: `pg-0`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.I1Gb8aC3Qx/run1/old-before-restore.log | head -8
2026-11-24 18:33:46,042 INFO: Leader key released
2026-11-24 18:33:46,143 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 213 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-0`. Leadership samples: 211 rounds of 3 members.

First acknowledged write on the new primary at 18:33:47.555 UTC. Last on the old primary at 18:33:44.893 UTC. Timeline 13 -> 14. Fault restored at 18:33:49.838, old member streaming from the new primary at 18:34:06.059 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.I1Gb8aC3Qx/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:33:55,600 INFO: running pg_rewind from pg-0
2026-11-24 18:33:55,692 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-0.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:33:58,341 INFO: running pg_rewind from pg-0 in progress
2026-11-24 18:34:01,356 INFO: running pg_rewind from pg-0 in progress
2026-11-24 18:34:03,827 INFO: pg_rewind exit code=0
2026-11-24 18:34:03,827 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CD72560 on timeline 13
pg_rewind: rewinding from last common checkpoint at 0/CD5E078 on timeline 13
pg_rewind: Done!
2026-11-24 18:34:04.887 UTC [48] LOG:  database system is ready to accept read-only connections
```

## Run 2

Fault at 18:35:42.956 UTC on primary `pg-0` (10.42.1.12, node `k3d-pg-ha-agent-1`, timeline 14). Sync standby before: `pg-1`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.I1Gb8aC3Qx/run2/old-before-restore.log | head -8
2026-11-24 18:35:43,466 INFO: Leader key released
2026-11-24 18:35:43,533 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 212 acknowledged, 3 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 18:35:44.742 UTC. Last on the old primary at 18:35:42.622 UTC. Timeline 14 -> 15. Fault restored at 18:35:47.680, old member streaming from the new primary at 18:36:05.127 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.I1Gb8aC3Qx/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:35:53,378 INFO: running pg_rewind from pg-1
2026-11-24 18:35:53,480 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-1.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:35:55,711 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:35:58,675 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:36:01,634 INFO: pg_rewind exit code=0
2026-11-24 18:36:01,634 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CD8C2B8 on timeline 14
pg_rewind: rewinding from last common checkpoint at 0/CD726F8 on timeline 14
pg_rewind: Done!
2026-11-24 18:36:02.955 UTC [48] LOG:  database system is ready to accept read-only connections
```

## Run 3

Fault at 18:37:41.251 UTC on primary `pg-1` (10.42.3.8, node `k3d-pg-ha-agent-2`, timeline 15). Sync standby before: `pg-2`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.I1Gb8aC3Qx/run3/old-before-restore.log | head -8
2026-11-24 18:37:43,768 INFO: Leader key released
2026-11-24 18:37:44,393 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 207 acknowledged, 7 failed attempts. Lock holders sampled: `pg-1>pg-2`. Leadership samples: 207 rounds of 3 members.

First acknowledged write on the new primary at 18:37:45.194 UTC. Last on the old primary at 18:37:41.166 UTC. Timeline 15 -> 16. Fault restored at 18:37:47.720, old member streaming from the new primary at 18:38:05.704 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.I1Gb8aC3Qx/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:37:54,199 INFO: running pg_rewind from pg-2
2026-11-24 18:37:54,316 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-2.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:37:56,615 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:37:59,545 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:38:02,038 INFO: pg_rewind exit code=0
2026-11-24 18:38:02,038 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CDA0CB8 on timeline 15
pg_rewind: rewinding from last common checkpoint at 0/CD8C450 on timeline 15
pg_rewind: Done!
2026-11-24 18:38:03.504 UTC [48] LOG:  database system is ready to accept read-only connections
```
