# L2 failure mode: pod

**Result: PASS**

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- **Run:** 2026-11-26T15:01:35Z (UTC), 254 s
- **Reproduce:** `make failover-pod`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 4.34 | 3.86 | 132 | 0 | 1 | restart only | 10.47 | k3d-pg-ha-server-0 | 0 | 2.36 | PASS |
| 2 | pg-2 | pg-1 | 3.33 | 3.35 | 131 | 0 | 1 | restart only | 10.61 | k3d-pg-ha-server-0 | 0 | 1.88 | PASS |
| 3 | pg-1 | pg-0 | 3.74 | 3.73 | 132 | 0 | 1 | restart only | 11.78 | k3d-pg-ha-server-0 | 0 | 2.80 | PASS |

RTO: min 3.33 s, median 3.74 s, max 4.34 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 4.34 s) | PASS |
| run 1: RPO 0, all 132 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 3.33 s) | PASS |
| run 2: RPO 0, all 131 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 2: no new archive failures on the primary pg-1 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 3: writes resumed on the new primary (RTO 3.74 s) | PASS |
| run 3: RPO 0, all 132 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 3: no new archive failures on the primary pg-0 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:01:51.312 UTC on primary `pg-0` (10.42.2.4, node `k3d-pg-ha-agent-0`, timeline 1). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 132 acknowledged, 5 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 131 rounds of 3 members.

First acknowledged write on the new primary at 15:01:55.647 UTC. Last on the old primary at 15:01:51.790 UTC. Timeline 1 -> 2. Fault restored at 15:01:54.444, old member streaming from the new primary at 15:02:01.782 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.SWz461qxcG/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
  File "/usr/lib/python3/dist-packages/patroni/postgresql/rewind.py", line 83, in check_leader_is_not_in_recovery
2026-11-26 15:01:59.401 UTC [35] LOG:  database system was shut down at 2026-11-26 15:01:52 UTC
2026-11-26 15:01:59.595 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.36 s (bound 90 s). Last archived `000000020000000000000012`. Pending .ready: 0 (-).

## Run 2

Fault at 15:03:14.402 UTC on primary `pg-2` (10.42.1.3, node `k3d-pg-ha-agent-2`, timeline 2). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 131 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 129 rounds of 3 members.

First acknowledged write on the new primary at 15:03:17.729 UTC. Last on the old primary at 15:03:14.377 UTC. Timeline 2 -> 3. Fault restored at 15:03:16.600, old member streaming from the new primary at 15:03:25.010 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.SWz461qxcG/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
  File "/usr/lib/python3/dist-packages/patroni/postgresql/rewind.py", line 83, in check_leader_is_not_in_recovery
2026-11-26 15:03:22.340 UTC [36] LOG:  database system was shut down at 2026-11-26 15:03:15 UTC
2026-11-26 15:03:22.713 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 1.88 s (bound 90 s). Last archived `000000030000000000000015`. Pending .ready: 0 (-).

## Run 3

Fault at 15:04:38.673 UTC on primary `pg-1` (10.42.4.5, node `k3d-pg-ha-agent-1`, timeline 3). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 132 acknowledged, 3 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 126 rounds of 3 members.

First acknowledged write on the new primary at 15:04:42.412 UTC. Last on the old primary at 15:04:38.681 UTC. Timeline 3 -> 4. Fault restored at 15:04:40.763, old member streaming from the new primary at 15:04:50.452 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.SWz461qxcG/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-26 15:04:47.629 UTC [36] LOG:  database system was shut down at 2026-11-26 15:04:39 UTC
2026-11-26 15:04:48.004 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 18 before the fault, +0 since. After a WAL fill, a segment was archived in 2.80 s (bound 90 s). Last archived `000000040000000000000018`. Pending .ready: 0 (-).
