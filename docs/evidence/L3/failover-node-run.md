# L2 failure mode: node

**Result: PASS**

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- **Run:** 2026-11-25T13:35:35Z (UTC), 123 s
- **Reproduce:** `make failover-node`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-2 | pg-1 | 23.09 | 23.09 | 173 | 0 | 1 | restart only | 41.04 | k3d-pg-ha-server-0 | 0 | 2.18 | PASS |

RTO: min 23.09 s, median 23.09 s, max 23.09 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 1: writes resumed on the new primary (RTO 23.09 s) | PASS |
| run 1: RPO 0, all 173 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 1: no new archive failures on the primary pg-1 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:35:47.435 UTC on primary `pg-2` (10.42.3.6, node `k3d-pg-ha-agent-2`, timeline 15). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 173 acknowledged, 43 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 211 rounds of 3 members.

First acknowledged write on the new primary at 13:36:10.530 UTC. Last on the old primary at 13:35:47.439 UTC. Timeline 15 -> 16. Fault restored at 13:36:10.316, old member streaming from the new primary at 13:36:28.478 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.R2blb4WYgi/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:36:26.523 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 13:36:26.920 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.18 s (bound 90 s). Last archived `000000100000000000000039`. Pending .ready: 0 (-).
