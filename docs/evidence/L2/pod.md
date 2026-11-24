# L2 failure mode: pod

**Result: PASS**

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- **Run:** 2026-11-24T18:23:32Z (UTC), 235 s
- **Reproduce:** `make failover-pod`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 3.15 | 2.64 | 134 | 0 | 1 | restart only | 7.92 | PASS |
| 2 | pg-0 | pg-1 | 3.08 | 3.02 | 132 | 0 | 1 | restart only | 8.16 | PASS |
| 3 | pg-1 | pg-2 | 3.88 | 2.89 | 133 | 0 | 1 | pg_rewind | 9.68 | PASS |

RTO: min 3.08 s, median 3.15 s, max 3.88 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 3.15 s) | PASS |
| run 1: RPO 0, all 134 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 3.08 s) | PASS |
| run 2: RPO 0, all 132 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-2) | PASS |
| run 3: writes resumed on the new primary (RTO 3.88 s) | PASS |
| run 3: RPO 0, all 133 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |

## Run 1

Fault at 18:23:45.420 UTC on primary `pg-2` (10.42.2.5, node `k3d-pg-ha-agent-0`, timeline 7). Sync standby before: `pg-0`.

Probe: 134 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-0`. Leadership samples: 132 rounds of 3 members.

First acknowledged write on the new primary at 18:23:48.571 UTC. Last on the old primary at 18:23:45.935 UTC. Timeline 7 -> 8. Fault restored at 18:23:47.843, old member streaming from the new primary at 18:23:53.339 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.2X5gtGa5fD/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:23:51.702 UTC [38] LOG:  database system was shut down at 2026-11-24 18:23:46 UTC
2026-11-24 18:23:51.724 UTC [35] LOG:  database system is ready to accept read-only connections
```

## Run 2

Fault at 18:25:03.043 UTC on primary `pg-0` (10.42.1.10, node `k3d-pg-ha-agent-1`, timeline 8). Sync standby before: `pg-1`.

Probe: 132 acknowledged, 4 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 130 rounds of 3 members.

First acknowledged write on the new primary at 18:25:06.120 UTC. Last on the old primary at 18:25:03.096 UTC. Timeline 8 -> 9. Fault restored at 18:25:04.960, old member streaming from the new primary at 18:25:11.198 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.2X5gtGa5fD/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:25:09.736 UTC [38] LOG:  database system was shut down at 2026-11-24 18:25:03 UTC
2026-11-24 18:25:09.760 UTC [35] LOG:  database system is ready to accept read-only connections
```

## Run 3

Fault at 18:26:20.388 UTC on primary `pg-1` (10.42.3.6, node `k3d-pg-ha-agent-2`, timeline 9). Sync standby before: `pg-2`.

Probe: 133 acknowledged, 4 failed attempts. Lock holders sampled: `pg-1>pg-2`. Leadership samples: 129 rounds of 3 members.

First acknowledged write on the new primary at 18:26:24.265 UTC. Last on the old primary at 18:26:21.372 UTC. Timeline 9 -> 10. Fault restored at 18:26:23.056, old member streaming from the new primary at 18:26:30.068 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.2X5gtGa5fD/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:26:27,252 INFO: running pg_rewind from pg-2
2026-11-24 18:26:27,382 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-2.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:26:27,509 INFO: pg_rewind exit code=0
2026-11-24 18:26:27,509 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CCC6CC0 on timeline 9
pg_rewind: no rewind required
  Database cluster state: shut down
2026-11-24 18:26:28.496 UTC [46] LOG:  database system was shut down at 2026-11-24 18:26:21 UTC
2026-11-24 18:26:28.524 UTC [43] LOG:  database system is ready to accept read-only connections
```
