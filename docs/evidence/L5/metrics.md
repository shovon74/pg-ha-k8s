# L5: Scrape targets, key series, lag measurement and resources (R10.1, R1.7)

**Result: PASS**

- **What:** Every scrape target up, the key series for each alert present, all rules loaded and healthy, nothing firing on the healthy cluster, nothing scraped from pg-restore. Then induced lag (R1.7): the async standby's stream is throttled with iptables on the primary's node while a writer fills WAL. Lag in bytes and seconds must rise past the alert thresholds, ReplicationLagHigh must fire in Alertmanager (R10.3), and after the throttle lag must return to near zero and the alert resolve. Then RAM and disk use with monitoring running.
- **Run:** 2026-11-25T16:53:07Z (UTC), 162 s
- **Reproduce:** `make test-metrics`
- **Versions:** Prometheus `prom/prometheus:v3.16.0`, Alertmanager `prom/alertmanager:v0.34.2`, postgres_exporter `quay.io/prometheuscommunity/postgres-exporter:v0.20.1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Checks

| Check | Result |
|---|---|
| Job patroni: 3 target(s) up (found 3) | PASS |
| Job postgres: 3 target(s) up (found 3) | PASS |
| Job node: 4 target(s) up (found 4) | PASS |
| Job kube-state-metrics: 1 target(s) up (found 1) | PASS |
| Job kube-state-metrics-self: 1 target(s) up (found 1) | PASS |
| Job alertmanager: 1 target(s) up (found 1) | PASS |
| Job prometheus: 1 target(s) up (found 1) | PASS |
| No target is down | PASS |
| Patroni role per member: 3 series (need 3) | PASS |
| Exactly one primary: 1 series (need 1) | PASS |
| Sync standby flag: 1 series (need 1) | PASS |
| Postgres reachable by each exporter: 3 series (need 3) | PASS |
| Timeline: 3 series (need 3) | PASS |
| Replication lag in bytes per standby (primary's view): 2 series (need 2) | PASS |
| Replication lag in seconds per standby (primary's view): 2 series (need 2) | PASS |
| Slot WAL retention: 6 series (need 2) | PASS |
| Archiver failure counter: 3 series (need 3) | PASS |
| Archive backlog (.ready): 3 series (need 3) | PASS |
| Backup and restore-test CronJobs: 2 series (need 2) | PASS |
| Backup or restore-test Job status: 2 series (need 1) | PASS |
| Expected member count: 1 series (need 1) | PASS |
| CoreDNS availability: 1 series (need 1) | PASS |
| Root filesystem free space per node: 4 series (need 4) | PASS |
| No series from namespace pg-restore is scraped | PASS |
| 19 alerting rules loaded | PASS |
| Every rule evaluates without error | PASS |
| No warning or critical alert firing before the fault | PASS |
| Lag in bytes rose above the 16 MiB threshold (peak 217712496) | PASS |
| Lag in seconds rose above the 30 s threshold (peak 123.599331) | PASS |
| The standby stayed connected during the throttle (state streaming) | PASS |
| ReplicationLagHigh fired in Alertmanager | PASS |
| Lag returned to near zero (< 1 MiB, < 1 s) within 180 s of removing the throttle | PASS |
| ReplicationLagHigh resolved in Alertmanager | PASS |

## Scrape targets (R10.1)

```console
$ jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health)"' /tmp/tmp.4QAgf9HRrH | sort
alertmanager alertmanager.monitoring.svc:9093 up
kube-state-metrics kube-state-metrics.monitoring.svc:8080 up
kube-state-metrics-self kube-state-metrics.monitoring.svc:8081 up
node k3d-pg-ha-agent-0 up
node k3d-pg-ha-agent-1 up
node k3d-pg-ha-agent-2 up
node k3d-pg-ha-server-0 up
patroni pg-0 up
patroni pg-1 up
patroni pg-2 up
postgres pg-0 up
postgres pg-1 up
postgres pg-2 up
prometheus localhost:9090 up
```

## Key series (R10.1)

One query per signal that an alert or the lag measurement depends on. Values at the time of the run.

`patroni_primary{namespace="pg-ha"}`

```
instance=pg-2,job=patroni,name=pg-2,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2,scope=pg-rw 0
instance=pg-1,job=patroni,name=pg-1,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,scope=pg-rw 1
instance=pg-0,job=patroni,name=pg-0,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0,scope=pg-rw 0
```

`sum(patroni_primary{namespace="pg-ha"}) == 1`

```
 1
