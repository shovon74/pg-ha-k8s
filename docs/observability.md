# Observability (L5)

Monitoring and alerting for the `pg-ha` cluster, built from our own manifests, with no operators or charts (ADR-011, D1, D2). Covers R1.6, R1.7, R10.1, R10.2, R10.3 and R10.5. Evidence: [`evidence/L5-monitoring.md`](evidence/L5-monitoring.md).

## What runs where

| Component | Where | Image (versions.env) | Purpose |
|---|---|---|---|
| Prometheus | `monitoring`, server node | `PROMETHEUS_IMAGE` | Scrapes every 10 s, evaluates rules every 10 s, keeps 3 days (max 1 GB) in an emptyDir |
| Alertmanager | `monitoring`, server node | `ALERTMANAGER_IMAGE` | Groups alerts. Uses a no-op receiver, so nothing is sent and no secret exists |
| kube-state-metrics | `monitoring`, server node | `KUBE_STATE_METRICS_IMAGE` | Job, CronJob, StatefulSet and Deployment state in `pg-ha` and `kube-system` only |
| node_exporter | `monitoring-host`, every node (DaemonSet) | `NODE_EXPORTER_IMAGE` | Root filesystem space, memory, load |
| postgres_exporter | sidecar `exporter` in each `pg-N` pod | `POSTGRES_EXPORTER_IMAGE` | Built-in Postgres metrics plus three custom queries ([`deploy/pg/exporter/queries.yaml`](../deploy/pg/exporter/queries.yaml)) |
| Patroni `/metrics` | each `pg-N` pod, port 8008 | (our image) | Role, timeline, streaming state, sync standby |

Deployed by `make monitoring`, which is part of `make up`. The exporter sidecar is part of the StatefulSet (`make deploy`). Manifests are in [`deploy/monitoring/`](../deploy/monitoring/).

**RBAC (least privilege, Roles only, no ClusterRole):**
- Prometheus can get, list and watch pods in `pg-ha` and `monitoring-host`, for service discovery. Every other target is static.
- kube-state-metrics can list and watch Jobs, CronJobs, StatefulSets and Deployments in `pg-ha` and `kube-system`. kube-state-metrics watches each listed resource in each listed namespace, so the two Roles are identical.
- Alertmanager and node_exporter have no API token mounted.

**Pod Security.** `monitoring` enforces `restricted`. node_exporter needs a read-only `hostPath` mount of the node's root for disk space, which `baseline` and `restricted` both forbid. It therefore runs alone in `monitoring-host`, which enforces `privileged` and warns and audits at `restricted`. This is a documented exception for R8.7. The pod still runs as non-root (65534) with no capabilities, no privilege escalation, a read-only root filesystem, and no hostNetwork or hostPID.

## What is scraped

| Job | Targets | Discovery | Key series |
|---|---|---|---|
| `patroni` | 3 members, `:8008/metrics` | pods in `pg-ha` with `app.kubernetes.io/name=pg` | `patroni_primary`, `patroni_postgres_running`, `patroni_postgres_streaming`, `patroni_sync_standby`, `patroni_postgres_timeline`, `patroni_xlog_*` |
| `postgres` | 3 members, `:9187` | same pods, port `metrics` | `pg_up`, `pg_replication_is_replica`, `pg_stat_archiver_*`, `pg_ha_archive_*`, `pg_ha_replication_*`, `pg_ha_slot_*` |
| `node` | every node, `:9100` | pods in `monitoring-host` | `node_filesystem_avail_bytes`, `node_filesystem_size_bytes`, `node_memory_*` |
| `kube-state-metrics` | 1 | static Service | `kube_job_*`, `kube_cronjob_created`, `kube_statefulset_replicas`, `kube_deployment_status_replicas_available` |
| `kube-state-metrics-self`, `alertmanager`, `prometheus` | 1 each | static | `up`, process metrics (memory of the monitoring components) |

Every target gets `namespace`, `pod` and `node` labels from discovery. Only `pg-ha` is discovered, so a restored cluster in `pg-restore` is never scraped. Every Postgres, backup and restore rule also selects `namespace="pg-ha"`, which `make test-alerts` checks. Its unit tests include `pg-restore` series that must not fire.

**Custom exporter queries** (all work on a primary and on a standby):

| Metric | Meaning |
|---|---|
| `pg_ha_archive_ready_count`, `pg_ha_archive_oldest_ready_seconds` | WAL segments waiting to be archived (`.ready` files from `pg_ls_archive_statusdir()`), and the age of the oldest one |
| `pg_ha_replication_lag_bytes`, `pg_ha_replication_replay_lag_seconds` | Per standby, from the primary's `pg_stat_replication` (labels `application_name`, `state`, `sync_state`) |
| `pg_ha_slot_retained_bytes`, `pg_ha_slot_safe_wal_size_bytes`, `pg_ha_slot_lost`, `pg_ha_slot_active` | Per replication slot, from `pg_replication_slots` |

## How replication lag is measured (R1.7)

