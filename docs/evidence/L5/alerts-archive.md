# L5: Alerts on an object-storage outage (R10.3, R9.6)

**Result: PASS**

- **What:** The primary pod's traffic to Garage is dropped with iptables on its node while a writer fills WAL. Writes must continue, ArchiveFailing and ArchiveStale must fire in Alertmanager, and after the block is removed archiving must catch up with no segment left waiting and both alerts resolve.
- **Run:** 2026-11-25T16:39:13Z (UTC), 427 s
- **Reproduce:** `make alerts-archive`
- **Versions:** Prometheus `prom/prometheus:v3.16.0`, Alertmanager `prom/alertmanager:v0.34.2`, postgres_exporter `quay.io/prometheuscommunity/postgres-exporter:v0.20.1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Checks

| Check | Result |
|---|---|
| No warning or critical alert firing before the fault | PASS |
| ArchiveFailing fired | PASS |
| ArchiveStale fired | PASS |
| Writes continued during the outage (9 WAL fills succeeded, 0 failed) | PASS |
| Primary did not change during the outage (pg-2) | PASS |
| WAL waited in .ready during the outage (11 segments) | PASS |
| Archive caught up: no .ready segment left (13 s after unblocking) | PASS |
| Last archived segment 000000240000000000000090 is at or past the newest segment that waited (000000240000000000000090) | PASS |
| A new segment is archived within 90 s after recovery (2.71 s, no new failures: 0) | PASS |
| ArchiveFailing and ArchiveStale resolved | PASS |
| No warning or critical alert firing at the end | PASS |

## Before

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; archive_stat pg-rw.pg-ha.svc.cluster.local
failed_count last_archived_epoch last_archived_wal ready_count ready_names
0 1795624745.870652 000000240000000000000085 0 -
```

```console
$ am_lines

```

Primary `pg-2` (10.42.3.21) on `k3d-pg-ha-agent-2`. Garage pod 10.42.0.7:3900.

## Fault

Rule on `k3d-pg-ha-agent-2`: `iptables -I FORWARD 1 -s 10.42.3.21 -d 10.42.0.7 -p tcp --dport 3900 -j DROP` at 16:39:15 UTC. A writer fills one 16 MB+ WAL segment through pg-rw every 15 s.

## Alertmanager during the outage (make alerts)

```console
$ scripts/alerts.sh
Firing alerts in Alertmanager at 2026-11-25T16:41:28Z (UTC):
  CRIT  ArchiveStale  since 2026-11-25T16:41:27Z  A completed WAL segment on pg-2 has waited 2m 2s to be archived; PITR is losing data.
  WARN  ArchiveFailing  since 2026-11-25T16:40:27Z  WAL archiving on pg-2 failed in the last 5 min.
```

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '2 1795624745.870652 000000240000000000000085 11 000000240000000000000086,000000240000000000000087,000000240000000000000088,000000240000000000000089,00000024000000000000008A,00000024000000000000008B,00000024000000000000008C,00000024000000000000008D,00000024000000000000008E,00000024000000000000008F,000000240000000000000090'
failed_count last_archived_epoch last_archived_wal ready_count ready_names
2 1795624745.870652 000000240000000000000085 11 000000240000000000000086,000000240000000000000087,000000240000000000000088,000000240000000000000089,00000024000000000000008A,00000024000000000000008B,00000024000000000000008C,00000024000000000000008D,00000024000000000000008E,00000024000000000000008F,000000240000000000000090
```

## Recovery

```console
$ echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '2 1795624902.670678 000000240000000000000090 0 -'
failed_count last_archived_epoch last_archived_wal ready_count ready_names
2 1795624902.670678 000000240000000000000090 0 -
```

```console
$ am_lines

```

## Timeline

Times are UTC. Alertmanager was polled every 5 s through the API server's service proxy, so each time is accurate to about 5 s. ArchiveFailing waits for pgBackRest's first failed archive-push. With dropped packets that is its io-timeout (60 s). ArchiveFailing then clears 5 min after the last failure, because its window is 5 min.

<!-- summary -->
| Event | Time | Seconds after fault |
|---|---|---:|
| Primary pg-2 blocked from Garage | 16:39:15 | 0 |
| Block removed | 16:41:29 | 134 |
| No .ready segment left (caught up) | 16:41:42 | 147 |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
| ArchiveFailing | 16:40:32 | 77 | 16:46:19 | 424 |
| ArchiveStale | 16:41:28 | 133 | 16:41:57 | 162 |

Archiver failures during the test: 2. Segments waiting at the end of the outage: 11.
<!-- /summary -->

Alertmanager's alert objects during the outage:

```json
[
  {
    "alertname": "ArchiveFailing",
    "severity": "warning",
    "pod": "pg-2",
    "startsAt": "2026-11-25T16:40:27.620Z",
    "summary": "WAL archiving on pg-2 failed in the last 5 min."
  },
  {
    "alertname": "ArchiveStale",
    "severity": "critical",
    "pod": "pg-2",
    "startsAt": "2026-11-25T16:41:27.620Z",
    "summary": "A completed WAL segment on pg-2 has waited 2m 2s to be archived; PITR is losing data."
  }
]
```
