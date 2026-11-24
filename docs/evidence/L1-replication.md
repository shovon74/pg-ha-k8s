# L1: replication, endpoints and rejoin

**Result: PASS**

- **Covers:** R1.1, R1.2, R1.3, R1.7 (bytes and seconds), R2.1, R2.2, R7.4 (placement), ADR-004 sync standby, ADR-005 slot cap
- **Run:** 2026-11-24T17:03:43Z (UTC), 24 s
- **Reproduce:** `make test-replication`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **kubectl exec:** psql runs only in the test's own client pod `pg-test-client`, never in a Postgres pod (D4)

## Checks

| Check | Result |
|---|---|
| Patroni: exactly 1 leader | PASS |
| Patroni: exactly 2 streaming replicas | PASS |
| Patroni: exactly 1 synchronous standby | PASS |
| Placement: 3 members on 3 distinct agent nodes (R7.4) | PASS |
| Every member runs Postgres >= 15 (R1.1) | PASS |
| Exactly 1 member not in recovery, 2 in recovery (R1.2) | PASS |
| Data checksums and server TLS on every member | PASS |
| pg_stat_replication on the primary: 2 rows streaming (R1.3) | PASS |
| pg_stat_replication: exactly 1 sync and 1 async standby | PASS |
| Postgres and Patroni agree on the sync standby (pg-1) | PASS |
| Row written through pg-rw is readable through pg-ro | PASS |
| Row is readable on replica pg-0 (R1.3) | PASS |
| Row is readable on replica pg-1 (R1.3) | PASS |
| Lag reported in bytes for both standbys | PASS |
| Lag reported in seconds for both standbys | PASS |
| One active physical slot per replica (pg_0 pg_1 ) | PASS |
| max_slot_wal_keep_size is 1GB and limits every slot (safe_wal_size set) | PASS |
| max_wal_size is 512MB | PASS |
| pg-rw EndpointSlice points only at the leader (pg-2) | PASS |
| pg-rw connects to the leader, not in recovery (R2.1) | PASS |
| pg-ro lists exactly the 2 replicas | PASS |
| pg-ro connects to a replica in recovery (R2.2) | PASS |
| pg-ro rejects a write (R2.2) | PASS |
| Deleted replica pg-1 came back as a new pod | PASS |
| Deleted replica pg-1 rejoined and is streaming | PASS |
| Leader unchanged (pg-2) and timeline unchanged | PASS |
| After rejoin: exactly 1 sync standby | PASS |
| After rejoin: pg_stat_replication shows 2 streaming rows including pg-1 | PASS |
| After rejoin: pg-1 has the marker row and its slot is active | PASS |

## Setup: test client pod (our image, Pod Security restricted)

## Topology (T:topology)

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) role=\(.role) state=\(.state) timeline=\(.timeline) lag=\(.lag // "-")"'
pg-0 role=replica state=streaming timeline=1 lag=0
pg-1 role=sync_standby state=streaming timeline=1 lag=0
pg-2 role=leader state=running timeline=1 lag=-
```

```console
$ kubectl -n pg-ha get pods -l app.kubernetes.io/name=pg -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,ROLE:.metadata.labels.role,READY:.status.containerStatuses[0].ready
POD    NODE                IP          ROLE      READY
pg-0   k3d-pg-ha-agent-1   10.42.1.7   replica   true
pg-1   k3d-pg-ha-agent-2   10.42.3.4   replica   true
pg-2   k3d-pg-ha-agent-0   10.42.2.3   primary   true
```

```console
$ cat /tmp/l1-members.481779
pg-2: version_num=170012 in_recovery=false checksums=on ssl=on
pg-0: version_num=170012 in_recovery=true checksums=on ssl=on
pg-1: version_num=170012 in_recovery=true checksums=on ssl=on
```

## Streaming and the synchronous standby (T:replication)

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select application_name, state, sync_state from pg_stat_replication order by application_name"
pg-0 streaming async
pg-1 streaming sync
```

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select name, setting from pg_settings where name in ('synchronous_commit','synchronous_standby_names') order by name"
synchronous_commit on
synchronous_standby_names "pg-1"
```

## Write through pg-rw, read through pg-ro and on each replica

```console
$ q pg-rw.pg-ha.svc.cluster.local app "insert into l1_marker(token) values ('l1-20261124T170349Z-25584') returning token, written_at"
l1-20261124T170349Z-25584 2026-11-24 17:03:49.696244+00
```

## Replication lag in bytes and seconds (R1.7)

Measured on the primary right after a write. `replay_lag` is Postgres's own time measurement and becomes NULL once a standby has been idle and caught up, so it is sampled straight after the write.

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select application_name, sync_state, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) as lag_bytes, coalesce(round(extract(epoch from replay_lag)::numeric, 6)::text, 'null') as lag_seconds from pg_stat_replication order by application_name"
pg-0 async 0 0.002417
pg-1 sync 0 0.002207
```

## Replication slots and the WAL cap (ADR-005)

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select slot_name, slot_type, active, wal_status, pg_size_pretty(safe_wal_size) as safe_wal_size from pg_replication_slots order by slot_name"
pg_0 physical t reserved 1029 MB
pg_1 physical t reserved 1029 MB
```

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select name, setting, unit from pg_settings where name in ('max_slot_wal_keep_size','max_wal_size','wal_log_hints') order by name"
max_slot_wal_keep_size 1024 MB
max_wal_size 512 MB
wal_log_hints on 
```

## Client endpoints (T:endpoints)

Leader `pg-2` has pod IP `10.42.2.3`. The pg-rw EndpointSlice (mirrored from Patroni's Endpoints) lists `10.42.2.3`. pg-ro lists `10.42.3.4 10.42.1.7 `.

```console
$ q pg-rw.pg-ha.svc.cluster.local app "select 'pg-rw: server=' || host(inet_server_addr()) || ' in_recovery=' || pg_is_in_recovery()"
pg-rw: server=10.42.2.3 in_recovery=false
```

```console
$ q pg-ro.pg-ha.svc.cluster.local app "select 'pg-ro: server=' || host(inet_server_addr()) || ' in_recovery=' || pg_is_in_recovery()"
pg-ro: server=10.42.1.7 in_recovery=true
```

```console
$ q pg-ro.pg-ha.svc.cluster.local app "insert into l1_marker(token) values ('must-fail')"
ERROR:  cannot execute INSERT in a read-only transaction
command terminated with exit code 1
[exit code 1]
```

## Replica pod deleted: it rejoins and streams again

Fault: `kubectl delete pod pg-1` (the synchronous standby). Leader before: `pg-2`, timeline 1.

```console
$ kubectl -n pg-ha delete pod pg-1 --wait=false
pod "pg-1" deleted from pg-ha namespace
```

Time from delete until the replacement pod (new UID) streams again, seen by both Patroni and pg_stat_replication on the primary: **10.3 s**.

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) role=\(.role) state=\(.state) timeline=\(.timeline) lag=\(.lag // "-")"'
pg-0 role=sync_standby state=streaming timeline=1 lag=0
pg-1 role=replica state=streaming timeline=1 lag=0
pg-2 role=leader state=running timeline=1 lag=-
```

```console
$ q pg-rw.pg-ha.svc.cluster.local monitor "select application_name, state, sync_state from pg_stat_replication order by application_name"
pg-0 streaming sync
pg-1 streaming async
```
