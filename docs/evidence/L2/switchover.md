# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- **Run:** 2026-11-24T18:46:25Z (UTC), 175 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-0 | pg-1 | 2.54 | 2.58 | 93 | 0 | 1 | pg_rewind | 8.78 | PASS |
| 2 | pg-1 | pg-2 | 1.83 | 1.85 | 95 | 0 | 1 | restart only | 8.79 | PASS |
| 3 | pg-2 | pg-0 | 2.60 | 2.63 | 93 | 0 | 1 | restart only | 9.31 | PASS |

RTO: min 1.83 s, median 2.54 s, max 2.60 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 1: writes resumed on the new primary (RTO 2.54 s) | PASS |
| run 1: RPO 0, all 93 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 2: lock moved from pg-1 to a new leader (pg-2) | PASS |
| run 2: writes resumed on the new primary (RTO 1.83 s) | PASS |
| run 2: RPO 0, all 95 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-1 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 3: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 3: writes resumed on the new primary (RTO 2.60 s) | PASS |
| run 3: RPO 0, all 93 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |

## Run 1

Fault at 18:46:39.618 UTC on primary `pg-0` (10.42.1.13, node `k3d-pg-ha-agent-1`, timeline 20). Sync standby before: `pg-1`.

Probe: 93 acknowledged, 4 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 91 rounds of 3 members.

First acknowledged write on the new primary at 18:46:42.163 UTC. Last on the old primary at 18:46:39.584 UTC. Timeline 20 -> 21. Fault restored at 18:46:42.856, old member streaming from the new primary at 18:46:48.396 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.gbAUxEMgN5/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:46:39,710 INFO: switchover: demoting myself
2026-11-24 18:46:39,710 INFO: Demoting self (graceful)
2026-11-24 18:46:39.938 UTC [1575] LOG:  database system is shut down
2026-11-24 18:46:40,925 INFO: switchover: demote in progress
2026-11-24 18:46:40,929 INFO: switchover: demote in progress
2026-11-24 18:46:42,003 INFO: switchover: demote in progress
2026-11-24 18:46:42,078 INFO: switchover: demote in progress
  Database cluster state: shut down
2026-11-24 18:46:43,157 INFO: running pg_rewind from pg-1
2026-11-24 18:46:43,287 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-1.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:46:43,432 INFO: pg_rewind exit code=0
2026-11-24 18:46:43,432 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CE4AFD8 on timeline 20
```

```console
$ cat /tmp/tmp.gbAUxEMgN5/run1/switchover.txt
Successfully switched over to "pg-1"
```

## Run 2

Fault at 18:47:36.544 UTC on primary `pg-1` (10.42.3.9, node `k3d-pg-ha-agent-2`, timeline 21). Sync standby before: `pg-2`.

Probe: 95 acknowledged, 2 failed attempts. Lock holders sampled: `pg-1>pg-2`. Leadership samples: 90 rounds of 3 members.

First acknowledged write on the new primary at 18:47:38.378 UTC. Last on the old primary at 18:47:36.526 UTC. Timeline 21 -> 22. Fault restored at 18:47:39.837, old member streaming from the new primary at 18:47:45.332 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.gbAUxEMgN5/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:47:36,627 INFO: switchover: demoting myself
2026-11-24 18:47:36,627 INFO: Demoting self (graceful)
2026-11-24 18:47:36.830 UTC [1408] LOG:  database system is shut down
2026-11-24 18:47:37,813 INFO: switchover: demote in progress
2026-11-24 18:47:37,891 INFO: switchover: demote in progress
2026-11-24 18:47:38,919 INFO: switchover: demote in progress
2026-11-24 18:47:39,001 INFO: switchover: demote in progress
2026-11-24 18:47:40.943 UTC [2350] LOG:  database system was shut down at 2026-11-24 18:47:36 UTC
2026-11-24 18:47:40.987 UTC [2347] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.gbAUxEMgN5/run2/switchover.txt
Successfully switched over to "pg-2"
```

## Run 3

Fault at 18:48:33.968 UTC on primary `pg-2` (10.42.2.8, node `k3d-pg-ha-agent-0`, timeline 22). Sync standby before: `pg-0`.

Probe: 93 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-0`. Leadership samples: 91 rounds of 3 members.

First acknowledged write on the new primary at 18:48:36.568 UTC. Last on the old primary at 18:48:33.938 UTC. Timeline 22 -> 23. Fault restored at 18:48:37.365, old member streaming from the new primary at 18:48:43.276 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.gbAUxEMgN5/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:48:34,078 INFO: switchover: demoting myself
2026-11-24 18:48:34,078 INFO: Demoting self (graceful)
2026-11-24 18:48:34.268 UTC [3139] LOG:  database system is shut down
2026-11-24 18:48:35,264 INFO: switchover: demote in progress
2026-11-24 18:48:36,407 INFO: switchover: demote in progress
2026-11-24 18:48:36,466 INFO: switchover: demote in progress
2026-11-24 18:48:38.556 UTC [3680] LOG:  database system was shut down at 2026-11-24 18:48:34 UTC
2026-11-24 18:48:38.590 UTC [3677] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.gbAUxEMgN5/run3/switchover.txt
Successfully switched over to "pg-0"
```
