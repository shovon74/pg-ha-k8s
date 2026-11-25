# L2 failure mode: diverge

**Result: PASS**

- **Fault:** Diverge failover (replication from the primary blocked for a few seconds while it commits, then its node stopped), so the old primary holds WAL no replica received and must rejoin by re-clone (ADR-008). Then a planned switchover back to it, through the sync standby if needed. This is the original trigger of the L3 archiving stall. Archive health is checked on the returned primary.
- **Run:** 2026-11-25T15:28:13Z (UTC), 261 s
- **Reproduce:** `make failover-diverge`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Summary

| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| diverge | pg-2 | pg-1 | 26.85 | 27.00 | 163 | 0 | 1 | re-clone | 54.10 | k3d-pg-ha-server-0 | 0 | 2.29 | PASS |
| switchover 1 | pg-1 | pg-0 | 2.54 | 2.55 | 93 | 0 | 1 | restart only | 7.99 | k3d-pg-ha-server-0 | 0 | 1.64 | PASS |
| switchover 2 | pg-0 | pg-2 | 2.51 | 2.58 | 93 | 0 | 1 | restart only | 7.86 | k3d-pg-ha-server-0 | 0 | 2.21 | PASS |

Second interval on `pg-2`: archived 1.52 s after a WAL fill, failed_count +0, pending .ready `-`.

## Checks

| Check | Result |
|---|---|
| diverge failover run passed (RTO within target, RPO 0 for acknowledged commits, one primary, rejoined, archive healthy) | PASS |
| pg-2 had diverged and rejoined by RE-CLONE (Patroni log), not restart or pg_rewind | PASS |
| Every switchover hop passed (RTO, RPO 0, one primary, archive health right after it), 2 hop(s) | PASS |
| pg-2 is the primary again, on timeline 27 | PASS |
| No new archive failures on pg-2 | PASS |
| A segment was archived within 90 s of a WAL fill | PASS |
| No pending .ready segment from an older timeline (stale WAL from a rejoin) | PASS |

## Step 1: diverge failover

Before: leader `pg-2`, timeline 24. Evidence: [`diverge-diverge.md`](diverge-diverge.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.BgHPT7yzI5/1.log
run 1: RTO=26.85 s gap=27.00 s acked=163 missing=0 maxprimaries=1 rejoin=re-clone coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.29s PASS
RESULT L2 diverge: PASS (min 26.85 s, median 26.85 s, max 26.85 s over 1 runs) -> docs/evidence/L2/diverge-diverge.md
```

Old primary's Patroni and Postgres log after the restart (from diverge-diverge.md):

```console
$ grep -E 'diverged|Removing data|basebackup|requested timeline|not a child|reinitializ|rewind' '/home/shibshankarbose71/pg-ha-k8s/docs/evidence/L2/diverge-diverge.md' | grep -v '^\$' | head -10
- **Fault:** Replication traffic from the primary pod to both replicas is dropped by iptables on its node for 5 s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).
2026-11-25 15:29:12,524 INFO: reinitializing due to diverged timelines
2026-11-25 15:29:12,960 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:13,548 INFO: Removing data directory: /data/pgdata
2026-11-25 15:29:16,121 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:16,122 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:18,886 INFO: reinitializing due to diverged timelines in progress
2026-11-25 15:29:19,454 INFO: replica has been created using basebackup
```

After step 1: leader `pg-1`, timeline 25. `pg-2` rejoined by: re-clone.

## Step 2: switchover back to the old primary

Hop 1: leader `pg-1`, sync standby `pg-0`, switchover to `pg-0`. Evidence: [`diverge-switchover-1.md`](diverge-switchover-1.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.BgHPT7yzI5/2.log
run 1: RTO=2.54 s gap=2.55 s acked=93 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=1.64s PASS
RESULT L2 switchover: PASS (min 2.54 s, median 2.54 s, max 2.54 s over 1 runs) -> docs/evidence/L2/diverge-switchover-1.md
```

Hop 2: leader `pg-0`, sync standby `pg-2`, switchover to `pg-2`. Evidence: [`diverge-switchover-2.md`](diverge-switchover-2.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.BgHPT7yzI5/2.log
run 1: RTO=2.51 s gap=2.58 s acked=93 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.21s PASS
RESULT L2 switchover: PASS (min 2.51 s, median 2.51 s, max 2.51 s over 1 runs) -> docs/evidence/L2/diverge-switchover-2.md
```

## Archive health on the returned primary, second interval

Primary `pg-2`. Before: failed_count 0, last archived 0000001B0000000000000058. After a WAL fill: archived in 1.52 s, failed_count +0, last archived `0000001B0000000000000059`, pending .ready: -.

```console
$ q pg-2.pg-headless.pg-ha.svc.cluster.local monitor 'select failed_count, last_failed_wal, last_failed_time, archived_count, last_archived_wal, last_archived_time from pg_stat_archiver'
0   4 0000001B0000000000000059 2026-11-25 15:32:32.982752+00
```
