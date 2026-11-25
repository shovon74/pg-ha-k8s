# L2 failure mode: pod

**Result: PASS**

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- **Run:** 2026-11-25T13:02:26Z (UTC), 250 s
- **Reproduce:** `make failover-pod`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 3.78 | 3.24 | 132 | 0 | 1 | restart only | 8.88 | k3d-pg-ha-server-0 | 0 | 2.26 | PASS |
| 2 | pg-0 | pg-2 | 5.13 | 4.55 | 131 | 0 | 1 | restart only | 10.33 | k3d-pg-ha-server-0 | 0 | 2.48 | PASS |
| 3 | pg-2 | pg-1 | 3.60 | 3.09 | 132 | 0 | 1 | restart only | 10.01 | k3d-pg-ha-server-0 | 0 | 2.41 | PASS |

RTO: min 3.60 s, median 3.78 s, max 5.13 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 3.78 s) | PASS |
| run 1: RPO 0, all 132 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 2: writes resumed on the new primary (RTO 5.13 s) | PASS |
| run 2: RPO 0, all 131 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 2: no new archive failures on the primary pg-2 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 3: writes resumed on the new primary (RTO 3.60 s) | PASS |
| run 3: RPO 0, all 132 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 3: no new archive failures on the primary pg-1 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:02:40.073 UTC on primary `pg-1` (10.42.4.3, node `k3d-pg-ha-agent-0`, timeline 1). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 132 acknowledged, 4 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 131 rounds of 3 members.

First acknowledged write on the new primary at 13:02:43.855 UTC. Last on the old primary at 13:02:40.612 UTC. Timeline 1 -> 2. Fault restored at 13:02:42.705, old member streaming from the new primary at 13:02:48.950 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.OYQLHPGKre/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-25 13:02:46.544 UTC [36] LOG:  database system was shut down at 2026-11-25 13:02:40 UTC
2026-11-25 13:02:46.773 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.26 s (bound 90 s). Last archived `000000020000000000000013`. Pending .ready: 0 (-).

## Run 2

Fault at 13:04:02.192 UTC on primary `pg-0` (10.42.1.3, node `k3d-pg-ha-agent-1`, timeline 2). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 131 acknowledged, 6 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 130 rounds of 3 members.

First acknowledged write on the new primary at 13:04:07.326 UTC. Last on the old primary at 13:04:02.780 UTC. Timeline 2 -> 3. Fault restored at 13:04:05.551, old member streaming from the new primary at 13:04:12.522 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.OYQLHPGKre/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-25 13:04:10.512 UTC [37] LOG:  database system was shut down at 2026-11-25 13:04:03 UTC
2026-11-25 13:04:10.868 UTC [34] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.48 s (bound 90 s). Last archived `000000030000000000000016`. Pending .ready: 0 (-).

## Run 3

Fault at 13:05:25.723 UTC on primary `pg-2` (10.42.3.3, node `k3d-pg-ha-agent-2`, timeline 3). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 132 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 128 rounds of 3 members.

First acknowledged write on the new primary at 13:05:29.319 UTC. Last on the old primary at 13:05:26.231 UTC. Timeline 3 -> 4. Fault restored at 13:05:27.807, old member streaming from the new primary at 13:05:35.733 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.OYQLHPGKre/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
  Database cluster state: shut down
2026-11-25 13:05:33.695 UTC [36] LOG:  database system was shut down at 2026-11-25 13:05:26 UTC
2026-11-25 13:05:34.079 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 15 before the fault, +0 since. After a WAL fill, a segment was archived in 2.41 s (bound 90 s). Last archived `000000040000000000000019`. Pending .ready: 0 (-).
