# L2 failure mode: split-brain

**Result: PASS**

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- **Run:** 2026-11-26T15:18:21Z (UTC), 375 s
- **Reproduce:** `make test-split-brain`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 20.62 | 15.15 | 188 | 0 | 1 | restart only | 24.59 | k3d-pg-ha-server-0 | 0 | 2.67 | PASS |
| 2 | pg-2 | pg-1 | 20.61 | 15.31 | 188 | 0 | 1 | restart only | 24.31 | k3d-pg-ha-server-0 | 0 | 2.35 | PASS |
| 3 | pg-1 | pg-0 | 19.56 | 14.64 | 188 | 0 | 1 | restart only | 23.53 | k3d-pg-ha-server-0 | 0 | 2.68 | PASS |

RTO: min 19.56 s, median 20.61 s, max 20.62 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 20.62 s) | PASS |
| run 1: RPO 0, all 188 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: demotion issued within 13 s of the last renewal | PASS |
| run 1: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 1: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 20.61 s) | PASS |
| run 2: RPO 0, all 188 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: demotion issued within 13 s of the last renewal | PASS |
| run 2: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 2: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 2: no new archive failures on the primary pg-1 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 3: writes resumed on the new primary (RTO 19.56 s) | PASS |
| run 3: RPO 0, all 188 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: demotion issued within 13 s of the last renewal | PASS |
| run 3: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 3: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 3: no new archive failures on the primary pg-0 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:18:36.163 UTC on primary `pg-0` (10.42.2.15, node `k3d-pg-ha-agent-0`, timeline 10). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 188 acknowledged, 28 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 212 rounds of 3 members.

First acknowledged write on the new primary at 15:18:56.785 UTC. Last on the old primary at 15:18:41.639 UTC. Timeline 10 -> 11. Fault restored at 15:18:56.739, old member streaming from the new primary at 15:19:00.751 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.Uwrtm0nzha/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:18:41,987 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-26 15:18:41,987 INFO: Demoting self (offline)
2026-11-26 15:18:42.752 UTC [33] LOG:  database system is shut down
2026-11-26 15:18:43.955 UTC [1533] LOG:  database system was shut down at 2026-11-26 15:18:42 UTC
2026-11-26 15:18:44.085 UTC [1530] LOG:  database system is ready to accept read-only connections
2026-11-26 15:18:44.260 UTC [1551] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:18:44.678 UTC [1553] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:18:45,059 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-26 15:18:45.177 UTC [1558] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:18:45.692 UTC [1560] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:18:46.245 UTC [1562] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:18:46.752 UTC [1566] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-0: 15:18:34.355 UTC. Demotion issued +7.63 s (bound 13 s). Postgres stopped +8.40 s. Last acknowledged write on the old primary +7.28 s. New leader pg-2 acquired the lock +21.53 s (ttl 20 s).

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.67 s (bound 90 s). Last archived `0000000B0000000000000027`. Pending .ready: 0 (-).

## Run 2

Fault at 15:20:40.181 UTC on primary `pg-2` (10.42.1.8, node `k3d-pg-ha-agent-2`, timeline 11). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 188 acknowledged, 28 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 15:21:00.793 UTC. Last on the old primary at 15:20:45.479 UTC. Timeline 11 -> 12. Fault restored at 15:21:00.752, old member streaming from the new primary at 15:21:04.489 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.Uwrtm0nzha/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:20:45,672 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-26 15:20:45,672 INFO: Demoting self (offline)
2026-11-26 15:20:46.458 UTC [32] LOG:  database system is shut down
2026-11-26 15:20:47.445 UTC [1523] LOG:  database system was shut down at 2026-11-26 15:20:45 UTC
2026-11-26 15:20:47.569 UTC [1520] LOG:  database system is ready to accept read-only connections
2026-11-26 15:20:48.027 UTC [1547] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:20:48,508 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-26 15:20:48.537 UTC [1552] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:20:49.034 UTC [1555] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:20:49.537 UTC [1558] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:20:50.051 UTC [1561] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:20:50.570 UTC [1564] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-2: 15:20:38.294 UTC. Demotion issued +7.38 s (bound 13 s). Postgres stopped +8.16 s. Last acknowledged write on the old primary +7.19 s. New leader pg-1 acquired the lock +21.52 s (ttl 20 s).

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.35 s (bound 90 s). Last archived `0000000C000000000000002A`. Pending .ready: 0 (-).

## Run 3

Fault at 15:22:44.987 UTC on primary `pg-1` (10.42.4.9, node `k3d-pg-ha-agent-1`, timeline 12). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 188 acknowledged, 27 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 209 rounds of 3 members.

First acknowledged write on the new primary at 15:23:04.547 UTC. Last on the old primary at 15:22:49.908 UTC. Timeline 12 -> 13. Fault restored at 15:23:04.945, old member streaming from the new primary at 15:23:08.515 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.Uwrtm0nzha/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:22:50,050 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-26 15:22:50,050 INFO: Demoting self (offline)
2026-11-26 15:22:51.401 UTC [33] LOG:  database system is shut down
2026-11-26 15:22:52.660 UTC [1527] LOG:  database system was shut down at 2026-11-26 15:22:50 UTC
2026-11-26 15:22:52.876 UTC [1524] LOG:  database system is ready to accept read-only connections
2026-11-26 15:22:53.039 UTC [1544] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:22:53.449 UTC [1550] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:22:53,794 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-26 15:22:54.010 UTC [1557] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:22:54.464 UTC [1561] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:22:54.989 UTC [1567] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-26 15:22:55.487 UTC [1571] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-1: 15:22:42.237 UTC. Demotion issued +7.81 s (bound 13 s). Postgres stopped +9.16 s. Last acknowledged write on the old primary +7.67 s. New leader pg-0 acquired the lock +21.52 s (ttl 20 s).

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.68 s (bound 90 s). Last archived `0000000D000000000000002D`. Pending .ready: 0 (-).
