# L2 failure mode: split-brain

**Result: PASS**

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- **Run:** 2026-11-24T18:39:26Z (UTC), 358 s
- **Reproduce:** `make test-split-brain`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 20.80 | 15.37 | 187 | 0 | 1 | restart only | 23.91 | PASS |
| 2 | pg-0 | pg-1 | 22.68 | 16.60 | 173 | 0 | 1 | restart only | 42.56 | PASS |
| 3 | pg-1 | pg-2 | 19.82 | 15.26 | 186 | 0 | 1 | restart only | 22.70 | PASS |

RTO: min 19.82 s, median 20.80 s, max 22.68 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 20.80 s) | PASS |
| run 1: RPO 0, all 187 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: demotion issued within 13 s of the last renewal | PASS |
| run 1: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 1: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 22.68 s) | PASS |
| run 2: RPO 0, all 173 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: demotion issued within 13 s of the last renewal | PASS |
| run 2: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 2: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-2) | PASS |
| run 3: writes resumed on the new primary (RTO 19.82 s) | PASS |
| run 3: RPO 0, all 186 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: demotion issued within 13 s of the last renewal | PASS |
| run 3: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget) | PASS |
| run 3: old primary's last acknowledged write precedes the new leader's lock acquisition | PASS |

## Run 1

Fault at 18:39:39.983 UTC on primary `pg-2` (10.42.2.8, node `k3d-pg-ha-agent-0`, timeline 16). Sync standby before: `pg-0`.

Probe: 187 acknowledged, 29 failed attempts. Lock holders sampled: `pg-2>pg-0`. Leadership samples: 211 rounds of 3 members.

First acknowledged write on the new primary at 18:40:00.783 UTC. Last on the old primary at 18:39:45.411 UTC. Timeline 16 -> 17. Fault restored at 18:40:00.839, old member streaming from the new primary at 18:40:03.893 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.xoNfFqVnsO/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:39:45,758 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-24 18:39:45,758 INFO: Demoting self (offline)
2026-11-24 18:39:45.903 UTC [48] LOG:  database system is shut down
2026-11-24 18:39:47.468 UTC [1655] LOG:  database system was shut down at 2026-11-24 18:39:45 UTC
2026-11-24 18:39:47.481 UTC [1652] LOG:  database system is ready to accept read-only connections
2026-11-24 18:39:47,518 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-24 18:39:47.928 UTC [1664] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:39:48.486 UTC [1666] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:39:48.942 UTC [1668] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:39:49.475 UTC [1670] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:39:49.972 UTC [1672] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:39:50.472 UTC [1674] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-2: 18:39:38.520 UTC. Demotion issued +7.24 s (bound 13 s). Postgres stopped +7.38 s. Last acknowledged write on the old primary +6.89 s. New leader pg-0 acquired the lock +21.53 s (ttl 20 s).

## Run 2

Fault at 18:41:40.521 UTC on primary `pg-0` (10.42.1.13, node `k3d-pg-ha-agent-1`, timeline 17). Sync standby before: `pg-1`.

Probe: 173 acknowledged, 26 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 147 rounds of 3 members.

First acknowledged write on the new primary at 18:42:03.197 UTC. Last on the old primary at 18:41:46.594 UTC. Timeline 17 -> 18. Fault restored at 18:42:03.578, old member streaming from the new primary at 18:42:23.086 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.xoNfFqVnsO/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:41:46,858 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-24 18:41:46,858 INFO: Demoting self (offline)
2026-11-24 18:41:47.403 UTC [48] LOG:  database system is shut down
2026-11-24 18:41:50.839 UTC [1579] LOG:  database system was shut down at 2026-11-24 18:41:47 UTC
2026-11-24 18:41:50.865 UTC [1575] LOG:  database system is ready to accept read-only connections
2026-11-24 18:41:51,000 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-24 18:41:51.253 UTC [1585] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:41:51.259 UTC [1583] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:41:51.853 UTC [1586] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:41:53.197 UTC [1594] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:41:53.823 UTC [1597] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:41:54.601 UTC [1599] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-0: 18:41:39.439 UTC. Demotion issued +7.42 s (bound 13 s). Postgres stopped +7.96 s. Last acknowledged write on the old primary +7.16 s. New leader pg-1 acquired the lock +21.60 s (ttl 20 s).

## Run 3

Fault at 18:43:38.003 UTC on primary `pg-1` (10.42.3.9, node `k3d-pg-ha-agent-2`, timeline 18). Sync standby before: `pg-2`.

Probe: 186 acknowledged, 28 failed attempts. Lock holders sampled: `pg-1>pg-2`. Leadership samples: 208 rounds of 3 members.

First acknowledged write on the new primary at 18:43:57.820 UTC. Last on the old primary at 18:43:42.562 UTC. Timeline 18 -> 19. Fault restored at 18:43:57.926, old member streaming from the new primary at 18:44:00.701 UTC.

```console
$ grep -iE 'rewind|basebackup|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.xoNfFqVnsO/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-24 18:43:42,804 INFO: demoting self because DCS is not accessible and I was a leader
2026-11-24 18:43:42,804 INFO: Demoting self (offline)
2026-11-24 18:43:43.095 UTC [48] LOG:  database system is shut down
2026-11-24 18:43:45.119 UTC [1411] LOG:  database system was shut down at 2026-11-24 18:43:43 UTC
2026-11-24 18:43:45.151 UTC [1408] LOG:  database system is ready to accept read-only connections
2026-11-24 18:43:45.612 UTC [1420] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:43:46.163 UTC [1424] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:43:46,214 INFO: demoted self because DCS is not accessible and I was a leader
2026-11-24 18:43:46.646 UTC [1431] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:43:47.149 UTC [1435] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:43:47.689 UTC [1439] ERROR:  cannot execute INSERT in a read-only transaction
2026-11-24 18:43:48.276 UTC [1447] ERROR:  cannot execute INSERT in a read-only transaction
```

Last lock renewal by pg-1: 18:43:35.176 UTC. Demotion issued +7.63 s (bound 13 s). Postgres stopped +7.92 s. Last acknowledged write on the old primary +7.39 s. New leader pg-2 acquired the lock +21.53 s (ttl 20 s).
