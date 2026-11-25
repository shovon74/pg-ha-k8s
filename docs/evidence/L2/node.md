# L2 failure mode: node

**Result: PASS**

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- **Run:** 2026-11-25T13:06:37Z (UTC), 386 s
- **Reproduce:** `make failover-node`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 23.22 | 23.43 | 170 | 0 | 1 | restart only | 39.42 | k3d-pg-ha-server-0 | 0 | 5.39 | PASS |
| 2 | pg-0 | pg-2 | 26.19 | 25.83 | 166 | 0 | 1 | restart only | 47.96 | k3d-pg-ha-server-0 | 0 | 2.32 | PASS |
| 3 | pg-2 | pg-1 | 23.93 | 23.81 | 166 | 0 | 1 | restart only | 45.49 | k3d-pg-ha-server-0 | 0 | 2.60 | PASS |

RTO: min 23.22 s, median 23.93 s, max 26.19 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 23.22 s) | PASS |
| run 1: RPO 0, all 170 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 2: writes resumed on the new primary (RTO 26.19 s) | PASS |
| run 2: RPO 0, all 166 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 2: no new archive failures on the primary pg-2 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 3: writes resumed on the new primary (RTO 23.93 s) | PASS |
| run 3: RPO 0, all 166 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 3: no new archive failures on the primary pg-1 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:06:51.296 UTC on primary `pg-1` (10.42.4.4, node `k3d-pg-ha-agent-0`, timeline 4). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 170 acknowledged, 45 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 209 rounds of 3 members.

First acknowledged write on the new primary at 13:07:14.513 UTC. Last on the old primary at 13:06:51.087 UTC. Timeline 4 -> 5. Fault restored at 13:07:14.806, old member streaming from the new primary at 13:07:30.714 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.tIRrayVd0Z/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:07:29.506 UTC [36] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 13:07:29.680 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 5.39 s (bound 90 s). Last archived `00000005000000000000001B`. Pending .ready: 0 (-).

## Run 2

Fault at 13:09:10.568 UTC on primary `pg-0` (10.42.1.8, node `k3d-pg-ha-agent-1`, timeline 5). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 166 acknowledged, 41 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 183 rounds of 3 members.

First acknowledged write on the new primary at 13:09:36.757 UTC. Last on the old primary at 13:09:10.931 UTC. Timeline 5 -> 6. Fault restored at 13:09:36.155, old member streaming from the new primary at 13:09:58.524 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.tIRrayVd0Z/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:09:56.040 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 13:09:56.405 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.32 s (bound 90 s). Last archived `00000006000000000000001D`. Pending .ready: 0 (-).

## Run 3

Fault at 13:11:13.174 UTC on primary `pg-2` (10.42.3.4, node `k3d-pg-ha-agent-2`, timeline 6). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 166 acknowledged, 47 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 205 rounds of 3 members.

First acknowledged write on the new primary at 13:11:37.108 UTC. Last on the old primary at 13:11:13.293 UTC. Timeline 6 -> 7. Fault restored at 13:11:37.188, old member streaming from the new primary at 13:11:58.666 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.tIRrayVd0Z/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:11:56.269 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-25 13:11:56.608 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.60 s (bound 90 s). Last archived `00000007000000000000001F`. Pending .ready: 0 (-).
