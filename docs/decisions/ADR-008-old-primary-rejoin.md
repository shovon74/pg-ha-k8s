# ADR-008: Old primary rejoin

**Status:** Accepted, revised in L3 (2026-11-25): rejoin by re-clone instead of `pg_rewind`

## Context

After failover, the old primary must return as a replica of the new primary with no human step.

The first decision (below, superseded) used `pg_rewind` with a re-clone fallback. In L3, with WAL archiving on, it caused a permanent archiving stall:

- A member that had rejoined with `pg_rewind` later became primary again. Its `pg_wal` still held segments from older timelines (`0000001E…2B` and `00000021…33` on timeline 36).
- Those copies differed from the copies the primaries of those timelines had already archived. pgBackRest therefore refused them with `[045] WAL file ... already exists in the repo1 archive with a different checksum`.
- Postgres retries the oldest `.ready` segment forever, so every current segment queued behind it was not archived either. Point-in-time recovery lost coverage from that moment, and backups after that failover could not be restored past it.
- The likely mechanism, inferred from documented Postgres behaviour and not traced: `pg_rewind` copies WAL files from the source without archive status. Segments closed early by `archive_timeout` hold leftover bytes after the switch record, and those bytes differ between servers. After a promotion, the checkpoint marks status-less files `.ready`, and the archiver pushes them.
- Evidence is in `docs/evidence/L3-backup-history.md`. The chained scenario `make failover-chain` reproduces the sequence: a node failover, then a switchover back to the old primary.

## Options considered

- **`pg_rewind` with re-clone fallback** (the first decision): fast normally, and recovers when rewind fails. It leaves stale old-timeline WAL that blocks archiving after a later promotion.
- **Always re-clone a diverged member:** `pg_basebackup` writes a fresh data directory and marks the WAL it streams as already archived, so no stale segment survives. It is slower and does more I/O.
- **`pg_rewind` only:** no automatic deletion, but a member can get stuck, and it has the same stale-WAL problem.
- **Keep `pg_rewind` and wrap `archive_command`:** on error 045 for a segment from an older timeline whose copy is already in the repository, log it and return success. **Rejected.** It hides a whole error class in the backup path. A real checksum conflict, such as two primaries writing the same timeline, would be silenced exactly where it must be loud.
- **Keep `pg_rewind` and clean up archive status after each rewind:** mark old-timeline segments `.done` before Postgres starts. This needs a hook that Patroni does not provide, plus custom code in the rejoin path.

## Decision

Set `use_pg_rewind: false` and `remove_data_directory_on_diverged_timelines: true`. Patroni checks each rejoining member against the leader's timeline history. If the member has diverged, Patroni deletes its data directory and re-clones it with `pg_basebackup`. A member that has not diverged, for example after a clean switchover, rejoins with a restart only.

Keep data checksums, `wal_log_hints=on` and the dedicated rewind role. Patroni's divergence check connects as the rewind role, and the settings keep `pg_rewind` available if this decision is reversed.

## Consequences

- Rejoin after an unclean failover is slower, because it copies the whole data directory. At about 180 MB this takes seconds, and it is not on the RTO path: writes resume on the new primary before the old one rejoins. The rejoin time is measured in the L2 evidence.
- Archiving after any sequence of failovers and switchovers no longer depends on what a rejoined member left in `pg_wal`. The L2 harness checks archive health after every run.
- The re-clone deletes the diverged member's data directory. That is safe only because the current primary remains the source of truth, as before.
- **For multi-TB databases** a full re-clone per failover is too slow and too much I/O. There, keep `pg_rewind` and add a post-rewind step that marks old-timeline segments as archived. Never suppress error 045.
- Checksums also detect page corruption, at a small write cost.

## R-IDs covered

R3.6, R4.6
