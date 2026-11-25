# L5 history: monitoring and alerting

Hand-written notes for L5. The generated results are in [`L5-monitoring.md`](L5-monitoring.md). Times are UTC (the lead works in UTC+6). Session date 2026-11-25.

## Order of work

| Time (UTC) | Step |
|---|---|
| 16:14 | Start. Read CLAUDE.md, ADR-011, the L4 phase notes and versions.env |
| 16:20 | Step 0: the R5.5 note in `L4-restore-history.md` (11 timeline switches, 16 → 27) |
| 16:22 | postgres_exporter sidecar deployed with `make deploy`. **This rolled the three Postgres pods, before any measurement.** Patroni healthy at 16:23 |
| 16:31 | Monitoring stack deployed (`make monitoring`): 13 of 13 targets up, 19 rules |
| 16:32 | `make test-alerts` PASS on the first run, then three mutations checked by hand (below) |
| 16:35 | First `make test-metrics`: all checks PASS, but the harness killed itself on exit (bug 1 below). Fixed, then rerun at 16:53 |
| 16:38 | Redeployed with kube-state-metrics' telemetry scrape (14 targets) |
| 16:39 | `make alerts-archive` PASS |
| 16:47 | `make alerts-failover` PASS |
| 16:53 | `make test-metrics` rerun with the fixes: PASS, exit 0 |
| 16:57 | Regression check: `make test-restore-full` (L4) PASS. The restore path renders the same StatefulSet, now with the exporter sidecar, and `scripts/restore.sh` gained the image substitution. This regenerated `L4/restore-full.md` and `L4-restore.md`. No alert fired from `pg-restore` |

The monitoring stack was redeployed (Prometheus recreated) at 16:38 and again at 16:52 for small changes: kube-state-metrics' telemetry scrape, and the MemberDown summary text. Neither rolled the Postgres pods.

## Decisions taken during the phase

- **The exporter is a sidecar, not a central multi-target Deployment.** Each member is discovered with its pod and node labels, and the exporter dies with its member, so a stopped node shows as `up == 0` for that member. The cost was one rolling restart of the StatefulSet, done first.
- **The exporter connects over TCP to `127.0.0.1` with `sslmode=require`.** `pg_hba` allows the local socket for `peer` only, and the OS user (999) is not `monitor`. TLS keeps it working after L6 moves to `hostssl`.
- **Three custom exporter queries** (`--extend.query-path`): archive backlog, lag per standby, slot retention. The exporter logs that this flag is deprecated. It still works in v0.20.1. A future upgrade must check it.
- **ArchiveStale uses the oldest `.ready` age, not `last_archived_time`.** Seen live: the standbys report `pg_stat_archiver_last_archive_age` and non-zero `archived_count` from their earlier time as primary. Also, an idle primary closes no segment, so archive age grows with nothing at risk.
- **Two namespaces for monitoring.** Only node_exporter needs `hostPath`, so only `monitoring-host` enforces `privileged`. `monitoring` stays `restricted`.
- **Roles only, no ClusterRole.** Prometheus discovers pods in `pg-ha` and `monitoring-host` only. kube-state-metrics is limited to four resource types in `pg-ha` and `kube-system`.
- **An extra alert, MonitoringTargetDown,** was added beyond the requested list. The staleness alerts (backup, restore test, CoreDNS, disk) depend on kube-state-metrics and node_exporter, and would stay silent if those were down.
- **ReplicationLagHigh is two rules with the same name,** labelled `lag=bytes` and `lag=seconds`, so each has its own threshold and `for`.
- **The node's root filesystem is `overlay`** (a k3d node is a container). node_exporter's default `fs-types-exclude` drops overlay, so the exclude list was overridden. `mountpoint="/"` is then reported, and DiskLow uses it.

## Findings

