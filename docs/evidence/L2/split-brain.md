# L2 failure mode: split-brain

**Result: PASS**

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- **Run:** 2026-11-25T13:19:13Z (UTC), 372 s
- **Reproduce:** `make test-split-brain`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 20.47 | 14.49 | 189 | 0 | 1 | restart only | 24.61 | k3d-pg-ha-server-0 | 0 | 2.45 | PASS |
| 2 | pg-0 | pg-2 | 22.20 | 15.11 | 188 | 0 | 1 | restart only | 25.81 | k3d-pg-ha-server-0 | 0 | 2.45 | PASS |
| 3 | pg-2 | pg-1 | 22.18 | 15.69 | 186 | 0 | 1 | restart only | 27.38 | k3d-pg-ha-server-0 | 0 | 2.69 | PASS |

RTO: min 20.47 s, median 22.18 s, max 22.20 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 20.47 s) | PASS |
| run 1: RPO 0, all 189 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: demotion issued within 13 s of the last renewal | PASS |
| run 1: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 1: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 2: writes resumed on the new primary (RTO 22.20 s) | PASS |
| run 2: RPO 0, all 188 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: demotion issued within 13 s of the last renewal | PASS |
| run 2: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 2: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 2: no new archive failures on the primary pg-2 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 3: writes resumed on the new primary (RTO 22.18 s) | PASS |
| run 3: RPO 0, all 186 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: demotion issued within 13 s of the last renewal | PASS |
| run 3: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 3: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 3: no new archive failures on the primary pg-1 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:19:27.855 UTC on primary `pg-1` (10.42.4.6, node `k3d-pg-ha-agent-0`, timeline 10). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 189 acknowledged, 27 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 13:19:48.322 UTC. Last on the old primary at 13:19:33.829 UTC. Timeline 10 -> 11. Fault restored at 13:19:48.562, old member streaming from the new primary at 13:19:52.462 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.bHMXkJkOsk/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:19:34,011 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-25 13:19:34,011 INFO: Demoting self (offline)
2026-11-25 13:19:34.833 UTC [32] LOG:  database system is shut down
2026-11-25 13:19:35.765 UTC [1785] LOG:  database system was shut down at 2026-11-25 13:19:34 UTC
2026-11-25 13:19:35.991 UTC [1781] LOG:  database system is ready to accept read-only connections
2026-11-25 13:19:36.069 UTC [1798] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:19:36.405 UTC [1804] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:19:36,845 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-25 13:19:36.926 UTC [1809] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:19:37.429 UTC [1811] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:19:37.931 UTC [1813] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:19:38.449 UTC [1815] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-1: 13:19:26.130 UTC. Demotion issued +7.88 s (bound 13 s). Postgres stopped +8.70 s. Last acknowledged write on the old primary +7.70 s. New leader pg-0 acquired the lock +21.52 s (ttl 20 s).

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.45 s (bound 90 s). Last archived `0000000B0000000000000028`. Pending .ready: 0 (-).

## Run 2

Fault at 13:21:30.624 UTC on primary `pg-0` (10.42.1.10, node `k3d-pg-ha-agent-1`, timeline 11). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 188 acknowledged, 28 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 210 rounds of 3 members.

First acknowledged write on the new primary at 13:21:52.823 UTC. Last on the old primary at 13:21:37.711 UTC. Timeline 11 -> 12. Fault restored at 13:21:52.167, old member streaming from the new primary at 13:21:56.437 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.bHMXkJkOsk/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:21:37,836 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-25 13:21:37,837 INFO: Demoting self (offline)
2026-11-25 13:21:39.185 UTC [31] LOG:  database system is shut down
2026-11-25 13:21:40.055 UTC [1761] LOG:  database system was shut down at 2026-11-25 13:21:38 UTC
2026-11-25 13:21:40.248 UTC [1758] LOG:  database system is ready to accept read-only connections
2026-11-25 13:21:40.310 UTC [1775] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:21:40.797 UTC [1782] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:21:41,164 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-25 13:21:41.297 UTC [1788] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:21:41.795 UTC [1791] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:21:42.318 UTC [1794] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:21:42.809 UTC [1797] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-0: 13:21:30.029 UTC. Demotion issued +7.81 s (bound 13 s). Postgres stopped +9.16 s. Last acknowledged write on the old primary +7.68 s. New leader pg-2 acquired the lock +21.53 s (ttl 20 s).

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.45 s (bound 90 s). Last archived `0000000C000000000000002B`. Pending .ready: 0 (-).

## Run 3

Fault at 13:23:34.599 UTC on primary `pg-2` (10.42.3.6, node `k3d-pg-ha-agent-2`, timeline 12). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 186 acknowledged, 29 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 208 rounds of 3 members.

First acknowledged write on the new primary at 13:23:56.781 UTC. Last on the old primary at 13:23:41.088 UTC. Timeline 12 -> 13. Fault restored at 13:23:56.621, old member streaming from the new primary at 13:24:01.982 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.bHMXkJkOsk/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:23:41,466 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-25 13:23:41,466 INFO: Demoting self (offline)
2026-11-25 13:23:42.922 UTC [32] LOG:  database system is shut down
2026-11-25 13:23:43.989 UTC [1756] LOG:  database system was shut down at 2026-11-25 13:23:41 UTC
2026-11-25 13:23:44.229 UTC [1753] LOG:  database system is ready to accept read-only connections
2026-11-25 13:23:44.342 UTC [1771] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:23:44.780 UTC [1779] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:23:45,125 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-25 13:23:45.304 UTC [1787] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:23:45.741 UTC [1790] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:23:46.218 UTC [1794] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-25 13:23:46.802 UTC [1800] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-2: 13:23:34.116 UTC. Demotion issued +7.35 s (bound 13 s). Postgres stopped +8.81 s. Last acknowledged write on the old primary +6.97 s. New leader pg-1 acquired the lock +21.53 s (ttl 20 s).

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.69 s (bound 90 s). Last archived `0000000D000000000000002E`. Pending .ready: 0 (-).
