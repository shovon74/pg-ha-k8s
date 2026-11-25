# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- **Run:** 2026-11-25T13:41:30Z (UTC), 62 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 2.61 | 2.62 | 94 | 0 | 1 | restart only | 7.61 | k3d-pg-ha-server-0 | 0 | 2.26 | PASS |

RTO: min 2.61 s, median 2.61 s, max 2.61 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 2.61 s) | PASS |
| run 1: RPO 0, all 94 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:41:43.985 UTC on primary `pg-0` (10.42.1.11, node `k3d-pg-ha-agent-1`, timeline 17). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 94 acknowledged, 4 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 92 rounds of 3 members.

First acknowledged write on the new primary at 13:41:46.599 UTC. Last on the old primary at 13:41:43.975 UTC. Timeline 17 -> 18. Fault restored at 13:41:47.236, old member streaming from the new primary at 13:41:51.595 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.ZUVsEuXeWd/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:41:44,070 INFO: switchover: demoting myself
2026-11-25 13:41:44,071 INFO: Demoting self (graceful)
2026-11-25 13:41:45.023 UTC [32] LOG:  database system is shut down
2026-11-25 13:41:45,286 INFO: switchover: demote in progress
2026-11-25 13:41:46,454 INFO: switchover: demote in progress
2026-11-25 13:41:48.567 UTC [1741] LOG:  database system was shut down at 2026-11-25 13:41:44 UTC
2026-11-25 13:41:48.826 UTC [1738] LOG:  database system is ready to accept read-only connections
2026-11-25 13:41:49,520 INFO: switchover: demote in progress
2026-11-25 13:41:49,521 INFO: switchover: demote in progress
```

```console
$ cat /tmp/tmp.ZUVsEuXeWd/run1/switchover.txt
Successfully switched over to "pg-2"
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.26 s (bound 90 s). Last archived `000000120000000000000041`. Pending .ready: 0 (-).
