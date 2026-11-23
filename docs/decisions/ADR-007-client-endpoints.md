# ADR-007: Client endpoints and pooling

**Status:** Accepted

## Context

Clients need one stable primary endpoint and a separate read-only endpoint. By default, a pod on a dead node can stay in a selector-based Service for up to 50 s (`node-monitor-grace-period`).

## Options considered

- **Patroni-managed `pg-rw` + selector-based `pg-ro`:** primary routing changes atomically with leadership.
- **Label selectors for both:** standard, but a dead primary can linger.
- **HAProxy:** fast routing, but another HA component.
- **PgBouncer:** connection protection, but an extra hop and more auth configuration.

## Decision

Use a selector-less **`pg-rw`** whose Endpoints Patroni writes, and **`pg-ro`** selecting ready pods with `role=replica`. Set `node-monitor-grace-period=20s`. Do **not** add a connection pooler.

## Consequences

- The primary endpoint follows the leader lock directly.
- Routing depends on EndpointSlice mirroring, whose latency is measured in spike S4.
- Clients need short connect timeouts and TCP keepalives to reconnect quickly.
- Applications with many short connections would need a pooler in production.

## R-IDs covered

R2.1, R2.2, R2.3, R2.4, R2.5, R3.2, R3.7, R6.3