1. **The CronJob's `lastSuccessfulTime` is not a backup signal.** `kube_cronjob_status_last_successful_time{cronjob="pg-backup"}` was 16:23 UTC, the time of the stanza-create Job. That Job and the check Jobs are made from the `pg-backup` template by `scripts/pgbr-job.sh` (`kubectl create job --from=cronjob/...`), so the CronJob owns them. BackupStale and RestoreTestStale therefore count only Jobs named `pg-backup-*` and `pg-restore-test*`. A unit test covers a fresh stanza Job alongside a stale backup. A side effect, not changed in L5: those owned Jobs also count toward the CronJob's `successfulJobsHistoryLimit: 3`, so many check Jobs in one day can prune the last real backup Job. BackupStale would then fire early, a false alarm rather than a missed one.
2. **A full block cannot show the lag alert.** Blocking the stream ends the walsender after `wal_sender_timeout` (60 s), the `pg_stat_replication` row disappears, and ReplicaNotStreaming fires instead. `tc` is not in the k3s node image. An iptables `limit` match (40 packets/s, the rest dropped) slows the stream but keeps it connected. Lag reached about 218 MB and 120 s, and ReplicationLagHigh fired after its 2-minute `for`.
3. **NoPrimary does not fire in a node failover, by design.** The new primary held the lock 23 s after `docker stop`, inside NoPrimary's 45 s. The old primary showed up as MemberDown (pod `pg-2`). A second, namespace-level MemberDown instance came from the "fewer members up than replicas" branch. Its summary rendered an empty pod name, so it was given its own text.
4. **ArchiveFailing fires 77 s after the block, ArchiveStale 133 s after.** With dropped packets, pgBackRest's archive-push fails only after its io-timeout (about 60 s). ArchiveFailing resolved 424 s after the fault, about 5 minutes after the last failure, as its 5-minute window implies. ArchiveStale resolved 29 s after unblocking.
5. **Prometheus TSDB size.** About 1.2 MB of WAL after roughly 10 minutes, with about 4.5k head series. This has not been measured over a day. The 1 GB retention cap and the 2 Gi emptyDir limit bound it.

## Harness bugs found and fixed (no product impact)

1. `tests/l5-metrics.sh` cleanup ran `kill "${WRITER:-0}"` after `WRITER` had been cleared. `kill 0` signals the whole process group, so make printed `Terminated` (exit 143) after the test had already written PASS evidence. It now kills only a set PID. The run was repeated at 16:53 with exit 0. `tests/l5-alerts-archive.sh` had the same pattern and was fixed before its first real run.
2. `tests/l5-alerts-archive.sh` was created after the `chmod +x`, so the first `make alerts-archive` failed with `Permission denied` before doing anything.

## Mutation check of the unit tests (by hand, not committed)

Each mutation was applied to a scratch copy of the rules and `promtool test rules` was run against it.

| Mutation | Failing assertions |
|---|---:|
| NoPrimary `for: 45s` → `10s` | 1 |
| ArchiveStale `> 120` → `> 300` | 1 |
| BackupFailed/BackupStale without `namespace="pg-ha"` | 1 |

## exec and other disclosures (D4)

- **kubectl exec:** only through the existing `q` helper into the test client pod `pg-test-client`, from the committed L5 tests (WAL fills and archiver status). Never into a Postgres pod.
- **docker exec in committed fault scripts:** `iptables` on the primary's k3d agent in `tests/l5-metrics.sh` (stream throttle) and `tests/l5-alerts-archive.sh` (Garage block). Both are documented in the script headers, and both rules are removed on exit.
- **docker stop / start:** in `tests/l5-alerts-failover.sh`, as in `make failover-node`.
- **Ad hoc, outside committed scripts (read-only):** one `docker exec k3d-pg-ha-agent-0 sh -c 'which tc iptables ip; ...; ip route'`, to find out whether `tc` exists on the node image. Also `docker exec k3d-pg-ha-agent-N iptables -S FORWARD` on all three agents, to confirm that no test rule was left behind after the bug-1 exit. Neither changed anything.
- **Other ad hoc reads:** Prometheus queries through `kubectl get --raw` on the API server's service proxy.
- **Secrets:** no secret value was printed. The exporter reads the monitor password through `secretKeyRef`, and the evidence files pass through the existing `redact` filter.