Lag is read on the primary, per standby, from `pg_stat_replication`. The exporter runs this query every 10 s:

```sql
select application_name, state, sync_state,
       case when pg_is_in_recovery() then 0 else pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) end as lag_bytes,
       coalesce(extract(epoch from replay_lag), 0) as replay_lag_seconds
from pg_stat_replication where replay_lsn is not null
```

- **Bytes** is how much WAL the primary has written that the standby has not replayed yet.
- **Seconds** is Postgres's own `replay_lag`: the time between the primary flushing WAL and the standby reporting it replayed. Postgres shows NULL once a standby has caught up and nothing new is written, so NULL is reported as 0.

PromQL used by the alerts and by `make test-metrics`:

```promql
# Lag in bytes per standby
max by (application_name) (pg_ha_replication_lag_bytes{namespace="pg-ha"})
# Lag in seconds per standby
max by (application_name) (pg_ha_replication_replay_lag_seconds{namespace="pg-ha"})
# Cross-check from Patroni, bytes: primary's WAL position minus each standby's replayed position
# (a standby reports patroni_xlog_location 0, so the max is the primary's)
scalar(max(patroni_xlog_location{namespace="pg-ha"})) - patroni_xlog_replayed_location{namespace="pg-ha"}
  and on (pod) patroni_replica{namespace="pg-ha"} == 1
```

`make test-metrics` shows lag rising under a throttled stream and returning to near zero. The values are in the evidence.

## Alerts

Rules: [`deploy/monitoring/rules/pg-ha.rules.yml`](../deploy/monitoring/rules/pg-ha.rules.yml). Unit tests: [`tests/alerts/pg-ha.test.yml`](../tests/alerts/pg-ha.test.yml) (`make test-alerts`, 33 test groups, each alert both fires and stays silent). Severities: **critical** means data or availability is at risk now. **warning** means degraded, act today. **info** is a record only.

| Alert | Severity | Condition (summary) | Threshold | Why this threshold | Response |
|---|---|---|---|---|---|
| NoPrimary | critical | No member has `patroni_primary = 1`, or no Patroni metrics at all | for 45 s | Worst measured failover is 26 s (L2 node mode). 45 s means failover itself failed | `make status`. Check the DCS (API server) and CoreDNS, then Patroni logs on the members |
| MultiplePrimaries | critical | More than one `patroni_primary = 1`, or more than one Postgres not in recovery | for 20 s | One scrape can catch both during a switchover. Two evaluations rule that out | Stop client writes and find the member without the leader lock. See the L2 split-brain evidence |
| MemberDown | warning | Patroni scrape fails, Postgres not running, or fewer `up` members than StatefulSet replicas | for 30 s | Pod restart takes 10–20 s and ttl is 20 s. Still serving on two members | `kubectl get pods -o wide`, node state, Patroni logs |
| ReplicaNotStreaming | warning | Fewer streaming standbys than replicas − 1 | for 2 min | Re-clone takes about 1 min at this size (ADR-008, L4). Raise it as data grows | Look for a re-clone in Patroni logs, a lost slot, or a network problem |
| ReplicationLagHigh (`lag=bytes`) | warning | A standby's lag in bytes > 16 MiB | for 2 min | Above 1 MiB (`maximum_lag_on_failover`) it cannot be promoted. 2 min filters bulk loads | Check standby I/O and network, and long queries on the standby |
| ReplicationLagHigh (`lag=seconds`) | warning | A standby's `replay_lag` > 30 s | for 2 min | Equals the RTO target, because a promoted standby would replay that much first | As above |
| SyncStandbyMissing | critical | A primary exists, but no member is sync standby | for 1 min | Non-strict sync (ADR-004): commits are not replicated, and Patroni will not fail over automatically. A new sync is normally picked within seconds | Bring a standby back to streaming (see ReplicaNotStreaming) |
| SlotWALRetentionHigh | warning | A slot holds > 512 MiB of WAL | for 5 min | Half of `max_slot_wal_keep_size` (1 GB, ADR-005) | Find the inactive or lagging standby before the slot is invalidated |
| SlotLost | warning | A slot's `wal_status` is `lost` | immediate | The 1 GB cap was hit. The standby needs the archive or a re-clone | Confirm the standby recovered through `restore_command`, otherwise re-clone it |
| ArchiveFailing | warning | `pg_stat_archiver.failed_count` increased in the last 5 min | immediate | Any failure means WAL is not leaving. One failed attempt during a Garage restart warns and clears | Check Garage, and the archive-push error in the Postgres log |
| ArchiveStale | critical | Oldest `.ready` WAL segment waiting > 120 s | immediate | A segment closes ≤ 60 s (`archive_timeout`) after its first write, and a Garage restart adds about 60 s. Beyond that, more than 3 min of writes is not in the repository. Idle clusters close no segment, so they do not fire | As ArchiveFailing. PITR (RPO) is degrading |
| BackupFailed | warning | The newest `pg-backup-*` Job failed (newer than the newest success) | immediate | The Job exits non-zero on backup, expire or verify errors | Read the Job log, then `make backup` |
| BackupStale | critical | No `pg-backup-*` Job succeeded in 26 h (new clusters get 26 h from CronJob creation) | 26 h | Daily at 20:00 UTC. 26 h allows a late run, not a missed day | Check the CronJob and the last Job, then `make backup` |
| RestoreTestFailed | warning | The newest `pg-restore-test*` Job failed | immediate | It exits non-zero on restore, recovery or `pg_amcheck` errors (ADR-010) | Read the Job log. The newest backup may not be restorable |
| RestoreTestStale | warning | No `pg-restore-test*` Job succeeded in 26 h | 26 h | Daily at 21:00 UTC | Check the CronJob, then `make test-restore` |
| DiskLow | warning | Root filesystem free < 15 % on a node | for 5 min | local-path volumes are not size-limited, so data, WAL, the restore test (≤ 4 Gi) and the slot cap share the 48 GB host. 15 % is about 7 GB | Free space or grow the disk, and check slot retention |
| CoreDNSNotReady | critical | CoreDNS Deployment has no available replica | for 1 min | Promotion runs `restore_command`, which resolves Garage through DNS (L3). A restart takes 10–20 s | Check the server node and the CoreDNS pod |
| FailoverOccurred | info | Highest timeline is above its value 5 min ago | immediate, clears after 5 min | Informational. Every promotion (failover or switchover) starts a timeline | Confirm the failover was expected, and check the old primary rejoined |
| MonitoringTargetDown | warning | kube-state-metrics, node_exporter or Alertmanager scrape down | for 5 min | Backup, restore, CoreDNS and disk alerts are blind without them. 5 min tolerates a restart | Restart the component (`make monitoring`) |

