# L2 failure mode: pod

**Result: PASS**

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- **Run:** 2026-11-25T17:23:07Z (UTC), 87 s
- **Reproduce:** `make failover-pod`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-2 | pg-0 | 2.72 | 2.70 | 134 | 0 | 1 | restart only | 8.99 | k3d-pg-ha-server-0 | 0 | 2.60 | PASS |

RTO: min 2.72 s, median 2.72 s, max 2.72 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 2.72 s) | PASS |
| run 1: RPO 0, all 134 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 17:23:22.739 UTC on primary `pg-2` (10.42.3.28, node `k3d-pg-ha-agent-2`, timeline 39). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 134 acknowledged, 3 failed attempts. Lock holders sampled: `pg-2>2026-11-25T17:23:20.968903+00:00>pg-0`. Leadership samples: 132 rounds of 3 members.

First acknowledged write on the new primary at 17:23:25.457 UTC. Last on the old primary at 17:23:22.760 UTC. Timeline 39 -> 40. Fault restored at 17:23:24.799, old member streaming from the new primary at 17:23:31.734 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.K1soIrvknP/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
  File "/usr/lib/python3/dist-packages/patroni/postgresql/rewind.py", line 83, in check_leader_is_not_in_recovery
2026-11-25 17:23:29.954 UTC [35] LOG:  database system was shut down at 2026-11-25 17:23:23 UTC
2026-11-25 17:23:30.339 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.60 s (bound 90 s). Last archived `0000002800000000000000B6`. Pending .ready: 0 (-).
