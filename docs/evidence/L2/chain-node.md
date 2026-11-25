# L2 failure mode: node

**Result: PASS**

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- **Run:** 2026-11-25T15:21:51Z (UTC), 123 s
- **Reproduce:** `make failover-node`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 24.15 | 24.05 | 169 | 0 | 1 | restart only | 43.12 | k3d-pg-ha-server-0 | 0 | 2.37 | PASS |

RTO: min 24.15 s, median 24.15 s, max 24.15 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 24.15 s) | PASS |
| run 1: RPO 0, all 169 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:22:04.007 UTC on primary `pg-1` (10.42.4.7, node `k3d-pg-ha-agent-0`, timeline 19). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 169 acknowledged, 46 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 15:22:28.155 UTC. Last on the old primary at 15:22:04.107 UTC. Timeline 19 -> 20. Fault restored at 15:22:28.794, old member streaming from the new primary at 15:22:47.129 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.YNCbrHNGd8/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 15:22:45.367 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 15:22:45.428 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.37 s (bound 90 s). Last archived `000000140000000000000049`. Pending .ready: 0 (-).
