# ADR-011: Observability

**Status:** Accepted

## Context

We need metrics and alerts from our own manifests, with no operators or charts (D1, D2).

## Options considered

- **Prometheus, Alertmanager, postgres_exporter, Patroni metrics, kube-state-metrics and node_exporter.**
- **The same with Pushgateway** instead of kube-state-metrics.
- **Adding Grafana** for dashboards.

## Decision

Use the first option. kube-state-metrics supplies backup and restore Job status, and node_exporter supplies disk space.

**Grafana is out of scope** unless every MUST and every other SHOULD is done. R10.4 is then the only remaining item it serves.

Required alerts: no primary, multiple primaries, instance down, high lag, slot WAL high, slot lost, archive failing, backup stale, restore test failed and low disk. Rules are tested with `promtool test rules`.

## Consequences

- Every required alert has a standard metric source.
- Without Grafana, R10.4 stays unmet and is listed in known limitations.
- node_exporter needs a documented Pod Security exception for host filesystem access.
- Alertmanager uses a no-op receiver, so no webhook secret exists in the repo.

## R-IDs covered

R1.6, R1.7, R10.1, R10.2, R10.3, R10.5
