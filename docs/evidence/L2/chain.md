# L2 failure mode: chain

**Result: PASS**

- **Fault:** Node failover (`docker stop` of the primary's agent), then a planned switchover back to the old primary after it has rejoined. This is the sequence that stalled WAL archiving in L3 when rejoin used `pg_rewind` (ADR-008). Archive health is checked on the returned primary.
- **Run:** 2026-11-25T15:21:49Z (UTC), 269 s
- **Reproduce:** `make failover-chain`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Summary

| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| node | pg-1 | pg-0 | 24.15 | 24.05 | 169 | 0 | 1 | restart only | 43.12 | k3d-pg-ha-server-0 | 0 | 2.37 | PASS |
| switchover 1 | pg-0 | pg-2 | 3.60 | 3.59 | 92 | 0 | 1 | restart only | 9.99 | k3d-pg-ha-server-0 | 0 | 2.19 | PASS |
| switchover 2 | pg-2 | pg-1 | 3.90 | 4.06 | 90 | 0 | 1 | restart only | 9.34 | k3d-pg-ha-server-0 | 0 | 3.77 | PASS |

Second interval on `pg-1`: archived 2.79 s after a WAL fill, failed_count +0, pending .ready `-`.

## Checks

| Check | Result |
|---|---|
| Node failover run passed (RTO within target, RPO 0, one primary, rejoined, archive healthy) | PASS |
| Every switchover hop passed (RTO, RPO 0, one primary, archive health right after it), 2 hop(s) | PASS |
| pg-1 is the primary again, on timeline 22 | PASS |
| No new archive failures on pg-1 | PASS |
| A segment was archived within 90 s of a WAL fill | PASS |
| No pending .ready segment from an older timeline (stale WAL from a rejoin) | PASS |

## Step 1: node failover

Before: leader `pg-1`, timeline 19. Evidence: [`chain-node.md`](chain-node.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.gb5Fxt9wRe/1.log
run 1: RTO=24.15 s gap=24.05 s acked=169 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.37s PASS
RESULT L2 node: PASS (min 24.15 s, median 24.15 s, max 24.15 s over 1 runs) -> docs/evidence/L2/chain-node.md
```

After step 1: leader `pg-0`, timeline 20. `pg-1` rejoined by: restartonly.

## Step 2: switchover back to the old primary

Hop 1: leader `pg-0`, sync standby `pg-2`, switchover to `pg-2`. Evidence: [`chain-switchover-1.md`](chain-switchover-1.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.gb5Fxt9wRe/2.log
run 1: RTO=3.60 s gap=3.59 s acked=92 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=2.19s PASS
RESULT L2 switchover: PASS (min 3.60 s, median 3.60 s, max 3.60 s over 1 runs) -> docs/evidence/L2/chain-switchover-1.md
```

Hop 2: leader `pg-2`, sync standby `pg-1`, switchover to `pg-1`. Evidence: [`chain-switchover-2.md`](chain-switchover-2.md).

```console
$ grep -E '^run 1:|RESULT' /tmp/tmp.gb5Fxt9wRe/2.log
run 1: RTO=3.90 s gap=4.06 s acked=90 missing=0 maxprimaries=1 rejoin=restart only coredns=k3d-pg-ha-server-0 archfail=+0 archived=3.77s PASS
RESULT L2 switchover: PASS (min 3.90 s, median 3.90 s, max 3.90 s over 1 runs) -> docs/evidence/L2/chain-switchover-2.md
```

## Archive health on the returned primary, second interval

Primary `pg-1`. Before: failed_count 0, last archived 00000016000000000000004D. After a WAL fill: archived in 2.79 s, failed_count +0, last archived `00000016000000000000004E`, pending .ready: -.

```console
$ q pg-1.pg-headless.pg-ha.svc.cluster.local monitor 'select failed_count, last_failed_wal, last_failed_time, archived_count, last_archived_wal, last_archived_time from pg_stat_archiver'
0   4 00000016000000000000004E 2026-11-25 15:26:15.755667+00
```