```

`sum(patroni_sync_standby{namespace="pg-ha"}) == 1`

```
 1
```

`pg_up{namespace="pg-ha"} == 1`

```
instance=pg-0,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0 1
instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1 1
instance=pg-2,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2 1
```

`patroni_postgres_timeline{namespace="pg-ha"}`

```
instance=pg-2,job=patroni,name=pg-2,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2,scope=pg-rw 37
instance=pg-1,job=patroni,name=pg-1,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,scope=pg-rw 37
instance=pg-0,job=patroni,name=pg-0,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0,scope=pg-rw 37
```

`pg_ha_replication_lag_bytes{namespace="pg-ha"}`

```
application_name=pg-0,instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,state=streaming,sync_state=sync 0
application_name=pg-2,instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,state=streaming,sync_state=async 0
```

`pg_ha_replication_replay_lag_seconds{namespace="pg-ha"}`

```
application_name=pg-0,instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,state=streaming,sync_state=sync 0
application_name=pg-2,instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,state=streaming,sync_state=async 0.008617
```

`pg_ha_slot_retained_bytes{namespace="pg-ha"}`

```
instance=pg-0,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0,slot_name=pg_1,slot_type=physical 16776944
instance=pg-0,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0,slot_name=pg_2,slot_type=physical 16776944
instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,slot_name=pg_0,slot_type=physical 0
instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1,slot_name=pg_2,slot_type=physical 0
instance=pg-2,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2,slot_name=pg_0,slot_type=physical 0
instance=pg-2,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2,slot_name=pg_1,slot_type=physical 0
```

`pg_stat_archiver_failed_count{namespace="pg-ha"}`

```
instance=pg-0,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0 0
instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1 0
instance=pg-2,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2 0
```

`pg_ha_archive_oldest_ready_seconds{namespace="pg-ha"}`

```
instance=pg-0,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-1,pod=pg-0 0
instance=pg-1,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-0,pod=pg-1 0
instance=pg-2,job=postgres,namespace=pg-ha,node=k3d-pg-ha-agent-2,pod=pg-2 0
```

`kube_cronjob_created{namespace="pg-ha"}`

```
cronjob=pg-restore-test,instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,namespace=pg-ha 1795620459
cronjob=pg-backup,instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,namespace=pg-ha 1795611527
```

`kube_job_status_succeeded{namespace="pg-ha", job_name=~"pg-backup-.+|pg-restore-test.*"}`

```
instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,job_name=pg-restore-test-29927025,namespace=pg-ha 1
instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,job_name=pg-backup-manual-20261125130202,namespace=pg-ha 1
```

`kube_statefulset_replicas{namespace="pg-ha", statefulset="pg"}`

```
instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,namespace=pg-ha,statefulset=pg 3
```

`kube_deployment_status_replicas_available{namespace="kube-system", deployment="coredns"}`

```
deployment=coredns,instance=kube-state-metrics.monitoring.svc:8080,job=kube-state-metrics,namespace=kube-system 1
```

`node_filesystem_avail_bytes{mountpoint="/"}`

```
device=overlay,fstype=overlay,instance=k3d-pg-ha-server-0,job=node,mountpoint=/,node=k3d-pg-ha-server-0 37414014976
device=overlay,fstype=overlay,instance=k3d-pg-ha-agent-1,job=node,mountpoint=/,node=k3d-pg-ha-agent-1 37414014976
device=overlay,fstype=overlay,instance=k3d-pg-ha-agent-2,job=node,mountpoint=/,node=k3d-pg-ha-agent-2 37414023168
device=overlay,fstype=overlay,instance=k3d-pg-ha-agent-0,job=node,mountpoint=/,node=k3d-pg-ha-agent-0 37414023168
```

## Rules

```console
$ jq -r '.data.groups[] | .name as $g | .rules[] | "\($g) \(.name) \(.health) \(.state)"' /tmp/tmp.Nv64zvAVvx
pg-ha-archive-backup ArchiveFailing ok inactive
pg-ha-archive-backup ArchiveStale ok inactive
pg-ha-archive-backup BackupFailed ok inactive
pg-ha-archive-backup BackupStale ok inactive
pg-ha-archive-backup RestoreTestFailed ok inactive
pg-ha-archive-backup RestoreTestStale ok inactive
pg-ha-platform DiskLow ok inactive
pg-ha-platform CoreDNSNotReady ok inactive
pg-ha-platform MonitoringTargetDown ok inactive
pg-ha-replication NoPrimary ok inactive
pg-ha-replication MultiplePrimaries ok inactive
pg-ha-replication MemberDown ok inactive
pg-ha-replication ReplicaNotStreaming ok inactive
pg-ha-replication ReplicationLagHigh ok inactive
pg-ha-replication ReplicationLagHigh ok inactive
pg-ha-replication SyncStandbyMissing ok inactive
pg-ha-replication SlotWALRetentionHigh ok inactive
pg-ha-replication SlotLost ok inactive
pg-ha-replication FailoverOccurred ok inactive
```

## Alerts on the healthy cluster

```console
$ am_lines

