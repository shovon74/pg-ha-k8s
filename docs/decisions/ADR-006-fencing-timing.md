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

## Split-brain timing argument

With `loop_wait=3`, `retry_timeout=5` and `ttl=20`:

```text
loop_wait + 2 × retry_timeout = 3 + (2 × 5) = 13 s  <  ttl = 20 s
```

An isolated primary demotes within **13 s** of its last successful lock renewal, before its leader key can expire at **20 s**. No other member can therefore acquire the lock while the old primary may still accept writes.

What this rests on, checked against Patroni `v4.1.5` source:

- **Expiry cannot start early.** Each replica times the TTL from when it last *observed* the leader record change, using its own clock (`dcs/kubernetes.py`). Observation happens at or after the renewal, so the earliest possible expiry is renewal + 20 s, and no clock synchronisation is needed.
- **13 s bounds when demotion is issued, not when Postgres has stopped.** On a failed renewal Patroni calls `demote('immediate-nolock')` (`ha.py`), which stops Postgres in `immediate` mode asynchronously. That stop must finish inside the remaining **7 s margin**. This is an **[Assumption]** until `T:split-brain` measures it.
- **The argument needs a running Patroni.** A frozen Patroni never issues the demotion, so the inequality does not protect that case. Synchronous replication is the backstop: once the standbys follow the new leader, the old primary's commits block and are never acknowledged.

### What `T:split-brain` must show

The fault is `docker network disconnect` on the primary's agent, with a writer running against the old primary throughout. Timestamps are in UTC. The test passes only if all of these hold, in each of its runs:

1. **Demotion before expiry:** the old primary stops acknowledging commits no later than 20 s after its last successful renewal. The report states the measured time against the 13 s bound and the 20 s TTL.
2. **No overlap:** the last commit acknowledged by the old primary is earlier than the new primary's first acknowledged commit.
3. **One lock holder:** the leader key names exactly one member at every sample, and the new leader acquires it only after the old key expired.
4. **No lost acknowledged writes:** every commit acknowledged to the client is present on the new primary after failover (RPO 0).
5. **Frozen-Patroni case:** with Patroni stopped by `SIGSTOP` on the primary and Postgres still running, commits on the old primary block and none is acknowledged after the standbys leave it.

## Consequences

- A frozen Patroni cannot demote itself, but sync replication should stop its commits being acknowledged. `T:split-brain` must prove this.
- Tight timing can cause unnecessary failovers if the API is slow.
- A production deployment on real nodes should add a hardware or software watchdog.

## R-IDs covered

R3.1, R3.2, R3.3, R3.4, R3.5, R3.7, R7.6, R9.1
