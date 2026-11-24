# L2 failure mode: node

**Result: PASS**

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- **Run:** 2026-11-24T18:27:28Z (UTC), 362 s
- **Reproduce:** `make failover-node`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 21.91 | 21.87 | 174 | 0 | 1 | pg_rewind | 46.11 | PASS |
| 2 | pg-0 | pg-1 | 22.62 | 22.66 | 146 | 0 | 1 | pg_rewind | 91.02 | PASS |
| 3 | pg-1 | pg-2 | 23.35 | 23.16 | 169 | 0 | 1 | pg_rewind | 57.79 | PASS |

RTO: min 21.91 s, median 22.62 s, max 23.35 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 21.91 s) | PASS |
| run 1: RPO 0, all 174 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 22.62 s) | PASS |
| run 2: RPO 0, all 146 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-2) | PASS |
| run 3: writes resumed on the new primary (RTO 23.35 s) | PASS |
| run 3: RPO 0, all 169 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |

## Run 1

Fault at 18:27:40.757 UTC on primary `pg-2` (10.42.2.6, node `k3d-pg-ha-agent-0`, timeline 10). Sync standby before: `pg-0`.

Probe: 174 acknowledged, 42 failed attempts. Lock holders sampled: `pg-2>pg-0`. Leadership samples: 211 rounds of 3 members.

First acknowledged write on the new primary at 18:28:02.666 UTC. Last on the old primary at 18:27:40.794 UTC. Timeline 10 -> 11. Fault restored at 18:28:03.213, old member streaming from the new primary at 18:28:26.862 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.PlQ4hG8yKI/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:28:17,743 INFO: running pg_rewind from pg-0
2026-11-24 18:28:17,826 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-0.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:28:20,442 INFO: running pg_rewind from pg-0 in progress
2026-11-24 18:28:23,425 INFO: running pg_rewind from pg-0 in progress
2026-11-24 18:28:24,009 INFO: pg_rewind exit code=0
2026-11-24 18:28:24,009 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CCD9CD8 on timeline 10
pg_rewind: rewinding from last common checkpoint at 0/CCCA5A8 on timeline 10
pg_rewind: Done!
2026-11-24 18:28:24.982 UTC [48] LOG:  database system is ready to accept read-only connections
```

## Run 2

Fault at 18:29:38.203 UTC on primary `pg-0` (10.42.1.11, node `k3d-pg-ha-agent-1`, timeline 11). Sync standby before: `pg-1`.

Probe: 146 acknowledged, 44 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 119 rounds of 3 members.

First acknowledged write on the new primary at 18:30:00.825 UTC. Last on the old primary at 18:29:38.166 UTC. Timeline 11 -> 12. Fault restored at 18:30:01.421, old member streaming from the new primary at 18:31:09.220 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.PlQ4hG8yKI/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:30:36,689 INFO: running pg_rewind from pg-1
2026-11-24 18:30:37,110 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-1.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:30:37,163 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:40,117 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:43,106 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:46,127 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:46,153 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:49,119 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:52,123 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:52,248 INFO: running pg_rewind from pg-1 in progress
2026-11-24 18:30:55,183 INFO: running pg_rewind from pg-1 in progress
```

## Run 3

Fault at 18:31:43.960 UTC on primary `pg-1` (10.42.3.7, node `k3d-pg-ha-agent-2`, timeline 12). Sync standby before: `pg-2`.

Probe: 169 acknowledged, 44 failed attempts. Lock holders sampled: `pg-1>pg-2`. Leadership samples: 207 rounds of 3 members.

First acknowledged write on the new primary at 18:32:07.309 UTC. Last on the old primary at 18:31:44.152 UTC. Timeline 12 -> 13. Fault restored at 18:32:08.292, old member streaming from the new primary at 18:32:41.751 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.PlQ4hG8yKI/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-24 18:32:26,846 INFO: running pg_rewind from pg-2
2026-11-24 18:32:26,972 INFO: running pg_rewind from dbname=postgres user=rewind host=pg-2.pg-headless.pg-ha.svc.cluster.local port=5432 target_session_attrs=read-write
2026-11-24 18:32:28,004 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:32:31,000 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:32:31,012 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:32:34,005 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:32:36,979 INFO: running pg_rewind from pg-2 in progress
2026-11-24 18:32:37,795 INFO: pg_rewind exit code=0
2026-11-24 18:32:37,796 INFO:  stderr=pg_rewind: servers diverged at WAL location 0/CD5BEB0 on timeline 12
pg_rewind: rewinding from last common checkpoint at 0/CD1E918 on timeline 12
pg_rewind: Done!
```
