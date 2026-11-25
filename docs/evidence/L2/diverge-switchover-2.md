# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- **Run:** 2026-11-25T15:31:26Z (UTC), 62 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 2.51 | 2.58 | 93 | 0 | 1 | restart only | 7.86 | k3d-pg-ha-server-0 | 0 | 2.21 | PASS |

RTO: min 2.51 s, median 2.51 s, max 2.51 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-2) | PASS |
| run 1: writes resumed on the new primary (RTO 2.51 s) | PASS |
| run 1: RPO 0, all 93 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-2, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 1: no new archive failures on the primary pg-2 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 15:31:39.689 UTC on primary `pg-0` (10.42.1.14, node `k3d-pg-ha-agent-1`, timeline 26). Sync standby before: `pg-2`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 93 acknowledged, 4 failed attempts. Lock holders sampled: `pg-0>pg-2`. Leadership samples: 91 rounds of 3 members.

First acknowledged write on the new primary at 15:31:42.194 UTC. Last on the old primary at 15:31:39.610 UTC. Timeline 26 -> 27. Fault restored at 15:31:42.953, old member streaming from the new primary at 15:31:47.552 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.GIyuyTOYvh/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 15:31:39,796 INFO: switchover: demoting myself
2026-11-25 15:31:39,804 INFO: Demoting self (graceful)
2026-11-25 15:31:40.714 UTC [32] LOG:  database system is shut down
2026-11-25 15:31:41,031 INFO: switchover: demote in progress
2026-11-25 15:31:42,126 INFO: switchover: demote in progress
2026-11-25 15:31:42,186 INFO: switchover: demote in progress
2026-11-25 15:31:44.173 UTC [629] LOG:  database system was shut down at 2026-11-25 15:31:40 UTC
2026-11-25 15:31:44.409 UTC [626] LOG:  database system is ready to accept read-only connections
2026-11-25 15:31:45,320 INFO: switchover: demote in progress
```

```console
$ cat /tmp/tmp.GIyuyTOYvh/run1/switchover.txt
Successfully switched over to "pg-2"
```

Archive health on primary `pg-2`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 2.21 s (bound 90 s). Last archived `0000001B0000000000000058`. Pending .ready: 0 (-).
