# ADR-006: Split-brain prevention, fencing and timing

**Status:** Accepted

## Context

Two primaries must never accept writes at once. Patroni requires `ttl ≥ 20` and `loop_wait + 2 × retry_timeout ≤ ttl`. A watchdog would reset the shared VM kernel, taking down every k3d node.

The ≤ 30 s RTO is **our own target, not the brief's**.

## Options considered

- **Timing:** defaults 30/10/10, tuned 20/3/5, or 20/5/5.
- **Fencing:** lock-based demotion with synchronous replication, a software watchdog, or custom Kubernetes fencing.

## Decision

- Use `ttl=20`, `loop_wait=3`, `retry_timeout=5` and `primary_start_timeout=0`.
- Fence through lock-based demotion plus synchronous replication, with **no watchdog**.
- **"Accepts writes" means acknowledged commits.** A commit that blocks and never returns success is not an accepted write.
- Measure RTO per failure mode and **report the real numbers**. The 26–28 s worst case is only an estimate.
- **Do not tune timeouts into unsafe territory to hit the target.** If a mode exceeds 30 s with safe settings, record the miss and explain it.

## Consequences

- A frozen Patroni cannot demote itself, but sync replication should stop its commits being acknowledged. `T:split-brain` must prove this.
- Tight timing can cause unnecessary failovers if the API is slow.
- A production deployment on real nodes should add a hardware or software watchdog.

## R-IDs covered

R3.1, R3.2, R3.3, R3.4, R3.5, R3.7, R7.6, R9.1
