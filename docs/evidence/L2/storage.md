# L2 failure mode: storage

**Result: PASS**

- **Fault:** The primary's data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container's mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.
- **Run:** 2026-11-26T15:12:04Z (UTC), 376 s
- **Reproduce:** `make failover-storage`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 3.01 | 3.29 | 211 | 0 | 1 | restart only | 13.04 | k3d-pg-ha-server-0 | 0 | 1.94 | PASS |
| 2 | pg-2 | pg-1 | 4.65 | 4.65 | 207 | 0 | 1 | restart only | 16.04 | k3d-pg-ha-server-0 | 0 | 2.24 | PASS |
| 3 | pg-1 | pg-0 | 4.54 | 4.69 | 171 | 0 | 1 | restart only | 18.05 | k3d-pg-ha-server-0 | 0 | 2.93 | PASS |

RTO: min 3.01 s, median 4.54 s, max 4.65 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 3.01 s) | PASS |
| run 1: RPO 0, all 211 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 4.65 s) | PASS |
| run 2: RPO 0, all 207 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 2: no new archive failures on the primary pg-1 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 3: writes resumed on the new primary (RTO 4.54 s) | PASS |
| run 3: RPO 0, all 171 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 3: no new archive failures on the primary pg-0 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:12:21.397 UTC on primary `pg-0` (10.42.2.14, node `k3d-pg-ha-agent-0`, timeline 7). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.qLQ1IpH29d/run1/old-before-restore.log | head -8
2026-11-26 15:12:22,945 INFO: Leader key released
2026-11-26 15:12:23,281 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 211 acknowledged, 5 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 211 rounds of 3 members.

First acknowledged write on the new primary at 15:12:24.411 UTC. Last on the old primary at 15:12:21.116 UTC. Timeline 7 -> 8. Fault restored at 15:12:26.820, old member streaming from the new primary at 15:12:34.435 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.qLQ1IpH29d/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:12:33.185 UTC [36] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-26 15:12:33.408 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 1.94 s (bound 90 s). Last archived `000000080000000000000020`. Pending .ready: 0 (-).

## Run 2

Fault at 15:14:23.522 UTC on primary `pg-2` (10.42.1.7, node `k3d-pg-ha-agent-2`, timeline 8). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.qLQ1IpH29d/run2/old-before-restore.log | head -8
2026-11-26 15:14:26,622 INFO: Leader key released
2026-11-26 15:14:26,928 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 207 acknowledged, 8 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 209 rounds of 3 members.

First acknowledged write on the new primary at 15:14:28.172 UTC. Last on the old primary at 15:14:23.526 UTC. Timeline 8 -> 9. Fault restored at 15:14:30.490, old member streaming from the new primary at 15:14:39.559 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.qLQ1IpH29d/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:14:37.322 UTC [35] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-26 15:14:37.564 UTC [32] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.24 s (bound 90 s). Last archived `000000090000000000000022`. Pending .ready: 0 (-).

## Run 3

Fault at 15:16:27.267 UTC on primary `pg-1` (10.42.4.8, node `k3d-pg-ha-agent-1`, timeline 9). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

```console
$ grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' /tmp/tmp.qLQ1IpH29d/run3/old-before-restore.log | head -8
    raise RetryFailedError("Too many retry attempts")
patroni.utils.RetryFailedError: Too many retry attempts
2026-11-26 15:16:30,463 INFO: Leader key released
2026-11-26 15:16:30,893 INFO: released leader key voluntarily as data dir empty and currently leader
```

Probe: 171 acknowledged, 16 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 114 rounds of 3 members.

First acknowledged write on the new primary at 15:16:31.805 UTC. Last on the old primary at 15:16:27.113 UTC. Timeline 9 -> 10. Fault restored at 15:16:35.050, old member streaming from the new primary at 15:16:45.317 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.qLQ1IpH29d/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:16:41.887 UTC [36] LOG:  database system was not properly shut down; automatic recovery in progress
2026-11-26 15:16:42.210 UTC [33] LOG:  database system is ready to accept read-only connections
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.93 s (bound 90 s). Last archived `0000000A0000000000000024`. Pending .ready: 0 (-).
