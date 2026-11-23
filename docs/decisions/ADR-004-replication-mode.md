# ADR-004: Replication mode

**Status:** Accepted

## Context

The brief requires a justified choice between synchronous and asynchronous replication, with the implied RPO stated.

## Options considered

- **Asynchronous:** best availability, but failover can lose acknowledged commits.
- **`synchronous_mode: true`:** one sync standby, falling back when no standby is available.
- **`synchronous_mode_strict`:** never commits without a standby, so losing both replicas stops writes.
- **`synchronous_mode: quorum`:** any 1 of 2 standbys, with more behaviour to explain.

## Decision

Use **non-strict `synchronous_mode: true` with one synchronous standby**.

## Stated RPO

- **RPO is 0 for any single failure.**
- With non-strict `synchronous_mode`, a **double replica failure falls back to asynchronous operation**. Writes continue without replica protection, choosing availability over durability.
- If the primary and its synchronous standby fail **at the same time**, the remaining replica may be promoted without the latest commits.

## Consequences

- One lost replica does not stop writes.
- A backend cancelled while waiting for sync confirmation can expose a transaction that was not replicated.
- A client can opt out with `SET synchronous_commit = local`, so the RPO applies to the default commit setting.
- `T:rpo` tests the claim against acknowledged commits.

## R-IDs covered

R1.3, R1.4, R3.4, R9.1, R9.5, R9.7
