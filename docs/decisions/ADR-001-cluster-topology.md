# ADR-001: Cluster topology

**Status:** Accepted

## Context

D6 defines node failure as stopping a k3d agent, so every Postgres pod must run on an agent. Backups and monitoring should survive that failure. The host has 4 vCPU and 16 GB (D7).

## Options considered

- **1 server + 3 agents:** smallest layout where every Postgres node can be failed.
- **3 servers + 3 agents:** removes the API single point of failure, but runs six node containers and adds etcd load.
- **1 server + 2 agents:** smallest footprint, but one Postgres pod would sit on the server and could not be failed under D6.

## Decision

Use **1 tainted server + 3 agents**. Postgres pods use required node affinity on `pg-ha/role=db`, required pod anti-affinity on hostname, and a topology spread constraint with `maxSkew: 1` and `DoNotSchedule`. Infrastructure workloads tolerate the taint and run on the server.

## Consequences

- Any Postgres node can be stopped while object storage and monitoring keep running.
- The API server is a single point of failure, documented in ADR-002 and known limitations.
- All nodes share one VM, kernel and disk, so this simulates node failure rather than proving zone independence.

## R-IDs covered

R1.2, R3.2, R7.4, R7.5, R7.6
