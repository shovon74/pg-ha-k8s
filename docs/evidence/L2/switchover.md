# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. Since L6 the POST carries basic auth (user `patroni`, password from `./secrets`, passed to curl on stdin); unauthenticated state-changing requests are refused (`make test-security`).
- **Run:** 2026-11-26T15:24:37Z (UTC), 192 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 2.56 | 2.64 | 93 | 0 | 1 | restart only | 9.01 | k3d-pg-ha-server-0 | 0 | 1.66 | PASS |
| 2 | pg-2 | pg-1 | 2.60 | 2.63 | 94 | 0 | 1 | restart only | 8.38 | k3d-pg-ha-server-0 | 0 | 2.19 | PASS |
| 3 | pg-1 | pg-0 | 2.72 | 2.78 | 93 | 0 | 1 | restart only | 8.06 | k3d-pg-ha-server-0 | 0 | 2.65 | PASS |

RTO: min 2.56 s, median 2.60 s, max 2.72 s over 3 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 2.56 s) | PASS |
| run 1: RPO 0, all 93 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 2: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 2: writes resumed on the new primary (RTO 2.60 s) | PASS |
| run 2: RPO 0, all 94 acknowledged rows present on the new primary | PASS |
| run 2: never more than 1 member out of recovery in any sample | PASS |
| run 2: no acknowledged write on the old primary after the new primary's first | PASS |
| run 2: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 2: old primary in recovery on the new leader's timeline | PASS |
| run 2: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 2: no new archive failures on the primary pg-1 | PASS |
| run 2: the primary archived a segment within 90 s of a WAL fill | PASS |
| run 3: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 3: writes resumed on the new primary (RTO 2.72 s) | PASS |
| run 3: RPO 0, all 93 acknowledged rows present on the new primary | PASS |
| run 3: never more than 1 member out of recovery in any sample | PASS |
| run 3: no acknowledged write on the old primary after the new primary's first | PASS |
| run 3: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 3: old primary in recovery on the new leader's timeline | PASS |
| run 3: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 3: no new archive failures on the primary pg-0 | PASS |
| run 3: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:24:54.118 UTC on primary `pg-0` (10.42.2.15, node `k3d-pg-ha-agent-0`, timeline 13). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 93 acknowledged, 4 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 92 rounds of 3 members.

First acknowledged write on the new primary at 15:24:56.674 UTC. Last on the old primary at 15:24:54.033 UTC. Timeline 13 -> 14. Fault restored at 15:24:57.355, old member streaming from the new primary at 15:25:03.123 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.ZTG6bBkDDC/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:24:54,220 INFO: switchover: demoting myself
2026-11-26 15:24:54,220 INFO: Demoting self (graceful)
2026-11-26 15:24:55.126 UTC [1530] LOG:  database system is shut down
2026-11-26 15:24:55,454 INFO: switchover: demote in progress
2026-11-26 15:24:55,455 INFO: switchover: demote in progress
2026-11-26 15:24:56,584 INFO: switchover: demote in progress
2026-11-26 15:24:56,662 INFO: switchover: demote in progress
2026-11-26 15:24:58.437 UTC [3358] LOG:  database system was shut down at 2026-11-26 15:24:54 UTC
2026-11-26 15:24:58.630 UTC [3355] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.ZTG6bBkDDC/run1/switchover.txt
Successfully switched over to "pg-2"
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 1.66 s (bound 90 s). Last archived `0000000E000000000000002F`. Pending .ready: 0 (-).

## Run 2

Fault at 15:25:55.651 UTC on primary `pg-2` (10.42.1.8, node `k3d-pg-ha-agent-2`, timeline 14). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 94 acknowledged, 4 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 94 rounds of 3 members.

First acknowledged write on the new primary at 15:25:58.253 UTC. Last on the old primary at 15:25:55.618 UTC. Timeline 14 -> 15. Fault restored at 15:25:58.917, old member streaming from the new primary at 15:26:04.029 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.ZTG6bBkDDC/run2/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:25:55,824 INFO: switchover: demoting myself
2026-11-26 15:25:55,828 INFO: Demoting self (graceful)
2026-11-26 15:25:56.796 UTC [1520] LOG:  database system is shut down
2026-11-26 15:25:57,031 INFO: switchover: demote in progress
2026-11-26 15:25:58,272 INFO: switchover: demote in progress
2026-11-26 15:25:58,361 INFO: switchover: demote in progress
2026-11-26 15:26:00.160 UTC [3123] LOG:  database system was shut down at 2026-11-26 15:25:56 UTC
2026-11-26 15:26:00.437 UTC [3120] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.ZTG6bBkDDC/run2/switchover.txt
Successfully switched over to "pg-1"
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.19 s (bound 90 s). Last archived `0000000F0000000000000031`. Pending .ready: 0 (-).

## Run 3

Fault at 15:27:00.142 UTC on primary `pg-1` (10.42.4.9, node `k3d-pg-ha-agent-1`, timeline 15). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 93 acknowledged, 4 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 90 rounds of 3 members.

First acknowledged write on the new primary at 15:27:02.861 UTC. Last on the old primary at 15:27:00.078 UTC. Timeline 15 -> 16. Fault restored at 15:27:03.537, old member streaming from the new primary at 15:27:08.206 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.ZTG6bBkDDC/run3/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-26 15:27:00,339 INFO: switchover: demoting myself
2026-11-26 15:27:00,345 INFO: Demoting self (graceful)
2026-11-26 15:27:01.226 UTC [1524] LOG:  database system is shut down
2026-11-26 15:27:01,589 INFO: switchover: demote in progress
2026-11-26 15:27:01,720 INFO: switchover: demote in progress
2026-11-26 15:27:02,749 INFO: switchover: demote in progress
2026-11-26 15:27:02,930 INFO: switchover: demote in progress
2026-11-26 15:27:04.741 UTC [2858] LOG:  database system was shut down at 2026-11-26 15:27:00 UTC
2026-11-26 15:27:05.062 UTC [2855] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.ZTG6bBkDDC/run3/switchover.txt
Successfully switched over to "pg-0"
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.65 s (bound 90 s). Last archived `000000100000000000000033`. Pending .ready: 0 (-).