```

## Induced lag (R1.7, R10.3)

Primary `pg-1` on `k3d-pg-ha-agent-0`, async standby `pg-2`. Its stream is limited to 40 packets/s until ReplicationLagHigh fires (at most 300 s) while a writer fills WAL through pg-rw (one 16 MB+ fill every 10 s). Lag is read from Prometheus, which is what the alerts use.

<!-- summary -->
| Measure | Before | Peak during throttle | After |
|---|---:|---:|---:|
| Lag bytes (pg-2) | 0 | 217712496 | 0 |
| Lag seconds (pg-2) | 0.008617 | 123.599331 | 0.006325 |

| Event | Time (UTC) | Seconds after throttle start |
|---|---|---:|
| Throttle on | 16:53:11 | 0 |
| ReplicationLagHigh first seen firing | 16:55:24 | 133 |
| Throttle off | 16:55:26 | 135 |
| Lag back under 1 MiB and 1 s | 16:55:43 | 152 |
| ReplicationLagHigh gone from Alertmanager | 16:55:43 | 152 |
<!-- /summary -->

Alertmanager while firing:

```
ReplicationLagHigh/bytes severity=warning pod=- startsAt=2026-11-25T16:55:20.387Z
```

## Resources with monitoring running

Measured after the lag test. Memory per component is the resident set of its main process, as each one reports it (process_resident_memory_bytes). The host has no metrics-server (k3s's is disabled, ADR-001), so pod memory comes from these metrics and from docker stats on the k3d node containers.

```console
$ promq 'sum by (job) (process_resident_memory_bytes)'
job=alertmanager 41426944
job=node 78917632
job=prometheus 128114688
job=postgres 60772352
job=kube-state-metrics-self 56901632
```

```console
$ promq 'prometheus_tsdb_head_series'
instance=localhost:9090,job=prometheus 4617
```

```console
$ promq 'sum(prometheus_tsdb_storage_blocks_bytes) + sum(prometheus_tsdb_wal_storage_size_bytes) + sum(prometheus_tsdb_head_chunks_storage_size_bytes)'
 552956
```

```console
$ docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' $(docker ps -q --filter name=k3d-pg-ha)
k3d-pg-ha-agent-2 315.1MiB / 15.61GiB 9.41%
k3d-pg-ha-agent-1 265MiB / 15.61GiB 21.01%
k3d-pg-ha-agent-0 267MiB / 15.61GiB 7.13%
k3d-pg-ha-server-0 783.7MiB / 15.61GiB 14.97%
```

```console
$ free -m
               total        used        free      shared  buff/cache   available
Mem:           15985        2572        9492         104        4362       13413
Swap:              0           0           0
```

```console
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/root        48G   13G   35G  27% /
```

<!-- summary -->
| Component (scrape job) | Processes | Resident memory, total |
|---|---:|---:|
| alertmanager | 1 | 40 MiB |
| kube-state-metrics-self | 1 | 54 MiB |
| node | 4 | 75 MiB |
| postgres | 3 | 58 MiB |
| prometheus | 1 | 121 MiB |
| Prometheus TSDB on disk | | 1 MiB |
| Host memory used / total | | 2577 / 15985 MiB |
| Host disk used / size (/) | | 13G / 48G (27%) |
<!-- /summary -->
