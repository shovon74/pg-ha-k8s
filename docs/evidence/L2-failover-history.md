# L2 failover: history and notes

This file is maintained by hand. The harness writes only [`L2-failover.md`](L2-failover.md) and the files in [`L2/`](L2/), and never touches this file. Times are UTC, on 2026-11-25.

## Why the whole L2 suite was rerun after L3

The first L2 results (commit `b53d48f`) were measured without WAL archiving, with `pg_rewind` rejoin, and with CoreDNS wherever k3s had placed it. L3 changed all three, so every mode was rerun on the final configuration after a fresh `make down && make up`.

- **CoreDNS placement.** k3s runs one CoreDNS replica. In L3 it sat on the primary's node, so a node failure also took DNS down. The promoted standby then waited in `restore_command` until DNS returned, and node-failure RTO was 36.95 s (L3 history). The first L2 node runs were most likely unaffected only because CoreDNS was on another node at the time, but its placement was not recorded. `make up` now pins CoreDNS to the server node (ADR-001), and every run records where it ran.
- **Rejoin method.** `pg_rewind` left stale old-timeline WAL that stalled archiving after a later promotion. Rejoin is now by re-clone on divergence (ADR-008), so the "Rejoin" column and rejoin times differ from the first results.
- **Archiving on.** Promotion now fetches timeline history through `restore_command`, which adds about 2 s to node-failure RTO.
- **Harness gap.** The first harness reported a run over the 30 s target as PASS. Runs over target are now reported as OVER TARGET, the mode result says so, and the script exits non-zero.
- **New checks.** After every run, the harness checks archive health on the current primary. `failed_count` must not grow, and a segment must be archived within 90 s of a WAL fill. A new chained scenario (`make failover-chain`) repeats the sequence that caused the L3 stall: a node failover, then a switchover back.

## Rerun results (13:02 to 13:44, after `make down && make up` at 12:57)

All five modes passed on the final configuration: re-clone rejoin, CoreDNS pinned to `k3d-pg-ha-server-0` in every run, archiving on. No run was over target, and every run's archive check passed (no new failures, a segment archived 1.8 to 5.4 s after the WAL fill). Node-failure RTO was 23.22 to 26.19 s, against 21.9 to 23.4 s before archiving.

**No run diverged.** Every old primary rejoined by restart only, after crash recovery in the node and storage modes. The re-clone path was therefore not exercised. The earlier `pg_rewind` runs were real divergences (`pg_rewind: servers diverged at WAL location ...` in the L2 node evidence of commit `b53d48f` and in the L3 node run at 07:47), so divergence happens only sometimes. A forced-divergence test remains open.

## Chained scenario: passed in substance, combined evidence file missing

`make failover-chain` failed twice, both times on harness bugs and not on the cluster. Per the working rule it was not run a third time.

1. **13:31.** In synchronous mode Patroni switches over only to the sync standby (`candidate name does not match with sync_standby`), and the old primary was the async replica. The harness also died when a run measured no RTO (`grep` with no match under `pipefail`), and `client_up` accepted a test client still being deleted. All three are fixed: the chain now switches over through the sync standby, at most 3 hops.
2. **13:39.** The steps all passed. The node failover took `pg-1` to `pg-0` with an RTO of 21.90 s, then switchover hops went `pg-0` to `pg-2` (2.61 s) and `pg-2` to `pg-1` (2.56 s). Each had RPO 0, one primary and a healthy archive check. Evidence: [`chain-node.md`](L2/chain-node.md), [`chain-switchover-1.md`](L2/chain-switchover-1.md), [`chain-switchover-2.md`](L2/chain-switchover-2.md). The script then died in its final section on the same `grep` pattern, when no `.ready` file was pending, so `L2/chain.md` was not written. That line is fixed but has not been rerun. The same checks run by hand on `pg-1` at 13:44 showed a segment archived 1.37 s after a WAL fill, no new failures, and no pending `.ready` file.

## Chained scenario, third attempt (L4 step 0a, 15:21 to 15:25): PASS

Authorised by the lead. The run passed on all checks and wrote [`L2/chain.md`](L2/chain.md). Node failover `pg-1` to `pg-0` took 24.15 s, then switchover hops `pg-0` to `pg-2` (3.60 s) and `pg-2` to `pg-1` (3.90 s). Every step had RPO 0 and a healthy archive check. In the second interval on `pg-1`, a segment was archived 2.79 s after the WAL fill with no new failures and no pending `.ready` file. Again no member diverged, so this run exercised the sequence but not the re-clone.

## Forced divergence (L4 step 0b, 15:28 to 15:32): PASS, re-clone proven

`make failover-diverge` reproduces the original trigger on purpose. iptables on the primary's node dropped replication traffic from `pg-2` to both replicas for 5 s while the probe wrote, so `pg-2` wrote commit records that no replica received and that were never acknowledged. Then its node was stopped.

- `pg-1` took over with an RTO of 26.85 s, counted from the start of the block, with RPO 0 for acknowledged commits and never two primaries.
- After its node restarted, `pg-2`'s Patroni logged `reinitializing due to diverged timelines` and `Removing data directory: /data/pgdata` at 15:29:12 to 15:29:13, and `replica has been created using basebackup` at 15:29:19. That is a re-clone, not a restart or `pg_rewind`.
- Two switchover hops (`pg-1` to `pg-0` in 2.54 s, `pg-0` to `pg-2` in 2.51 s) made the re-cloned `pg-2` primary again. That is the exact situation that stalled archiving in L3. Archiving stayed healthy: no new failures, a segment archived 1.52 s after a WAL fill, and no pending `.ready` segment from an older timeline.
- Evidence: [`L2/diverge.md`](L2/diverge.md), with the per-step files `diverge-diverge.md` and `diverge-switchover-{1,2}.md`.

## API outage rerun (L3, 07:53)

The optional rerun of `make test-api-outage` with the fixed report guard passed all six checks. Its evidence is in [`L2/api-outage.md`](L2/api-outage.md). It was not repeated after the rebuild.
