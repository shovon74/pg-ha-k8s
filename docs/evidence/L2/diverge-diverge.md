# L2 failure mode: diverge

**Result: PASS**

- **Fault:** Replication traffic from the primary pod to both replicas is dropped by iptables on its node for 5 s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).
- **Run:** 2026-11-25T15:28:15Z (UTC), 123 s
- **Reproduce:** `make failover-diverge`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-2 | pg-1 | 26.85 | 27.00 | 163 | 0 | 1 | re-clone | 54.10 | k3d-pg-ha-server-0 | 0 | 2.29 | PASS |

RTO: min 26.85 s, median 26.85 s, max 26.85 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 1: writes resumed on the new primary (RTO 26.85 s) | PASS |
| run 1: RPO 0, all 163 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 1: no new archive failures on the primary pg-1 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Replication from `pg-2` to `10.42.1.14` `10.42.4.9` blocked at 15:28:28.352 UTC, node stopped +5.29 s later.

Fault at 15:28:28.352 UTC on primary `pg-2` (10.42.3.8, node `k3d-pg-ha-agent-2`, timeline 24). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 163 acknowledged, 52 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 15:28:55.197 UTC. Last on the old primary at 15:28:28.195 UTC. Timeline 24 -> 25. Fault restored at 15:28:56.370, old member streaming from the new primary at 15:29:22.449 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.tFqYNA8Mx5/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 15:29:11.607 UTC [34] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 15:29:11.654 UTC [31] LOG:  database system is ready to accept read-only connections
2026-11-25 15:29:12,524 INFO: reinitializing due to diverged timelines
2026-11-25 15:29:12.525 UTC [31] LOG:  received immediate shutdown request
2026-11-25 15:29:12.565 UTC [31] LOG:  database system is shut down
2026-11-25 15:29:12,960 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:13,548 INFO: Removing data directory: /data/pgdata
2026-11-25 15:29:16,121 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:16,122 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:18,886 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:19,454 INFO: replica has been created using basebackup
2026-11-25 15:29:20.707 UTC [78] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.29 s (bound 90 s). Last archived `000000190000000000000054`. Pending .ready: 0 (-).
