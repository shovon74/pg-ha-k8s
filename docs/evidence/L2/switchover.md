# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- **Run:** 2026-11-25T13:25:26Z (UTC), 63 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 2.08 | 2.15 | 95 | 0 | 1 | restart only | 8.90 | k3d-pg-ha-server-0 | 0 | 1.84 | PASS |

RTO: min 2.08 s, median 2.08 s, max 2.08 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-1 to a new leader (pg-0) | PASS |
| run 1: writes resumed on the new primary (RTO 2.08 s) | PASS |
| run 1: RPO 0, all 95 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-1 rejoined as a streaming replica of pg-0, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-0) | PASS |
| run 1: no new archive failures on the primary pg-0 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 13:25:42.333 UTC on primary `pg-1` (10.42.4.6, node `k3d-pg-ha-agent-0`, timeline 13). Sync standby before: `pg-0`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 95 acknowledged, 3 failed attempts. Lock holders sampled: `pg-1>pg-0`. Leadership samples: 92 rounds of 3 members.

First acknowledged write on the new primary at 13:25:44.411 UTC. Last on the old primary at 13:25:42.263 UTC. Timeline 13 -> 14. Fault restored at 13:25:45.612, old member streaming from the new primary at 13:25:51.229 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.4Zd6E2QWtm/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 13:25:42,420 INFO: switchover: demoting myself
2026-11-25 13:25:42,423 INFO: Demoting self (graceful)
2026-11-25 13:25:43.364 UTC [1781] LOG:  database system is shut down
2026-11-25 13:25:43,638 INFO: switchover: demote in progress
2026-11-25 13:25:43,823 INFO: switchover: demote in progress
2026-11-25 13:25:44,792 INFO: switchover: demote in progress
2026-11-25 13:25:44,871 INFO: switchover: demote in progress
2026-11-25 13:25:46.785 UTC [3576] LOG:  database system was shut down at 2026-11-25 13:25:42 UTC
2026-11-25 13:25:46.990 UTC [3573] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.4Zd6E2QWtm/run1/switchover.txt
Successfully switched over to "pg-0"
```

Archive health on primary `pg-0`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 1.84 s (bound 90 s). Last archived `0000000E0000000000000030`. Pending .ready: 0 (-).