**Design notes**
- **BackupStale and RestoreTestStale count only Jobs named `pg-backup-*` / `pg-restore-test*`.** The CronJob's `lastSuccessfulTime` is not used. Stanza and check Jobs made from the `pg-backup` template are owned by that CronJob and set it too, so it would hide a missing backup. This was seen live during L5.
- **ArchiveStale uses the age of the oldest `.ready` file, not `last_archived_time`.** A quiet primary writes no WAL and closes no segment, so `last_archived_time` grows forever without any data at risk. Standbys also keep the archiver counters from their time as primary.
- **ArchiveFailing has no `for`.** The 5-minute `increase()` window already holds it for 5 minutes, so a `for` would only delay it.
- **NoPrimary does not fire in a normal failover.** That is intended. In a node failure, the old primary shows up as MemberDown, and FailoverOccurred records the promotion.

## Using it

| Task | Command |
|---|---|
| List firing alerts | `make alerts` (`ALL=1 make alerts` adds pending ones). Reads Alertmanager through the API server's service proxy, with no port-forward and no exec |
| Prometheus UI | `make prometheus-ui`, then open http://127.0.0.1:9090 (Alerts, Status → Targets, Graph) |
| Alertmanager UI | `make alertmanager-ui`, then open http://127.0.0.1:9093 |
| Rule unit tests | `make test-alerts` (Docker only, no cluster) |
| Live checks | `make test-metrics`, `make alerts-failover`, `make alerts-archive` (`make test-l5` runs all four) |

The UI targets run `kubectl port-forward` in the foreground, bound to 127.0.0.1. Press Ctrl-C to stop. For a demo, run each in its own terminal. A useful query to show is the PromQL lag query above. To show live alerts, run `make alerts-archive` in another terminal and watch the Alerts page.

## Left out, and why

| Left out | Why |
|---|---|
| Grafana and dashboards (R10.4) | Out of scope by ADR-011 unless every MUST and SHOULD is done. The Prometheus UI and `make alerts` cover the demo. Listed in known limitations |
| A real notification receiver (email, Slack, webhook) | Would put a secret in a public repo. The receiver is a no-op, and wiring a real one is one block in `alertmanager.yml` |
| Persistent Prometheus storage | Metrics are for alerting, not history: 3 days in an emptyDir on the server node, lost if the pod moves. Alert `for` state is restored from the TSDB only while the pod lives |
| HA Prometheus or Alertmanager (2 replicas) | One server node (ADR-001). Losing the server node also loses the API server, a larger outage that the L2 API-outage test covers |
| Scraping `pg-restore` | A restored cluster is temporary and must not page. It is excluded at discovery and in every rule |
| cAdvisor, kubelet and API-server metrics | Not needed by any required alert. Pod memory comes from each process's own metrics |
| Log-based alerts (Loki and similar) | Every failure mode we alert on has a metric. Backup and restore Jobs signal failure by exit code |
| Connection, query and lock metrics (pg_stat_statements, long transactions) | Useful for tuning, but not required for HA or backups. The default exporter collectors still expose basic database statistics |
| Memory alert for database nodes | The restore test has a 1 Gi limit and each Postgres pod has a 1 Gi limit, so the kubelet enforces memory per pod. Host memory is shown in the resources table, not alerted on |
