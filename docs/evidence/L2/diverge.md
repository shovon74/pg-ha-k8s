# L2 failure mode: diverge

**Result: PASS**

- **Fault:** Diverge failover (replication from the primary blocked for a few seconds while it commits, then its node stopped), so the old primary holds WAL no replica received and must rejoin by re-clone (ADR-008). Then a planned switchover back to it, through the sync standby if needed. This is the original trigger of the L3 archiving stall. Archive health is checked on the returned primary.
- **Run:** 2026-11-26T16:42:51Z (UTC), 266 s
- **Reproduce:** `make failover-diverge`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Summary

| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| diverge | pg-1 | pg-0 | 29.48 | 29.70 | 157 | 0 | 1 | re-clone | 55.73 | k3d-pg-ha-server-0 | 0 | 2.17 | PASS |
| switchover 1 | pg-0 | pg-2 | 2.58 | 2.65 | 94 | 0 | 1 | restart only | 7.97 | k3d-pg-ha-server-0 | 0 | 2.23 | PASS |
| switchover 2 | pg-2 | pg-1 | 2.52 | 2.63 | 94 | 0 | 1 | restart only | 7.87 | k3d-pg-ha-server-0 | 0 | 2.24 | PASS |

Second interval on `pg-1`: archived 1.52 s after a WAL fill, failed_count +0, pending .ready `-`.

## Checks

| Check | Result |
|---|---|
| diverge failover run passed (RTO within target, RPO 0 for acknowledged commits, one primary, rejoined, archive healthy) | PASS |
| pg-1 had diverged and rejoined by RE-CLONE (Patroni log), not restart or pg_rewind | PASS |
| Every switchover hop passed (RTO, RPO 0, one primary, archive health right after it), 2 hop(s) | PASS |
| pg-1 is the primary again, on timeline 36 | PASS |
| No new archive failures on pg-1 | PASS |
| A segment was archived within 90 s of a WAL fill | PASS |
| No pending .ready segment from an older timeline (stale WAL from a rejoin) | PASS |

## Step 1: diverge failover

Before: leader `pg-1`, timeline 33. Evidence: [`diverge-diverge.md`](diverge-diverge.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.uZgDvdLI6P/1.log
run 1: RTO=29.48 s gap=29.70 s acked=157 missing=0 maxprimaries=1 rejoin=re-clone coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.17s PASS
RESULT L2 diverge: PASS (min 29.48 s, median 29.48 s, max 29.48 s over 1 runs) -> docs/evidence/L2/diverge-diverge.md
```

Old primary's Patroni and Postgres log after the restart (from diverge-diverge.md):

```console
$ grep -E 'diverged|Removing data|basebackup|requested timeline|not a child|reinitializ|rewind' '/home/shibshankarbose71/pg-ha-k8s/docs/evidence/L2/diverge-diverge.md' | grep -v '^\$' | head -10
- **Fault:** Replication traffic from the primary pod to both replicas is dropped by iptables on its node for 5 s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).
2026-11-26 16:43:52,872 INFO: reinitializing due to diverged timelines
2026-11-26 16:43:53,740 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:53,932 INFO: Removing data directory: /data/pgdata
2026-11-26 16:43:56,856 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:56,860 INFO: reinitializing due to diverged timelines in progress
2026-11-26 16:43:58,392 INFO: replica has been created using basebackup
2026-11-26 16:43:59,791 INFO: reinitializing due to diverged timelines in progress
```

After step 1: leader `pg-0`, timeline 34. `pg-1` rejoined by: re-clone.

## Step 2: switchover back to the old primary

Hop 1: leader `pg-0`, sync standby `pg-2`, switchover to `pg-2`. Evidence: [`diverge-switchover-1.md`](diverge-switchover-1.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.uZgDvdLI6P/2.log
run 1: RTO=2.58 s gap=2.65 s acked=94 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.23s PASS
RESULT L2 switchover: PASS (min 2.58 s, median 2.58 s, max 2.58 s over 1 runs) -> docs/evidence/L2/diverge-switchover-1.md
```

Hop 2: leader `pg-2`, sync standby `pg-1`, switchover to `pg-1`. Evidence: [`diverge-switchover-2.md`](diverge-switchover-2.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.uZgDvdLI6P/2.log
run 1: RTO=2.52 s gap=2.63 s acked=94 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.24s PASS
RESULT L2 switchover: PASS (min 2.52 s, median 2.52 s, max 2.52 s over 1 runs) -> docs/evidence/L2/diverge-switchover-2.md
```

## Archive health on the returned primary, second interval

Primary `pg-1`. Before: failed_count 0, last archived 0000002400000000000000E4. After a WAL fill: archived in 1.52 s, failed_count +0, last archived `0000002400000000000000E5`, pending .ready: -.

```console
$ q pg-1.pg-headless.pg-ha.svc.cluster.local monitor 'select failed_count, last_failed_wal, last_failed_time, archived_count, last_archived_wal, last_archived_time from pg_stat_archiver'
0   4 0000002400000000000000E5 2026-11-26 16:47:16.153582+00
```
