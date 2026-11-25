# L4 restore: history and notes

This file is maintained by hand. The L4 tests write only [`L4-restore.md`](L4-restore.md) and the files in [`L4/`](L4/), and never touch this file. Times are UTC, on 2026-11-25. L4 started at 15:21.

## Before L4: the two L2/L3 gaps

- **Step 0a (15:21 to 15:25):** the third, authorised run of `make failover-chain` passed and wrote `L2/chain.md`.
- **Step 0b (15:28 to 15:32):** `make failover-diverge` forced a divergence on the first attempt. The old primary rejoined by re-clone, was switched back to leader, and archived with no failures. Details are in [`L2-failover-history.md`](L2-failover-history.md).

## Design points settled during implementation

- **`post_bootstrap` runs after a custom bootstrap too.** Patroni 4.1.5 calls it after a restore, so `CREATE ROLE` would have failed on the restored roles. `post-bootstrap.sh` is now create-or-alter, which also resets the restored passwords to the target namespace's Secret (ADR-010).
- **Recovery settings stay out of `postgresql.auto.conf`.** pgBackRest writes `restore_command` and the recovery target there. Replicas cloned from the restored primary would copy those lines, and they would outlive the end of recovery. `restore-bootstrap.sh` removes them after the restore, and Patroni's `recovery_conf` drives recovery instead.
- **The restored cluster cannot archive into the source stanza.** `30-restore.yml` sets `archive_mode: "off"`. The full-restore test checks that the setting is off, that the restored primary's archiver counters are zero, and that the source archive has no WAL directory for the restored timeline.
- **Data check for the restore test.** The backup Job records a fingerprint as pgBackRest annotations: row counts and `hashtext` sums of the seeded pgbench tables, read as `app_ro` through `pg-rw` just before the backup. The restore test compares it after a `--type=immediate` restore. The tables only change on `make seed`, so a backup taken while the probe writes elsewhere still matches.
  - **Limit:** this fingerprints test data. A production deployment would choose its own marker tables.
  - On a cluster that was never seeded, the fingerprint is `seeded=no`, which the restore test still compares.

## What failed on the way

1. **Full restore, first attempt (15:33).** A test bug: the test library exports `NS=pg-ha`, and `scripts/restore.sh` reads `NS`, so it correctly refused to restore into the source namespace. Nothing was created or deleted, and `restore-clean` also refused `pg-ha`. The tests now pass `NS=pg-restore` explicitly. The second attempt passed.
2. **Restore test, first attempt (15:42).** `FATAL: recovery aborted because of insufficient parameter settings`. The scratch config set `max_connections = 20`, and recovery requires at least the primary's value (100). The Job failed loudly, as designed. `max_connections` is back at its default, and the second attempt passed. The rest of that sequence (the negative run and the scheduled capture) was stopped, so their attempts were not spent on a known failure.
3. **A blocked command.** A safety check blocked one shell command that created several files through heredocs, because the embedded scripts contained `rm -f`. Nothing in it ran. The two test scripts were then written with the editor instead.

## PITR: B was first committed too early

The first PITR run passed, but marker B was committed 18.5 s after T, once A's segment had been archived, not after `archive_timeout` as the brief says. The proof itself held: Postgres logged `recovery stopping before commit of transaction 4595`, which is B's commit. The test now waits at least 65 s after T before committing B. The rerun (15:44 to 15:46) passed: B was committed 66.0 s after T, Postgres logged `recovery stopping before commit of transaction 4608` (B), and the restore took 27.99 s end to end. The rerun replaced the first run's evidence file. Both runs' log lines are quoted here.

## PITR across timelines (R5.5, observed)

pgBackRest picks the newest backup that ends before the target. In the first PITR run (target `2026-11-25 21:39:28+06`), that was `20261125-133844F`, taken before the L2 rerun's failovers. Recovery to a target on timeline 27 therefore replayed across every timeline switch in between, using the history files in the archive, and stopped at the right transaction (`recovery stopping before commit of transaction 4595`). The rerun used the newer `20261125-154309F` on the same timeline, so its evidence file does not show this crossing. R5.5 ("a target time after a failover restores correctly") is shown by that run. There is no dedicated `T:pitr-timeline` test.

**Count of switches (added in L5).** The backup `20261125-133844F` started on timeline 16 (`00000010`, see [`L3/failover.md`](L3/failover.md): "The backup started on the new timeline (00000010)"). The target was on timeline 27 (`0000001B`). That run therefore replayed across **11 timeline switches** (16 → 27). The relevant log lines from the first run, taken from the agent session log (times UTC, from `kubectl -n pg-restore logs pg-2 -c postgres`):

```
2026-11-25 15:39:59.531 P00   INFO: repo1: restore backup set 20261125-133844F, recovery will start at 2026-11-25 13:38:44
2026-11-25 15:40:06.541 UTC [39] LOG:  starting point-in-time recovery to 2026-11-25 15:39:28+00
2026-11-25 15:40:15.666 UTC [39] LOG:  recovery stopping before commit of transaction 4595, time 2026-11-25 15:39:46.51932+00
```

The per-switch `restored log file "000000NN.history"` lines were filtered out by that run's `grep`, so they were not kept. The count comes from the backup's start timeline and the source's timeline, not from those lines.
