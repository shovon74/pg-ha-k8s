# ADR-005: Replication slots and disk protection

**Status:** Accepted

## Context

Replicas must not fall permanently behind, and slots must not fill the disk. local-path volumes do not enforce PVC size, and all nodes share one host disk.

## Options considered

- **Patroni member slots + WAL cap + alerts:** automatic across failover, with a hard bound.
- **Permanent named slots:** useful for external consumers, which we do not have.
- **No slots, `wal_keep_size` only:** simplest, but replicas can fall behind permanently.

## Decision

Use `use_slots: true`, with `max_wal_size=512MB`, `max_slot_wal_keep_size=1GB`, 5 GiB PVCs and `archive-push-queue-max=2GiB`. Alert on low safe WAL size and on lost slots.

## Consequences

- WAL held for slots has a hard limit, independent of PVC enforcement.
- A replica past the cap must recover through `restore_command`. `T:slot-bound` proves this.
- During a long object-storage outage, the archive queue limit drops WAL rather than filling the disk. That creates a PITR gap, which must alert.

## R-IDs covered

R1.5, R1.6, R1.7, R9.6
