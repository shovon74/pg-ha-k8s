# ADR-001: Cluster topology

**Status:** Accepted, amended in L3 (2026-11-25): cluster DNS runs on the server node

## Context

D6 defines node failure as stopping a k3d agent, so every Postgres pod must run on an agent. Backups and monitoring should survive that failure. The host has 4 vCPU and 16 GB (D7).

## Options considered

- **1 server + 3 agents:** smallest layout where every Postgres node can be failed.
- **3 servers + 3 agents:** removes the API single point of failure, but runs six node containers and adds etcd load.
- **1 server + 2 agents:** smallest footprint, but one Postgres pod would sit on the server and could not be failed under D6.

## Decision

Use **1 tainted server + 3 agents**. Postgres pods use required node affinity on `pg-ha/role=db`, required pod anti-affinity on hostname, and a topology spread constraint with `maxSkew: 1` and `DoNotSchedule`. Infrastructure workloads tolerate the taint and run on the server.

**Amendment (L3): cluster DNS on the server.** k3s runs a single CoreDNS replica and schedules it on any node. In L3 it sat on the primary's node. A node failure took DNS down with the primary, and the promoted standby waited inside `restore_command` because it could not resolve Garage. Node-failure RTO rose to 36.95 s. Clients could not have resolved `pg-rw` either. `scripts/deploy.sh` now pins CoreDNS to `pg-ha/role=infra` with a nodeSelector patch. k3s keeps the added key when it re-applies its addon manifest, which held through a k3s server restart. Node-failure RTO returned to about 25 s. Evidence is in `docs/evidence/L3-backup-history.md`.

## Consequences

- Any Postgres node can be stopped while object storage and monitoring keep running.
- The API server is a single point of failure, documented in ADR-002 and known limitations.
- Cluster DNS now shares the server node, and therefore that single point of failure. No database-node failure can take DNS down any more, but a server-node outage takes out the API server and DNS together. Name resolution then fails for clients and for `archive-get`. Patroni keeps the current primary running in that case. See known limitations.
- The L2 harness records CoreDNS placement in every run and fails a run if CoreDNS was on the faulted node.
- All nodes share one VM, kernel and disk, so this simulates node failure rather than proving zone independence.

## R-IDs covered

R1.2, R3.2, R7.4, R7.5, R7.6
