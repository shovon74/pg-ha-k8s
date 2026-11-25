# L5: monitoring and alerting

Generated from the per-part files in [`L5/`](L5/) each time a part runs. Timestamps are UTC. Design and alert table: [`../observability.md`](../observability.md).

| Part | Result | Checks passed | Details |
|---|---|---:|---|
| Alert rule unit tests (R10.2) | PASS | 4 of 4 | [`L5/alert-rules.md`](L5/alert-rules.md) |
| Scrape targets, key series, lag measurement and resources (R10.1, R1.7) | PASS | 33 of 33 | [`L5/metrics.md`](L5/metrics.md) |
| Alerts on a node failover (R10.3) | PASS | 11 of 11 | [`L5/alerts-failover.md`](L5/alerts-failover.md) |
| Alerts on an object-storage outage (R10.3, R9.6) | PASS | 11 of 11 | [`L5/alerts-archive.md`](L5/alerts-archive.md) |

## Alert rule unit tests (R10.2)

- **What:** `promtool check rules` and `promtool test rules` from the pinned Prometheus image, plus checks that every rule has a severity, a summary and a reason for its threshold, and that every alert has a test where it fires and one where it stays silent. The tests run against a copy of the rules without annotations, so they check labels and timing. No cluster is needed.

| Check | Result |
|---|---|
| promtool check rules passes on deploy/monitoring/rules/pg-ha.rules.yml | PASS |
| Every rule has severity, summary and why; every alert has a firing and a silent test | PASS |
| Every Postgres, backup and restore rule selects namespace="pg-ha" (unscoped: none) | PASS |
| promtool test rules passes (tests/alerts/pg-ha.test.yml) | PASS |

## Scrape targets, key series, lag measurement and resources (R10.1, R1.7)

- **What:** Every scrape target up, the key series for each alert present, all rules loaded and healthy, nothing firing on the healthy cluster, nothing scraped from pg-restore. Then induced lag (R1.7): the async standby's stream is throttled with iptables on the primary's node while a writer fills WAL. Lag in bytes and seconds must rise past the alert thresholds, ReplicationLagHigh must fire in Alertmanager (R10.3), and after the throttle lag must return to near zero and the alert resolve. Then RAM and disk use with monitoring running.

| Check | Result |
|---|---|
| Job patroni: 3 target(s) up (found 3) | PASS |
| Job postgres: 3 target(s) up (found 3) | PASS |
| Job node: 4 target(s) up (found 4) | PASS |
| Job kube-state-metrics: 1 target(s) up (found 1) | PASS |
| Job kube-state-metrics-self: 1 target(s) up (found 1) | PASS |
| Job alertmanager: 1 target(s) up (found 1) | PASS |
| Job prometheus: 1 target(s) up (found 1) | PASS |
| No target is down | PASS |
| Patroni role per member: 3 series (need 3) | PASS |
| Exactly one primary: 1 series (need 1) | PASS |
| Sync standby flag: 1 series (need 1) | PASS |
| Postgres reachable by each exporter: 3 series (need 3) | PASS |
| Timeline: 3 series (need 3) | PASS |
| Replication lag in bytes per standby (primary's view): 2 series (need 2) | PASS |
| Replication lag in seconds per standby (primary's view): 2 series (need 2) | PASS |
| Slot WAL retention: 6 series (need 2) | PASS |
| Archiver failure counter: 3 series (need 3) | PASS |
| Archive backlog (.ready): 3 series (need 3) | PASS |
| Backup and restore-test CronJobs: 2 series (need 2) | PASS |
| Backup or restore-test Job status: 2 series (need 1) | PASS |
| Expected member count: 1 series (need 1) | PASS |
| CoreDNS availability: 1 series (need 1) | PASS |
| Root filesystem free space per node: 4 series (need 4) | PASS |
| No series from namespace pg-restore is scraped | PASS |
| 19 alerting rules loaded | PASS |
| Every rule evaluates without error | PASS |
| No warning or critical alert firing before the fault | PASS |
| Lag in bytes rose above the 16 MiB threshold (peak 217712496) | PASS |
| Lag in seconds rose above the 30 s threshold (peak 123.599331) | PASS |
| The standby stayed connected during the throttle (state streaming) | PASS |
| ReplicationLagHigh fired in Alertmanager | PASS |
| Lag returned to near zero (< 1 MiB, < 1 s) within 180 s of removing the throttle | PASS |
| ReplicationLagHigh resolved in Alertmanager | PASS |
| Measure | Before | Peak during throttle | After |
|---|---:|---:|---:|
| Lag bytes (pg-2) | 0 | 217712496 | 0 |
| Lag seconds (pg-2) | 0.008617 | 123.599331 | 0.006325 |

| Event | Time (UTC) | Seconds after throttle start |
|---|---|---:|
| Throttle on | 16:53:11 | 0 |
| ReplicationLagHigh first seen firing | 16:55:24 | 133 |
| Throttle off | 16:55:26 | 135 |
| Lag back under 1 MiB and 1 s | 16:55:43 | 152 |
| ReplicationLagHigh gone from Alertmanager | 16:55:43 | 152 |
| Component (scrape job) | Processes | Resident memory, total |
|---|---:|---:|
| alertmanager | 1 | 40 MiB |
| kube-state-metrics-self | 1 | 54 MiB |
| node | 4 | 75 MiB |
| postgres | 3 | 58 MiB |
| prometheus | 1 | 121 MiB |
| Prometheus TSDB on disk | | 1 MiB |
| Host memory used / total | | 2577 / 15985 MiB |
| Host disk used / size (/) | | 13G / 48G (27%) |

## Alerts on a node failover (R10.3)

- **What:** `docker stop` of the primary's k3d agent for 180 s, then `docker start`. MemberDown, ReplicaNotStreaming and FailoverOccurred must fire in Alertmanager and then resolve. NoPrimary and MultiplePrimaries must stay silent. Read from the Alertmanager API through the API server's service proxy.

| Check | Result |
|---|---|
| No warning or critical alert firing before the fault | PASS |
| MemberDown firing while the node is down | PASS |
| ReplicaNotStreaming firing while the node is down | PASS |
| MemberDown names the old primary pg-2 | PASS |
| FailoverOccurred fired (new primary pg-1) | PASS |
| A new primary took over (pg-1, 23 s after the fault) | PASS |
| Cluster healthy again: 1 leader, 2 streaming, 1 sync (18 s after docker start) | PASS |
| MemberDown, ReplicaNotStreaming and FailoverOccurred all resolved | PASS |
| NoPrimary never fired (failover finished within its 45 s delay) | PASS |
| MultiplePrimaries never fired | PASS |
| No warning or critical alert firing at the end | PASS |
| Event | Time | Seconds after fault |
|---|---|---:|
| docker stop k3d-pg-ha-agent-2 (primary pg-2) | 16:46:41 | 0 |
| New primary pg-1 holds the lock | 16:47:04 | 23 |
| docker start | 16:49:44 | 183 |
| Cluster healthy (3 members, sync standby) | 16:50:02 | 201 |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
| MemberDown | 16:47:32 | 51 | 16:50:13 | 212 |
| ReplicaNotStreaming | 16:48:51 | 130 | 16:50:13 | 212 |
| FailoverOccurred | 16:47:10 | 29 | 16:52:10 | 329 |

## Alerts on an object-storage outage (R10.3, R9.6)

- **What:** The primary pod's traffic to Garage is dropped with iptables on its node while a writer fills WAL. Writes must continue, ArchiveFailing and ArchiveStale must fire in Alertmanager, and after the block is removed archiving must catch up with no segment left waiting and both alerts resolve.

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
