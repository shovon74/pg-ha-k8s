# ADR-008: Old primary rejoin

**Status:** Accepted

## Context

After failover, the old primary must return as a replica of the new primary with no human step.

## Options considered

- **`pg_rewind` with re-clone fallback:** fast normally, and recovers when rewind fails.
- **Always re-clone:** simple, but slower and heavier on the shared disk.
- **`pg_rewind` only:** no automatic deletion, but a member can get stuck.

## Decision

Set `use_pg_rewind: true` and `remove_data_directory_on_rewind_failure: true`. Initialise with data checksums, keep `wal_log_hints=on`, and use a dedicated rewind role.

## Consequences

- The fallback deletes that member's diverged data directory, which is safe only because the current primary remains the source of truth.
- `restore_command` lets rewind fetch older WAL from the archive.
- Checksums also detect page corruption, at a small write cost.

## R-IDs covered

R3.6
