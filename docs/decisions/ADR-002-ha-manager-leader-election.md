# ADR-002: HA manager and leader election

**Status:** Accepted

## Context

Failover must be automatic and must never create two writers. Patroni is explicitly allowed if we wire it ourselves (HC4). Its Kubernetes DCS supports Endpoints or ConfigMaps, and does not implement Leases.

## Options considered

- **Patroni + Endpoints:** lock and leader address change in one atomic write. Patroni's docs call this the recommended mode.
- **Patroni + ConfigMaps:** avoids a deprecated API, but lock and routing change in separate updates.
- **Patroni + etcd:** independent consensus, but adds three stateful pods.
- **repmgr:** no built-in consensus lock, so fencing would be our own code.

## Decision

Use **Patroni 4.1.5 with `use_endpoints: true`** and **`failsafe_mode` off**.

Kubernetes v1.35.10, the base of the pinned k3s release, still defines the v1 Endpoints paths in its OpenAPI spec and marks the API as deprecated since v1.33. This was verified from source, and a runtime check is part of spike S4.

## API-server outage

With `failsafe_mode` off, a primary that cannot renew its lock **demotes itself**. Replicas cannot take the lock either. Writes stop until the API returns, reads continue, and no split-brain or data loss occurs.

This is the right trade-off here because the API server is a known single point of failure and safety outranks write availability. Failsafe mode would keep writes running only while all members can confirm the primary, which adds a further mode to test and defend.

## Consequences

- An API-server outage is a full write outage, documented as a known limitation.
- A future Kubernetes release could remove Endpoints, so upgrades must recheck this decision.
- A multi-server control plane would be the production fix.

## R-IDs covered

R1.2, R1.3, R2.1, R3.1, R3.2, R3.3, R3.4, R3.5, R6.3, R6.4, R9.1
