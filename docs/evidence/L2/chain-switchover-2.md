# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- **Run:** 2026-11-25T15:25:01Z (UTC), 67 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-2 | pg-1 | 3.90 | 4.06 | 90 | 0 | 1 | restart only | 9.34 | k3d-pg-ha-server-0 | 0 | 3.77 | PASS |

RTO: min 3.90 s, median 3.90 s, max 3.90 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-2 to a new leader (pg-1) | PASS |
| run 1: writes resumed on the new primary (RTO 3.90 s) | PASS |
| run 1: RPO 0, all 90 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-2 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-2) | PASS |
| run 1: no new archive failures on the primary pg-1 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:25:15.499 UTC on primary `pg-2` (10.42.3.7, node `k3d-pg-ha-agent-2`, timeline 21). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 90 acknowledged, 7 failed attempts. Lock holders sampled: `pg-2>pg-1`. Leadership samples: 91 rounds of 3 members.

First acknowledged write on the new primary at 15:25:19.398 UTC. Last on the old primary at 15:25:15.340 UTC. Timeline 21 -> 22. Fault restored at 15:25:19.806, old member streaming from the new primary at 15:25:24.841 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.rGQGvpRlDN/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 15:25:15,580 INFO: switchover: demoting myself
2026-11-25 15:25:15,581 INFO: Demoting self (graceful)
2026-11-25 15:25:17.239 UTC [784] LOG:  database system is shut down
2026-11-25 15:25:18,033 INFO: switchover: demote in progress
2026-11-25 15:25:18,166 INFO: switchover: demote in progress
2026-11-25 15:25:19,098 INFO: switchover: demote in progress
2026-11-25 15:25:19,173 INFO: switchover: demote in progress
2026-11-25 15:25:21.549 UTC [1484] LOG:  database system was shut down at 2026-11-25 15:25:16 UTC
2026-11-25 15:25:21.845 UTC [1481] LOG:  database system is ready to accept read-only connections
2026-11-25 15:25:22,243 INFO: switchover: demote in progress
2026-11-25 15:25:22,244 INFO: switchover: demote in progress
```

```console
$ cat /tmp/tmp.rGQGvpRlDN/run1/switchover.txt
Successfully switched over to "pg-1"
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 3.77 s (bound 90 s). Last archived `00000016000000000000004D`. Pending .ready: 0 (-).
