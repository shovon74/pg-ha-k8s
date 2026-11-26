# L5: Alerts on a node failover (R10.3)

**Result: PASS**

- **What:** `docker stop` of the primary's k3d agent for 180 s, then `docker start`. MemberDown, ReplicaNotStreaming and FailoverOccurred must fire in Alertmanager and then resolve. NoPrimary and MultiplePrimaries must stay silent. Read from the Alertmanager API through the API server's service proxy.
- **Run:** 2026-11-26T16:08:24Z (UTC), 341 s
- **Reproduce:** `make alerts-failover`
- **Versions:** Prometheus `prom/prometheus:v3.16.0`, Alertmanager `prom/alertmanager:v0.34.2`, postgres_exporter `quay.io/prometheuscommunity/postgres-exporter:v0.20.1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **History:** [`L5-monitoring-history.md`](../L5-monitoring-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| No warning or critical alert firing before the fault | PASS |
| MemberDown firing while the node is down | PASS |
| ReplicaNotStreaming firing while the node is down | PASS |
| MemberDown names the old primary pg-2 | PASS |
| FailoverOccurred fired (new primary pg-1) | PASS |
| A new primary took over (pg-1, 23 s after the fault) | PASS |
| Cluster healthy again: 1 leader, 2 streaming, 1 sync (22 s after docker start) | PASS |
| MemberDown, ReplicaNotStreaming and FailoverOccurred all resolved | PASS |
| NoPrimary never fired (failover finished within its 45 s delay) | PASS |
| MultiplePrimaries never fired | PASS |
| No warning or critical alert firing at the end | PASS |

## Before

```console
$ am_lines

```

Primary `pg-2` on `k3d-pg-ha-agent-2`, timeline 23. CoreDNS on: k3d-pg-ha-server-0.

## Fault

`docker stop k3d-pg-ha-agent-2` at 16:08:25 UTC. Held for 180 s.

## Alertmanager at the end of the outage (make alerts)

```console
$ scripts/alerts.sh
Firing alerts in Alertmanager at 2026-11-26T16:11:30Z (UTC):
  INFO  FailoverOccurred  since 2026-11-26T16:09:00Z  The timeline in pg-ha increased in the last 5 min: a member was promoted (failover or switchover).
  WARN  MemberDown  since 2026-11-26T16:09:10Z  Patroni member pg-2 in pg-ha is down or Postgres is not running.
  WARN  MemberDown  since 2026-11-26T16:09:10Z  Fewer Patroni members are up in pg-ha than the StatefulSet expects.
  WARN  ReplicaNotStreaming  since 2026-11-26T16:10:30Z  Fewer standbys are streaming than expected in pg-ha (a member is down, re-cloning or disconnected).
```

## Recovery

```console
$ am_lines

```

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) role=\(.role) state=\(.state) timeline=\(.timeline)"'
pg-0 role=sync_standby state=streaming timeline=24
pg-1 role=leader state=running timeline=24
pg-2 role=replica state=streaming timeline=24
```

## Timeline

Times are UTC. Alertmanager was polled every 5 s through the API server's service proxy, so each time is accurate to about 5 s. Alert delays add the scrape interval (10 s), the rule evaluation interval (10 s) and Alertmanager's group_wait (10 s) to each rule's `for`.

<!-- summary -->
| Event | Time | Seconds after fault |
|---|---|---:|
| docker stop k3d-pg-ha-agent-2 (primary pg-2) | 16:08:25 | 0 |
| New primary pg-1 holds the lock | 16:08:48 | 23 |
| docker start | 16:11:30 | 185 |
| Cluster healthy (3 members, sync standby) | 16:11:52 | 207 |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
| MemberDown | 16:09:15 | 50 | 16:12:02 | 217 |
| ReplicaNotStreaming | 16:10:32 | 127 | 16:12:02 | 217 |
| FailoverOccurred | 16:09:04 | 39 | 16:14:05 | 340 |
<!-- /summary -->

Alertmanager's full alert objects at the end of the outage:

```json
[
  {
    "alertname": "ReplicaNotStreaming",
    "severity": "warning",
    "pod": null,
    "startsAt": "2026-11-26T16:10:30.387Z",
    "summary": "Fewer standbys are streaming than expected in pg-ha (a member is down, re-cloning or disconnected)."
  },
  {
    "alertname": "MemberDown",
    "severity": "warning",
    "pod": "pg-2",
    "startsAt": "2026-11-26T16:09:10.387Z",
    "summary": "Patroni member pg-2 in pg-ha is down or Postgres is not running."
  },
  {
    "alertname": "MemberDown",
    "severity": "warning",
    "pod": null,
    "startsAt": "2026-11-26T16:09:10.387Z",
    "summary": "Fewer Patroni members are up in pg-ha than the StatefulSet expects."
  },
  {
    "alertname": "FailoverOccurred",
    "severity": "info",
    "pod": null,
    "startsAt": "2026-11-26T16:09:00.387Z",
    "summary": "The timeline in pg-ha increased in the last 5 min: a member was promoted (failover or switchover)."
  }
]
```
