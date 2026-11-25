# L3 backup: history and notes

This file is maintained by hand. The L3 tests write only [`L3-backup.md`](L3-backup.md) and the files in [`L3/`](L3/), and never touch this file. Times are UTC, on 2026-11-25.

## Build order and what failed on the way

1. **Garage bootstrap, first attempt (07:02).** The existence check for the bucket used a pipeline in `sh`, whose exit status is the last command's (`sed`), so a 404 from `GetBucketInfo` read as "bucket exists". `AllowBucketKey` then got a malformed bucket ID and returned HTTP 400, retried 20 times. Fixed by capturing the response before parsing, and by making existence checks single tries without `--retry-all-errors`. The rerun created the bucket, and a second rerun kept layout, key and bucket.
2. **Stanza creation, first attempt (07:14).** The pgBackRest TLS server sidecar loaded `repo.conf` through `conf.d`, which sets `repo1-cipher-type`, but the sidecar has no passphrase, so every remote refused with `OptionRequiredError: repo1-cipher-pass`. The sidecar never reads the repository, so it now mounts only `db.conf`. The postgres container and the Jobs still read `repo.conf`.
3. **Short backup schedule, first attempt (07:17).** Kustomize prints the schedule placeholder unquoted, and `*/10 * * * *` is not valid YAML unquoted (a leading `*` is an alias). The default `0 20 * * *` had worked by luck. `scripts/deploy.sh` now substitutes a single-quoted value.

The archiving config was deployed at 07:14 to 07:15, before any measurement, as L2 advised. The rollout restarted every pod and moved the leader from `pg-1` to `pg-2`, timeline 25 to 28.

## Archive failures before the stanza existed

`pg_stat_archiver` showed 6 failures at 07:15, all before the stanza was created at 07:15:38. Postgres started archiving as soon as the new config took effect, while the stanza Job runs only after the rollout. Each segment is retried until it succeeds, so nothing was lost: the first backup's info showed the archive starting at `000000010000000000000004`. On a fresh `make up` the same window exists. The archive test therefore requires no failure during the test and a last failure older than the last successful archive, rather than a zero lifetime counter.

## Node-failure RTO regression: cluster DNS on the primary's node

The first R4.6 run (07:35) measured a node-failure RTO of **36.95 s**, against 21.9 to 23.4 s in L2 and the 30 s target. The L2 harness does not fail a run over 30 s, so it still printed PASS.

- **What the logs showed:** Patroni on the new leader acquired the lock and asked Postgres to promote at 07:35:40.4, but Postgres logged `received promote request` only at 07:35:55.2. After its WAL stream broke at 07:35:19.7, the standby logged no reconnect attempts for 35 s, so its startup process was stuck inside `restore_command`. It checks for a promote request only between WAL retrieval attempts.
- **First fix, partial (07:40):** `archive-get` made synchronous (`--no-archive-async`). RTO 31.07 s, promote noticed 9.3 s late.
- **Cause:** the cluster's only CoreDNS replica ran on `k3d-pg-ha-agent-0`, the node that was stopped because it hosted the primary. `archive-get` could not resolve `garage.pg-ha.svc.cluster.local` until CoreDNS came back. CoreDNS was Ready again at 07:41:09, after the harness restarted the node, and Postgres noticed the promote at 07:41:11.6. In a real node loss the node stays down, CoreDNS returns only after eviction (300 s by default), and clients cannot resolve `pg-rw` meanwhile either. L2's node runs were most likely unaffected because CoreDNS was on another node at the time. Its placement was not recorded then.
- **Fix (07:45):** `scripts/deploy.sh` pins CoreDNS to the server node (`pg-ha/role=infra`), as ADR-001 does for other infrastructure. The pin survived the k3s server restart in the API-outage run at 07:53. Rerun: **RTO 25.11 s**, promote noticed 40 ms after the lock was taken.
- **Remaining cost:** promotion to "ready to accept connections" took about 2 s, against well under 1 s in L2, while Postgres fetched timeline history files through `restore_command`. Node-failure RTO with archiving is therefore about 2 to 3 s higher than L2's numbers, and still TTL-bound.
- The synchronous `archive-get` is kept: each `restore_command` call should return as soon as the repository answers.

## Garage restart: about 60 s to recover

Archiving resumed on its own 59.87 s after the new Garage pod was Ready, with one counted failure and a backlog of at most 8 segments. Writes were unaffected. The 60 s matches pgBackRest's default `io-timeout`, so the likely mechanism is an in-flight upload to the old pod hanging until that timeout, then a retry against the new pod. This mechanism is inferred, not traced. The S1 startup stall (about 135 s) did not occur.

## Archiving stalled on the new primary after the API-outage run (resolved by rebuild and ADR-008 change)

After the optional API-outage rerun (07:53 to 07:56), `pg-0` became leader. At 07:59 its `pg_stat_archiver` showed 27 failures and no successful archive since 07:55:03, and the log showed:

```console
2026-11-25 07:59:11.506 P00  ERROR: [045]: raised from local-1 protocol: WAL file '0000001E000000000000002B' already exists in the repo1 archive with a different checksum
2026-11-25 07:59:11.508 UTC [538] LOG:  archive command failed with exit code 45
```

Pending `.ready` files at 08:02:

```console
pg-0 (leader):  0000001E000000000000002B 000000210000000000000033 00000024000000000000004A 00000024000000000000004B 00000024000000000000004C 00000024000000000000004D
pg-1 (replica): 000000230000000000000049
pg-2 (sync):    (none)
```

- `pg-0` holds segments from old timelines 30 (`0x1E`) and 33 (`0x21`) whose content differs from the copies already archived by the primary of that timeline. They most likely come from `pg_rewind`, which copies WAL files from the source, or from an earlier demotion of `pg-0`. Postgres retries the oldest `.ready` segment forever, so the four current-timeline segments behind it are not archived either. The PITR gap grows until this is cleared.
- The single-failover R4.6 test passed because that run's new primary had no such segment. R4.6 is therefore **not proven** for a sequence of failovers.
- No `exec` was used to inspect or clear it.

**Decision and remediation (lead, 12:52).**

- Rejoin by re-clone instead of `pg_rewind` (ADR-008 revised). Wrapping `archive_command` to accept error 045 was rejected because it hides an error class in the backup path.
- The cluster was rebuilt with `make down && make up` (12:57 to 13:01; secrets kept, repository and test data discarded). The dataset was seeded again, and a fresh full backup passed verify at 13:02.
- The failover harness now checks archive health after every run, and `make failover-chain` repeats the failover-then-switchover-back sequence. Results are in [`L2-failover-history.md`](L2-failover-history.md).
- **R4.6 rerun (13:36 to 13:39), PASS:** node failover with an RTO of 23.09 s, archiving on the new timeline with no failures, `pgbackrest check`, then a backup with verify status ok, started on the new timeline.
- **Limit:** no failover in the rerun diverged, so the re-clone path itself was not exercised, and the exact rewind-then-promote trigger of the stall has not been reproduced. R4.6 is met for every sequence run (13 failovers and switchovers plus the chain), but a forced divergence test is still open.
