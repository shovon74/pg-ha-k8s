# L5: Alerts on an object-storage outage (R10.3, R9.6)

**Result: PASS**

- **What:** The primary pod's traffic to Garage is dropped with iptables on its node while a writer fills WAL. Writes must continue, ArchiveFailing and ArchiveStale must fire in Alertmanager, and after the block is removed archiving must catch up with no segment left waiting and both alerts resolve.
- **Run:** 2026-11-26T16:21:19Z (UTC), 433 s
- **Reproduce:** `make alerts-archive`
- **Versions:** Prometheus `prom/prometheus:v3.16.0`, Alertmanager `prom/alertmanager:v0.34.2`, postgres_exporter `quay.io/prometheuscommunity/postgres-exporter:v0.20.1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **History:** [`L5-monitoring-history.md`](../L5-monitoring-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| No warning or critical alert firing before the fault | PASS |
| ArchiveFailing fired | PASS |
| ArchiveStale fired | PASS |
| Writes continued during the outage (8 WAL fills succeeded, 0 failed) | PASS |
| Primary did not change during the outage (pg-1) | PASS |
| WAL waited in .ready during the outage (9 segments) | PASS |
| Archive caught up: no .ready segment left (14 s after unblocking) | PASS |
| Last archived segment 0000001800000000000000C1 is at or past the newest segment that waited (0000001800000000000000C1) | PASS |
| A new segment is archived within 90 s after recovery (1.79 s, no new failures: 0) | PASS |
| ArchiveFailing and ArchiveStale resolved | PASS |
| No warning or critical alert firing at the end | PASS |

## Before

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; archive_stat pg-rw.pg-ha.svc.cluster.local
failed_count last_archived_epoch last_archived_wal ready_count ready_names
1 1795710077.706024 0000001800000000000000B8 0 -
```

```console
$ am_lines

```

Primary `pg-1` (10.42.4.9) on `k3d-pg-ha-agent-1`. Garage pod 10.42.0.52:3900.

## Fault

Rule on `k3d-pg-ha-agent-1`: `iptables -I FORWARD 1 -s 10.42.4.9 -d 10.42.0.52 -p tcp --dport 3900 -j DROP` at 16:21:24 UTC. A writer fills one 16 MB+ WAL segment through pg-rw every 15 s.

## Alertmanager during the outage (make alerts)

```console
$ scripts/alerts.sh
Firing alerts in Alertmanager at 2026-11-26T16:23:38Z (UTC):
  CRIT  ArchiveStale  since 2026-11-26T16:23:37Z  A completed WAL segment on pg-1 has waited 2m 8s to be archived; PITR is losing data.
  WARN  ArchiveFailing  since 2026-11-26T16:22:37Z  WAL archiving on pg-1 failed in the last 5 min.
```

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '3 1795710077.706024 0000001800000000000000B8 9 0000001800000000000000B9,0000001800000000000000BA,0000001800000000000000BB,0000001800000000000000BC,0000001800000000000000BD,0000001800000000000000BE,0000001800000000000000BF,0000001800000000000000C0,0000001800000000000000C1'
failed_count last_archived_epoch last_archived_wal ready_count ready_names
3 1795710077.706024 0000001800000000000000B8 9 0000001800000000000000B9,0000001800000000000000BA,0000001800000000000000BB,0000001800000000000000BC,0000001800000000000000BD,0000001800000000000000BE,0000001800000000000000BF,0000001800000000000000C0,0000001800000000000000C1
```

## Recovery

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '3 1795710232.612460 0000001800000000000000C1 0 -'
failed_count last_archived_epoch last_archived_wal ready_count ready_names
3 1795710232.612460 0000001800000000000000C1 0 -
```

```console
$ am_lines

```

## Timeline

Times are UTC. Alertmanager was polled every 5 s through the API server's service proxy, so each time is accurate to about 5 s. ArchiveFailing waits for pgBackRest's first failed archive-push. With dropped packets that is its io-timeout (60 s). ArchiveFailing then clears 5 min after the last failure, because its window is 5 min.

<!-- summary -->
| Event | Time | Seconds after fault |
|---|---|---:|
| Primary pg-1 blocked from Garage | 16:21:24 | 0 |
| Block removed | 16:23:39 | 135 |
| No .ready segment left (caught up) | 16:23:53 | 149 |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
| ArchiveFailing | 16:22:42 | 78 | 16:28:32 | 428 |
| ArchiveStale | 16:23:38 | 134 | 16:24:01 | 157 |

Archiver failures during the test: 2. Segments waiting at the end of the outage: 9.
<!-- /summary -->

Alertmanager's alert objects during the outage:

```json
[
  {
    "alertname": "ArchiveFailing",
    "severity": "warning",
    "pod": "pg-1",
    "startsAt": "2026-11-26T16:22:37.620Z",
    "summary": "WAL archiving on pg-1 failed in the last 5 min."
  },
  {
    "alertname": "ArchiveStale",
    "severity": "critical",
    "pod": "pg-1",
    "startsAt": "2026-11-26T16:23:37.620Z",
    "summary": "A completed WAL segment on pg-1 has waited 2m 8s to be archived; PITR is losing data."
  }
]
```
