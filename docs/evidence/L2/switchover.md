# L2 failure mode: switchover

**Result: PASS**

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. Since L6 the POST carries basic auth (user `patroni`, password from `./secrets`, passed to curl on stdin); unauthenticated state-changing requests are refused (`make test-security`).
- **Run:** 2026-11-25T17:24:34Z (UTC), 64 s
- **Reproduce:** `make switchover`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.

## Summary

| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-1 | 3.07 | 3.19 | 92 | 0 | 1 | restart only | 8.09 | k3d-pg-ha-server-0 | 0 | 1.73 | PASS |

RTO: min 3.07 s, median 3.07 s, max 3.07 s over 1 runs. Target 30 s.

## Checks

| Check | Result |
|---|---|
| run 1: lock moved from pg-0 to a new leader (pg-1) | PASS |
| run 1: writes resumed on the new primary (RTO 3.07 s) | PASS |
| run 1: RPO 0, all 92 acknowledged rows present on the new primary | PASS |
| run 1: never more than 1 member out of recovery in any sample | PASS |
| run 1: no acknowledged write on the old primary after the new primary's first | PASS |
| run 1: old primary pg-0 rejoined as a streaming replica of pg-1, sync standby restored | PASS |
| run 1: old primary in recovery on the new leader's timeline | PASS |
| run 1: CoreDNS was not on the faulted primary's node (k3d-pg-ha-agent-1) | PASS |
| run 1: no new archive failures on the primary pg-1 | PASS |
| run 1: the primary archived a segment within 90 s of a WAL fill | PASS |

## Run 1

Fault at 17:24:50.952 UTC on primary `pg-0` (10.42.1.53, node `k3d-pg-ha-agent-1`, timeline 40). Sync standby before: `pg-1`. CoreDNS on `k3d-pg-ha-server-0`.

Probe: 92 acknowledged, 5 failed attempts. Lock holders sampled: `pg-0>pg-1`. Leadership samples: 93 rounds of 3 members.

First acknowledged write on the new primary at 17:24:54.021 UTC. Last on the old primary at 17:24:50.833 UTC. Timeline 40 -> 41. Fault restored at 17:24:54.201, old member streaming from the new primary at 17:24:59.045 UTC.

```console
$ grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' /tmp/tmp.NJe9JbmNze/run1/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12
2026-11-25 17:24:51,068 INFO: switchover: demoting myself
2026-11-25 17:24:51,069 INFO: Demoting self (graceful)
2026-11-25 17:24:52.203 UTC [33] LOG:  database system is shut down
2026-11-25 17:24:52,313 INFO: switchover: demote in progress
2026-11-25 17:24:52,324 INFO: switchover: demote in progress
2026-11-25 17:24:52,588 INFO: switchover: demote in progress
2026-11-25 17:24:53,617 INFO: switchover: demote in progress
2026-11-25 17:24:53,712 INFO: switchover: demote in progress
2026-11-25 17:24:55.296 UTC [536] LOG:  database system was shut down at 2026-11-25 17:24:51 UTC
2026-11-25 17:24:55.586 UTC [533] LOG:  database system is ready to accept read-only connections
```

```console
$ cat /tmp/tmp.NJe9JbmNze/run1/switchover.txt
Successfully switched over to "pg-1"
```

Archive health on primary `pg-1`: failed_count 0 before the fault, +0 since. After a WAL fill, a segment was archived in 1.73 s (bound 90 s). Last archived `0000002900000000000000B8`. Pending .ready: 0 (-).
