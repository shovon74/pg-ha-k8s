# L2 failure mode: diverge

**Result: PASS**

- **Fault:** Replication traffic from the primary pod to both replicas is dropped by iptables on its node for 5 s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).
- **Run:** 2026-11-26T16:42:52Z (UTC), 124 s
- **Reproduce:** `make failover-diverge`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 29.48 | 29.70 | 157 | 0 | 1 | re-clone | 55.73 | k3d-pg-ha-server-0 | 0 | 2.17 | PASS |

RTO: min 29.48 s, median 29.48 s, max 29.48 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 29.48 s) | PASS |
| run 1: RPO 0, all 157 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Replication from `pg-1` to `10.42.2.32` `10.42.1.18` blocked at 16:43:05.649 UTC, node stopped +5.27 s later.

Fault at 16:43:05.649 UTC on primary `pg-1` (10.42.4.25, node `k3d-pg-ha-agent-1`, timeline 33). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 157 acknowledged, 57 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 16:43:35.125 UTC. Last on the old primary at 16:43:05.422 UTC. Timeline 33 -> 34. Fault restored at 16:43:35.574, old member streaming from the new primary at 16:44:01.381 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.QhyHcTv4zw/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 16:43:51.865 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-26 16:43:52.237 UTC [32] LOG:  database system is ready to accept read-only connections
2026-11-26 16:43:52,872 INFO: reinitializing due to diverged timelines
2026-11-26 16:43:52.895 UTC [32] LOG:  received immediate shutdown request
2026-11-26 16:43:52.953 UTC [32] LOG:  database system is shut down
2026-11-26 16:43:53,740 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:53,932 INFO: Removing data directory: /data/pgdata
2026-11-26 16:43:56,856 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:56,860 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:58,392 INFO: replica has been created using basebackup
2026-11-26 16:43:59.482 UTC [80] LOG:  database system is ready to accept read-only connections
2026-11-26 16:43:59,791 INFO: reinitializing due to diverged timelines in progress
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.17 s (bound 90 s). Last archived `0000002200000000000000E0`. Pending .ready: 0 (-).
