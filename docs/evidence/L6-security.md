# L6: security baseline

**Result: PASS**

- **What:** T:tls (R8.4), T:db-authz (R8.5), T:netpol (R8.6), T:pod-security (R8.7), T:rbac (R8.8), Patroni REST API authentication, and a credential scan of the full git history (R8.2). Expected refusals pass only when they fail for the expected reason.
- **Run:** 2026-11-26T14:20:16Z (UTC), 56 s
- **Reproduce:** `make test-security`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **Design:** [`../security.md`](../security.md). **History:** [`L6-security-history.md`](L6-security-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| pg_hba: every rule for the pod network is hostssl + scram-sha-256 | PASS |
| pg_hba: remote superuser rejected first (hostssl all postgres 0.0.0.0/0 reject) | PASS |
| pg_hba: non-TLS remote connections end in an explicit reject (host all all 0.0.0.0/0 reject) | PASS |
| Client through pg-rw with sslmode=verify-full (CA + hostname verified): TLS in use | PASS |
| Client through pg-ro with sslmode=verify-full: TLS in use | PASS |
| Non-TLS connection (sslmode=disable) refused by pg_hba (expected failure) | PASS |
| Wrong password refused (expected failure) | PASS |
| Remote superuser login refused before any password exchange (expected failure) | PASS |
| App role: physical replication connection rejected by pg_hba (expected failure) | PASS |
| App role: logical replication connection refused, no REPLICATION attribute (expected failure) | PASS |
| password_encryption is scram-sha-256, ssl on | PASS |
| Both replication streams use TLS | PASS |
| Replica pg-1 streams with sslmode=verify-full and the L0 CA (pg_stat_wal_receiver.conninfo) | PASS |
| Replica pg-2 streams with sslmode=verify-full and the L0 CA (pg_stat_wal_receiver.conninfo) | PASS |
| Only postgres is a superuser among login roles | PASS |
| replicator: replication only, no superuser, no other grants | PASS |
| app: no superuser, replication, createrole, createdb or bypassrls, no role memberships | PASS |
| app_ro: only pg_read_all_data | PASS |
| monitor: only pg_monitor | PASS |
| backup: only pg_checkpoint and pg_read_all_settings | PASS |
| rewind: no superuser, replication, createrole, createdb or bypassrls | PASS |
| app_ro cannot create a table (expected failure) | PASS |
| app_ro can read application data | PASS |
| monitor cannot create a table (expected failure) | PASS |
| app cannot create roles (expected failure) | PASS |
| Control: outsider has a working network (kube-dns 10.43.0.10:53 open) | PASS |
| outsider -> Postgres 5432 on the leader pod blocked | PASS |
| outsider -> Postgres via pg-rw Service blocked | PASS |
| outsider -> Patroni REST API 8008 blocked | PASS |
| outsider -> pgBackRest TLS 8432 blocked | PASS |
| outsider -> postgres_exporter 9187 blocked | PASS |
| outsider -> Garage S3 3900 blocked | PASS |
| outsider -> Garage admin 3903 blocked | PASS |
| outsider -> Prometheus 9090 blocked | PASS |
| test client (db client) -> Postgres via pg-rw open | PASS |
| test client -> Patroni 8008 blocked (clients get 5432 only) | PASS |
| test client -> pgBackRest TLS 8432 blocked | PASS |
| test client -> Garage S3 3900 blocked | PASS |
| test client -> API server blocked (no API egress for clients) | PASS |
| API server pod proxy -> Patroni GET /cluster (make status, patroni_cluster) works | PASS |
| Patroni -> API server (DCS): leader lock renewed within the last 10 s | PASS |
| Prometheus (via the API proxy) -> every target up: members 8008 and 9187, node_exporter, kube-state-metrics, Alertmanager | PASS |
| Prometheus -> API server: pod discovery found all 3 members | PASS |
| API server service proxy -> Alertmanager works (make alerts) | PASS |
| Backup-template Job -> pgBackRest TLS 8432 on the members and Garage S3; primary -> Garage archive-push (pgbackrest check) | PASS |
| Client DNS and pg-rw 5432 work | PASS |
| GET /cluster without credentials: 200 (status and helpers stay usable) | PASS |
| GET /readiness without credentials: 200 (kubelet probe) | PASS |
| GET /metrics without credentials: 200 (Prometheus) | PASS |
| POST /switchover without credentials refused: 401 (expected failure) | PASS |
| POST /switchover with a wrong password refused: 401 (expected failure) | PASS |
| POST /restart without credentials refused: 401 (expected failure) | PASS |
| POST /reinitialize without credentials refused: 401 (expected failure) | PASS |
| PATCH /config without credentials refused: 401 (expected failure) | PASS |
| DELETE /switchover without credentials refused: 401 (expected failure) | PASS |
| Authenticated POST /switchover accepted: 202, switchover scheduled for 2026-11-27T14:20:54+00:00 | PASS |
| Authenticated DELETE /switchover accepted: the scheduled switchover is cancelled (200) | PASS |
| Leader unchanged after the REST API checks (pg-0) | PASS |
| Every running pod in pg-ha passes restricted (server re-check gives no warning) | PASS |
| Every running pod in monitoring passes restricted | PASS |
| A privileged pod is rejected in pg-ha (expected failure) | PASS |
| A pod without a restricted securityContext (root, escalation allowed) is rejected (expected failure) | PASS |
| Control: a restricted-compliant pod is admitted (server dry run) | PASS |
| Every container in pg-ha: non-root, no escalation, ALL capabilities dropped, read-only root, RuntimeDefault seccomp | PASS |
| Every container in monitoring: non-root, no escalation, ALL dropped, read-only root, RuntimeDefault seccomp | PASS |
| No ClusterRoleBinding names a ServiceAccount from pg-ha, monitoring or monitoring-host | PASS |
| can-i pg-ha:pg: get endpoints in pg-ha -> yes | PASS |
| can-i pg-ha:pg: patch endpoints in pg-ha -> yes | PASS |
| can-i pg-ha:pg: patch pods in pg-ha -> yes | PASS |
| can-i pg-ha:pg: create services in pg-ha -> yes | PASS |
| can-i pg-ha:pg: get secrets in pg-ha -> no | PASS |
| can-i pg-ha:pg: list secrets in pg-ha -> no | PASS |
| can-i pg-ha:pg: create pods in pg-ha -> no | PASS |
| can-i pg-ha:pg: delete pods in pg-ha -> no | PASS |
| can-i pg-ha:pg: create pods/exec in pg-ha -> no | PASS |
| can-i pg-ha:pg: create pods/portforward in pg-ha -> no | PASS |
| can-i pg-ha:pg: update services in pg-ha -> no | PASS |
| can-i pg-ha:pg: delete statefulsets in pg-ha -> no | PASS |
| can-i pg-ha:pg: get configmaps in pg-ha -> no | PASS |
| can-i pg-ha:pg: create rolebindings in pg-ha -> no | PASS |
| can-i pg-ha:pg: list pods in kube-system -> no | PASS |
| can-i pg-ha:pg: get endpoints in default -> no | PASS |
| can-i pg-ha:pg: get nodes in the cluster -> no | PASS |
| can-i pg-ha:pg: list namespaces in the cluster -> no | PASS |
| can-i monitoring:prometheus: list pods in pg-ha -> yes | PASS |
| can-i monitoring:prometheus: watch pods in monitoring-host -> yes | PASS |
| can-i monitoring:prometheus: get secrets in pg-ha -> no | PASS |
| can-i monitoring:prometheus: list pods in default -> no | PASS |
| can-i monitoring:prometheus: list pods in kube-system -> no | PASS |
| can-i monitoring:prometheus: create pods in monitoring -> no | PASS |
| can-i monitoring:prometheus: get nodes in the cluster -> no | PASS |
| can-i monitoring:kube-state-metrics: list jobs in pg-ha -> yes | PASS |
| can-i monitoring:kube-state-metrics: watch cronjobs in kube-system -> yes | PASS |
| can-i monitoring:kube-state-metrics: get secrets in pg-ha -> no | PASS |
| can-i monitoring:kube-state-metrics: list pods in pg-ha -> no | PASS |
| can-i monitoring:kube-state-metrics: list jobs in default -> no | PASS |
| can-i monitoring:kube-state-metrics: get nodes in the cluster -> no | PASS |
| can-i pg-ha:default: list pods in pg-ha -> no | PASS |
| can-i pg-ha:default: get secrets in pg-ha -> no | PASS |
| No credential value appears in the git history or the tracked tree (14 checked) | PASS |
| ./secrets is ignored by git | PASS |
| No private key block appears anywhere in the git history | PASS |

## Setup

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) role=\(.role) state=\(.state) timeline=\(.timeline)"'
pg-0 role=leader state=running timeline=44
pg-1 role=sync_standby state=streaming timeline=44
pg-2 role=replica state=streaming timeline=44
```

Leader `pg-0` (10.42.1.65), sync standby `pg-1`, Garage pod 10.42.0.7.

## T:tls and T:db-authz: pg_hba, TLS and SCRAM (R8.4, R8.5)

The rendered rules come from the pg-patroni ConfigMap that the members run with. First match wins.

```console
$ kubectl -n pg-ha get cm pg-patroni-d7g78t2dm9 -o jsonpath='{.data.10-base\.yml}' | sed -n '/^  pg_hba:/,/^[^ ]/p' | grep -E '^ +- '
    - local all all peer
    - host replication replicator 127.0.0.1/32 scram-sha-256   # Patroni's local timeline check on replicas
    - host all all 127.0.0.1/32 scram-sha-256                  # exporter sidecar (monitor) and local tools
    - hostssl all postgres 0.0.0.0/0 reject
    - hostssl replication replicator 10.42.0.0/16 scram-sha-256
    - hostssl all all 10.42.0.0/16 scram-sha-256
    - host all all 0.0.0.0/0 reject
    - host replication all 0.0.0.0/0 reject
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=verify-full sslrootcert=/etc/pg-ca/ca.crt' "select 'ssl=' || ssl || ' ' || version || ' ' || cipher from pg_stat_ssl where pid = pg_backend_pid()"
ssl=true TLSv1.3 TLS_AES_256_GCM_SHA384
```

```console
$ cx app 'host=pg-ro.pg-ha.svc.cluster.local user=app dbname=app sslmode=verify-full sslrootcert=/etc/pg-ca/ca.crt' "select 'ssl=' || ssl || ' ' || version from pg_stat_ssl where pid = pg_backend_pid()"
ssl=true TLSv1.3
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=disable' 'select 1'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.106.91), port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "10.42.0.81", user "app", database "app", no encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx wrong 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require' 'select 1'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.106.91), port 5432 failed: FATAL:  password authentication failed for user "app"
command terminated with exit code 2
[exit code 2]
```

```console
$ cx none 'host=pg-rw.pg-ha.svc.cluster.local user=postgres dbname=postgres sslmode=require' 'select 1'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.106.91), port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "10.42.0.81", user "postgres", database "postgres", SSL encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require replication=true' 'IDENTIFY_SYSTEM'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.106.91), port 5432 failed: FATAL:  pg_hba.conf rejects replication connection for host "10.42.0.81", user "app", SSL encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require replication=database' 'IDENTIFY_SYSTEM'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.106.91), port 5432 failed: FATAL:  permission denied to start WAL sender
DETAIL:  Only roles with the REPLICATION attribute may start a WAL sender process.
command terminated with exit code 2
[exit code 2]
```

```console
$ cx monitor 'host=pg-rw.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select 'password_encryption=' || current_setting('password_encryption') || ' ssl=' || current_setting('ssl') || ' ssl_min_protocol_version=' || current_setting('ssl_min_protocol_version')"
password_encryption=scram-sha-256 ssl=on ssl_min_protocol_version=TLSv1.2
```

Replication streams, as seen on the primary (pg_stat_replication joined with pg_stat_ssl):

```console
$ cx monitor 'host=pg-rw.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select r.application_name, r.state, r.sync_state, 'ssl=' || s.ssl, s.version from pg_stat_replication r join pg_stat_ssl s using (pid) order by 1"
pg-1 streaming sync ssl=true TLSv1.3
pg-2 streaming async ssl=true TLSv1.3
```

```console
$ cx monitor 'host=pg-1.pg-headless.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select status, regexp_replace(conninfo, 'password=[^ ]*', 'password=********') from pg_stat_wal_receiver"
streaming user=replicator passfile=/tmp/pgpass channel_binding=prefer dbname=replication host=pg-0.pg-headless.pg-ha.svc.cluster.local port=5432 application_name=pg-1 fallback_application_name=pg-rw sslmode=verify-full sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslrootcert=/etc/pg-tls/ca.crt sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable
```

```console
$ cx monitor 'host=pg-2.pg-headless.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select status, regexp_replace(conninfo, 'password=[^ ]*', 'password=********') from pg_stat_wal_receiver"
streaming user=replicator passfile=/tmp/pgpass channel_binding=prefer dbname=replication host=pg-0.pg-headless.pg-ha.svc.cluster.local port=5432 application_name=pg-2 fallback_application_name=pg-rw sslmode=verify-full sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslrootcert=/etc/pg-tls/ca.crt sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable
```

## T:db-authz: separate roles with least privilege (R8.5)

```console
$ cx monitor 'host=pg-rw.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select r.rolname, 'super=' || r.rolsuper, 'repl=' || r.rolreplication, 'createrole=' || r.rolcreaterole, 'createdb=' || r.rolcreatedb, 'bypassrls=' || r.rolbypassrls, 'member_of=' || coalesce((select string_agg(b.rolname, ',' order by b.rolname) from pg_auth_members m join pg_roles b on b.oid = m.roleid where m.member = r.oid), '-') from pg_roles r where r.rolcanlogin order by 1"
app super=false repl=false createrole=false createdb=false bypassrls=false member_of=-
app_ro super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_read_all_data
backup super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_checkpoint,pg_read_all_settings
monitor super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_monitor
postgres super=true repl=true createrole=true createdb=true bypassrls=true member_of=-
replicator super=false repl=true createrole=false createdb=false bypassrls=false member_of=-
rewind super=false repl=false createrole=false createdb=false bypassrls=false member_of=-
```

```console
$ cx app_ro 'host=pg-rw.pg-ha.svc.cluster.local user=app_ro dbname=app sslmode=require' 'create table l6_should_not_exist (i int)'
ERROR:  permission denied for schema public
LINE 1: create table l6_should_not_exist (i int)
                     ^
command terminated with exit code 1
[exit code 1]
```

```console
$ cx app_ro 'host=pg-rw.pg-ha.svc.cluster.local user=app_ro dbname=app sslmode=require' 'select count(*) from pgbench_accounts'
1000000
```

```console
$ cx monitor 'host=pg-rw.pg-ha.svc.cluster.local user=monitor dbname=app sslmode=require' 'create table l6_should_not_exist (i int)'
ERROR:  permission denied for schema public
LINE 1: create table l6_should_not_exist (i int)
                     ^
command terminated with exit code 1
[exit code 1]
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require' 'create role l6_should_not_exist'
ERROR:  permission denied to create role
DETAIL:  Only roles with the CREATEROLE attribute may create roles.
command terminated with exit code 1
[exit code 1]
```

## T:netpol: NetworkPolicy, default deny with explicit allows (R8.6)

```console
$ kubectl get networkpolicy -A
NAMESPACE         NAME                      POD-SELECTOR                                AGE
monitoring-host   default-deny              <none>                                      21h
monitoring-host   node-exporter             app.kubernetes.io/name=node-exporter        21h
monitoring        alertmanager              app.kubernetes.io/name=alertmanager         21h
monitoring        allow-dns-egress          <none>                                      21h
monitoring        default-deny              <none>                                      21h
monitoring        kube-state-metrics        app.kubernetes.io/name=kube-state-metrics   21h
monitoring        prometheus                app.kubernetes.io/name=prometheus           21h
pg-ha             allow-dns-egress          <none>                                      21h
pg-ha             backup-egress             app.kubernetes.io/name=pg-backup            21h
pg-ha             db-client-egress          pg-ha/db-client=true                        21h
pg-ha             default-deny              <none>                                      21h
pg-ha             garage-bootstrap-egress   app.kubernetes.io/name=garage-bootstrap     21h
pg-ha             garage-ingress            app.kubernetes.io/name=garage               21h
pg-ha             pg-egress                 app.kubernetes.io/name=pg                   21h
pg-ha             pg-ingress                app.kubernetes.io/name=pg                   21h
pg-ha             restore-test-egress       app.kubernetes.io/name=pg-restore-test      21h
```

A throwaway namespace `l6-outsider` with one pod, `outsider`, made to look like an insider: it carries both `app.kubernetes.io/name=pg` and `pg-ha/db-client=true`. Labels in another namespace grant nothing, because every allow names pg-ha pods or a labelled namespace. Probes go to pod IPs and to Service names. kube-router (the k3s policy controller) rejects a denied connection at once, so a block shows as *rejected*. That each port really listens is shown by the allowed paths: the test client reaches the same leader IP on 5432, the API proxy and Prometheus reach 8008 and 9187, the backup Job reaches 8432, the members reach Garage 3900 (archiving) and the bootstrap Job reaches 3903.

| Source | Destination | Expected | Got |
|---|---|---|---|
| outsider | 10.43.0.10:53 | open | open |
| outsider | 10.42.1.65:5432 | blocked | blocked (rejected, rc=1) |
| outsider | pg-rw.pg-ha.svc.cluster.local:5432 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.1.65:8008 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.1.65:8432 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.1.65:9187 | blocked | blocked (rejected, rc=1) |
| outsider | garage.pg-ha.svc.cluster.local:3900 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.0.7:3903 | blocked | blocked (rejected, rc=1) |
| outsider | prometheus.monitoring.svc.cluster.local:9090 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | pg-rw.pg-ha.svc.cluster.local:5432 | open | open |
| test client (pg-ha, db-client) | 10.42.1.65:8008 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | 10.42.1.65:8432 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | 10.42.0.7:3900 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | kubernetes.default.svc.cluster.local:443 | blocked | blocked (rejected, rc=1) |

Allowed paths still work under the policies:

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) \(.role) \(.state)"'
pg-0 leader running
pg-1 sync_standby streaming
pg-2 replica streaming
```

```console
$ lock; echo; date -u +%FT%TZ
pg-0 2026-11-26T14:20:44.291224+00:00 2026-11-26T14:19:08.478625+00:00
2026-11-26T14:20:44Z
```

```console
$ jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health) lastScrape=\(.lastScrape)"' <<<'{"status":"success","data":{"activeTargets":[{"discoveredLabels":{"__address__":"alertmanager.monitoring.svc:9093","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"alertmanager"},"labels":{"instance":"alertmanager.monitoring.svc:9093","job":"alertmanager"},"scrapePool":"alertmanager","scrapeUrl":"http://alertmanager.monitoring.svc:9093/metrics","globalUrl":"http://alertmanager.monitoring.svc:9093/metrics","lastError":"","lastScrape":"2026-11-26T14:20:44.832416826Z","lastScrapeDuration":0.008762913,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"kube-state-metrics.monitoring.svc:8080","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"kube-state-metrics"},"labels":{"instance":"kube-state-metrics.monitoring.svc:8080","job":"kube-state-metrics"},"scrapePool":"kube-state-metrics","scrapeUrl":"http://kube-state-metrics.monitoring.svc:8080/metrics","globalUrl":"http://kube-state-metrics.monitoring.svc:8080/metrics","lastError":"","lastScrape":"2026-11-26T14:20:35.160228685Z","lastScrapeDuration":0.002218837,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"kube-state-metrics.monitoring.svc:8081","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"kube-state-metrics-self"},"labels":{"instance":"kube-state-metrics.monitoring.svc:8081","job":"kube-state-metrics-self"},"scrapePool":"kube-state-metrics-self","scrapeUrl":"http://kube-state-metrics.monitoring.svc:8081/metrics","globalUrl":"http://kube-state-metrics.monitoring.svc:8081/metrics","lastError":"","lastScrape":"2026-11-26T14:20:39.222776891Z","lastScrapeDuration":0.002817253,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.45:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://2c6f22d21e7dfc5cad86e9b8ed7d24a5f9a2ce3f7da3dad4059c528127485081","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.1.45","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-277qr","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"02b149b9-f123-4808-a14c-dbd8ffd5876f","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-1","job":"node","node":"k3d-pg-ha-agent-1"},"scrapePool":"node","scrapeUrl":"http://10.42.1.45:9100/metrics","globalUrl":"http://10.42.1.45:9100/metrics","lastError":"","lastScrape":"2026-11-26T14:20:36.075203737Z","lastScrapeDuration":0.005895193,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.0.65:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://5757433c25189f5937ad0f5f4171abbcc0fc62303cc40b6c41c73873f1777c41","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.2","__meta_kubernetes_pod_ip":"10.42.0.65","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-jnnlj","__meta_kubernetes_pod_node_name":"k3d-pg-ha-server-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"999b8ccb-1a51-4059-9337-e9978aa72ea4","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-server-0","job":"node","node":"k3d-pg-ha-server-0"},"scrapePool":"node","scrapeUrl":"http://10.42.0.65:9100/metrics","globalUrl":"http://10.42.0.65:9100/metrics","lastError":"","lastScrape":"2026-11-26T14:20:36.017679574Z","lastScrapeDuration":0.008404367,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.3.23:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://6ce08b20c242339ef53c116b349a8082bef78fd1425572bdeca094b494883c95","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.3.23","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-qhk68","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"c2f4c56f-4534-46aa-8ea2-26eeff2d04fd","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-2","job":"node","node":"k3d-pg-ha-agent-2"},"scrapePool":"node","scrapeUrl":"http://10.42.3.23:9100/metrics","globalUrl":"http://10.42.3.23:9100/metrics","lastError":"","lastScrape":"2026-11-26T14:20:41.364728766Z","lastScrapeDuration":0.008187681,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.22:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://bdb46a7ce71fd29d9039e9652dff91d6ecc21d2dd8d813de3a773ce0a4ac59a1","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.4.22","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-wck7f","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"2fa12a92-78e7-4526-950a-ccc7b662871b","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-0","job":"node","node":"k3d-pg-ha-agent-0"},"scrapePool":"node","scrapeUrl":"http://10.42.4.22:9100/metrics","globalUrl":"http://10.42.4.22:9100/metrics","lastError":"","lastScrape":"2026-11-26T14:20:42.84562909Z","lastScrapeDuration":0.006602045,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.65:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-0.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.1.65:8008/patroni\",\"state\":\"running\",\"role\":\"primary\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://1ecc4ec279911a4caf1b96c923a450da1261ce171e95ba4121b75eadffb14485","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.1.65","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"0","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"primary","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-0","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-0","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"a3f5bbdc-277b-4142-9582-ed76e80f406b","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-0","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-1","pod":"pg-0"},"scrapePool":"patroni","scrapeUrl":"http://10.42.1.65:8008/metrics","globalUrl":"http://10.42.1.65:8008/metrics","lastError":"","lastScrape":"2026-11-26T14:20:37.755989778Z","lastScrapeDuration":0.005040705,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.29:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-1.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.4.29:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"replay_lsn\":3812409984,\"receive_lsn\":3812409984,\"replication_state\":\"streaming\",\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://94bd0f3f84d73d9667c71cf5ab08739b72aac7c8b19ec155875a79f13ac758c5","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.4.29","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"1","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-1","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"68dc6c18-ff7e-4f0a-aff5-0a2648f8e2d0","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-1","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-0","pod":"pg-1"},"scrapePool":"patroni","scrapeUrl":"http://10.42.4.29:8008/metrics","globalUrl":"http://10.42.4.29:8008/metrics","lastError":"","lastScrape":"2026-11-26T14:20:44.472275191Z","lastScrapeDuration":0.004438361,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.3.35:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-2.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.3.35:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"replay_lsn\":3812409984,\"receive_lsn\":3812409984,\"replication_state\":\"streaming\",\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://34d1fcfb1a6de44c63ceb4eb649afcbb8072ceb1b1eeefb47562063c558fc097","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.3.35","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"2","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-2","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-2","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"ec5934d5-b9a1-4ec0-b3e8-1b4f21a4bd10","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-2","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-2","pod":"pg-2"},"scrapePool":"patroni","scrapeUrl":"http://10.42.3.35:8008/metrics","globalUrl":"http://10.42.3.35:8008/metrics","lastError":"","lastScrape":"2026-11-26T14:20:44.800331325Z","lastScrapeDuration":0.004451052,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.3.35:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-2.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.3.35:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"replay_lsn\":3812409984,\"receive_lsn\":3812409984,\"replication_state\":\"streaming\",\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://b213c3069ad97cc135ecdc3ca13f728a3b6b43387adb73e1566ca011aeb0ea13","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.3.35","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"2","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-2","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-2","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"ec5934d5-b9a1-4ec0-b3e8-1b4f21a4bd10","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-2","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-2","pod":"pg-2"},"scrapePool":"postgres","scrapeUrl":"http://10.42.3.35:9187/metrics","globalUrl":"http://10.42.3.35:9187/metrics","lastError":"","lastScrape":"2026-11-26T14:20:37.353136062Z","lastScrapeDuration":0.072337126,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.65:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-0.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.1.65:8008/patroni\",\"state\":\"running\",\"role\":\"primary\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://edcbd35756b6bf19ce337257b9b932a47504ac0f539f5ebb2fe4b2e6d9396601","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.1.65","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"0","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"primary","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-0","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-0","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"a3f5bbdc-277b-4142-9582-ed76e80f406b","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-0","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-1","pod":"pg-0"},"scrapePool":"postgres","scrapeUrl":"http://10.42.1.65:9187/metrics","globalUrl":"http://10.42.1.65:9187/metrics","lastError":"","lastScrape":"2026-11-26T14:20:38.72603488Z","lastScrapeDuration":0.065680624,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.29:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-1.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.4.29:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3812409984,\"replay_lsn\":3812409984,\"receive_lsn\":3812409984,\"replication_state\":\"streaming\",\"timeline\":44}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://20fcf9b8340042f8a12ea83f80f52f819eced5572f9f0631e6d106504ab1e807","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.4.29","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"1","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-1","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"68dc6c18-ff7e-4f0a-aff5-0a2648f8e2d0","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-1","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-0","pod":"pg-1"},"scrapePool":"postgres","scrapeUrl":"http://10.42.4.29:9187/metrics","globalUrl":"http://10.42.4.29:9187/metrics","lastError":"","lastScrape":"2026-11-26T14:20:37.29947618Z","lastScrapeDuration":0.068816197,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"localhost:9090","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"prometheus"},"labels":{"instance":"localhost:9090","job":"prometheus"},"scrapePool":"prometheus","scrapeUrl":"http://localhost:9090/metrics","globalUrl":"http://prometheus-6fd6845ff8-5jfbk:9090/metrics","lastError":"","lastScrape":"2026-11-26T14:20:36.874789762Z","lastScrapeDuration":0.009572289,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"}],"droppedTargets":[],"droppedTargetCounts":null}}' | sort
alertmanager alertmanager.monitoring.svc:9093 up lastScrape=2026-11-26T14:20:44.832416826Z
kube-state-metrics kube-state-metrics.monitoring.svc:8080 up lastScrape=2026-11-26T14:20:35.160228685Z
kube-state-metrics-self kube-state-metrics.monitoring.svc:8081 up lastScrape=2026-11-26T14:20:39.222776891Z
node k3d-pg-ha-agent-0 up lastScrape=2026-11-26T14:20:42.84562909Z
node k3d-pg-ha-agent-1 up lastScrape=2026-11-26T14:20:36.075203737Z
node k3d-pg-ha-agent-2 up lastScrape=2026-11-26T14:20:41.364728766Z
node k3d-pg-ha-server-0 up lastScrape=2026-11-26T14:20:36.017679574Z
patroni pg-0 up lastScrape=2026-11-26T14:20:37.755989778Z
patroni pg-1 up lastScrape=2026-11-26T14:20:44.472275191Z
patroni pg-2 up lastScrape=2026-11-26T14:20:44.800331325Z
postgres pg-0 up lastScrape=2026-11-26T14:20:38.72603488Z
postgres pg-1 up lastScrape=2026-11-26T14:20:37.29947618Z
postgres pg-2 up lastScrape=2026-11-26T14:20:37.353136062Z
prometheus localhost:9090 up lastScrape=2026-11-26T14:20:36.874789762Z
```

```console
$ kubectl get --raw '/api/v1/namespaces/monitoring/services/alertmanager:9093/proxy/api/v2/status' | jq -r '.cluster.status, .versionInfo.version'
disabled
0.34.2
```

```console
$ JOB_WAIT=300 /home/shibshankarbose71/pg-ha-k8s/scripts/pgbr-job.sh pg-check-l6 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -E 'check command end|CHECK_OK'
2026-11-26 14:20:47.380 P00   INFO: check command end: completed successfully (933ms)
CHECK_OK
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require' "select 'dns+5432 ok from ' || host(inet_server_addr())"
dns+5432 ok from 10.42.1.65
```

## Patroni REST API authentication

Reached over `kubectl port-forward` to the leader, as the switchover harness does. The credential is read from `./secrets` and handed to curl on stdin, never on a command line. Every unauthenticated request is chosen to be harmless even if auth were missing: a switchover and a restart scheduled a day ahead, an empty config patch, and a reinitialize sent to the leader (which Patroni refuses anyway).

```console
$ rest GET /cluster none | cut -c1-60
HTTP 200 {"members": [{"name": "pg-0", "role": "leader", "st
```

```console
$ rest GET /readiness none | cut -c1-60
HTTP 200 
```

```console
$ rest GET /metrics none | cut -c1-60
HTTP 200 # HELP patroni_version Patroni semver without perio
```

```console
$ rest POST /switchover none '{"leader": "pg-0", "candidate": "pg-1", "scheduled_at": "2026-11-27T14:20:54+00:00"}'
HTTP 401 no auth header received
```

```console
$ rest POST /switchover bad '{"leader": "pg-0", "candidate": "pg-1", "scheduled_at": "2026-11-27T14:20:54+00:00"}'
HTTP 401 not authenticated
```

```console
$ rest POST /restart none '{"schedule": "2026-11-27T14:20:54+00:00"}'
HTTP 401 no auth header received
```

```console
$ rest POST /reinitialize none '{}'
HTTP 401 no auth header received
```

```console
$ rest PATCH /config none '{}'
HTTP 401 no auth header received
```

```console
$ rest DELETE /switchover none
HTTP 401 no auth header received
```

```console
$ rest POST /switchover good '{"leader": "pg-0", "candidate": "pg-1", "scheduled_at": "2026-11-27T14:20:54+00:00"}'
HTTP 202 Switchover scheduled
```

```console
$ rest DELETE /switchover good
HTTP 200 scheduled switchover deleted
```

A real authenticated switchover (with RTO) is run by `make switchover` (tests/failover.sh), evidence in `L2/switchover.md`.

## T:pod-security: Pod Security restricted (R8.7)

```console
$ kubectl get ns pg-ha monitoring monitoring-host -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit
NAME              STATUS   AGE   ENFORCE      WARN         AUDIT
pg-ha             Active   25h   restricted   restricted   restricted
monitoring        Active   21h   restricted                
monitoring-host   Active   21h   privileged   restricted   restricted
```

```console
$ kubectl label --dry-run=server --overwrite ns pg-ha pod-security.kubernetes.io/enforce=restricted 2>&1
namespace/pg-ha not labeled (server dry run)
```

```console
$ kubectl label --dry-run=server --overwrite ns monitoring pod-security.kubernetes.io/enforce=restricted 2>&1
namespace/monitoring not labeled (server dry run)
```

```console
$ kubectl -n pg-ha run l6-privileged --image=pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1 --restart=Never --dry-run=server --overrides='{"spec": {"containers": [{"name": "l6-privileged", "image": "pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1", "securityContext": {"privileged": true}}]}}'
Error from server (Forbidden): pods "l6-privileged" is forbidden: violates PodSecurity "restricted:v1.35": privileged (container "l6-privileged" must not set securityContext.privileged=true), allowPrivilegeEscalation != false (container "l6-privileged" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "l6-privileged" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "l6-privileged" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "l6-privileged" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[exit code 1]
```

```console
$ kubectl -n pg-ha run l6-root --image=pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1 --restart=Never --dry-run=server
Error from server (Forbidden): pods "l6-root" is forbidden: violates PodSecurity "restricted:v1.35": allowPrivilegeEscalation != false (container "l6-root" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "l6-root" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "l6-root" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "l6-root" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[exit code 1]
```

```console
$ kubectl -n pg-ha run l6-compliant --image=pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1 --restart=Never --dry-run=server --overrides='{"spec": {"securityContext": {"runAsNonRoot": true, "runAsUser": 999, "seccompProfile": {"type": "RuntimeDefault"}}, "containers": [{"name": "l6-compliant", "image": "pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1", "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}}]}}'
pod/l6-compliant created (server dry run)
```

Security context of every container running in pg-ha and monitoring:

```console
$ kubectl get pods -n pg-ha -o json | jq -r '.items[] | .metadata.name as $p | .spec.securityContext as $s | .spec.containers[] | "\($p)/\(.name) nonRoot=\($s.runAsNonRoot) uid=\($s.runAsUser) seccomp=\($s.seccompProfile.type) escalation=\(.securityContext.allowPrivilegeEscalation) drop=\(.securityContext.capabilities.drop | join(",")) roRootFS=\(.securityContext.readOnlyRootFilesystem) privileged=\(.securityContext.privileged // false)"'
garage-78b588844b-gjqdp/garage nonRoot=true uid=10001 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
garage-bootstrap-966ss/bootstrap nonRoot=true uid=100 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-29927280-sdv9r/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-manual-20261125130202-klnpp/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-manual-20261125172539-dn4jq/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-manual-20261125172613-zbjht/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-manual-20261126140930-f5sgh/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-check-l6-6mfcz/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-check-l6-step0-42jn9/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-netpol-race-probe-r67qm/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-restore-test-29927025-qj82k/restore-test nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-restore-test-29927340-xj8jc/restore-test nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-stanza-create-79zdw/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-test-client/client nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
```

```console
$ kubectl get pods -n monitoring -o json | jq -r '.items[] | .metadata.name as $p | .spec.securityContext as $s | .spec.containers[] | "\($p)/\(.name) nonRoot=\($s.runAsNonRoot) seccomp=\($s.seccompProfile.type) escalation=\(.securityContext.allowPrivilegeEscalation) drop=\(.securityContext.capabilities.drop | join(",")) roRootFS=\(.securityContext.readOnlyRootFilesystem)"'
alertmanager-7bfd9ccc56-m7ggq/alertmanager nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
kube-state-metrics-745cf745bf-z7hzz/kube-state-metrics nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
prometheus-6fd6845ff8-5jfbk/prometheus nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
```

## T:rbac: ServiceAccounts and kubectl auth can-i (R8.8)

```console
$ kubectl get sa -n pg-ha; kubectl get sa -n monitoring; kubectl get sa -n monitoring-host
NAME      AGE
default   25h
pg        25h
NAME                 AGE
default              21h
kube-state-metrics   21h
prometheus           21h
NAME      AGE
default   21h
```

```console
$ kubectl get roles,rolebindings -n pg-ha -o wide; kubectl get roles,rolebindings -n monitoring-host -o wide; kubectl get roles,rolebindings -n kube-system -o wide | grep -E '^NAME|kube-state-metrics'
NAME                                                CREATED AT
role.rbac.authorization.k8s.io/kube-state-metrics   2026-11-25T16:30:31Z
role.rbac.authorization.k8s.io/pg-patroni           2026-11-25T12:58:47Z
role.rbac.authorization.k8s.io/prometheus-sd        2026-11-25T16:30:31Z

NAME                                                       ROLE                      AGE   USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/kube-state-metrics   Role/kube-state-metrics   21h                    monitoring/kube-state-metrics
rolebinding.rbac.authorization.k8s.io/pg-patroni           Role/pg-patroni           25h                    pg-ha/pg
rolebinding.rbac.authorization.k8s.io/prometheus-sd        Role/prometheus-sd        21h                    monitoring/prometheus
NAME                                           CREATED AT
role.rbac.authorization.k8s.io/prometheus-sd   2026-11-25T16:30:31Z

NAME                                                  ROLE                 AGE   USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/prometheus-sd   Role/prometheus-sd   21h                    monitoring/prometheus
NAME                                                                            CREATED AT
role.rbac.authorization.k8s.io/kube-state-metrics                               2026-11-25T16:30:31Z
NAME                                                                                       ROLE                                                  AGE   USERS                                                   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/kube-state-metrics                                   Role/kube-state-metrics                               21h                                                                    monitoring/kube-state-metrics
```

```console
$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; (.namespace // "") as $n | $n == "pg-ha" or $n == "monitoring" or $n == "monitoring-host")) | .metadata.name' | sed 's/^/clusterrolebinding: /'; echo end
end
```

```console
$ kubectl auth can-i --list -n pg-ha --as=system:serviceaccount:pg-ha:pg | grep -vE 'selfsubject|/api|/openapi|/version|/healthz|/livez|/readyz|\[\]\s+\[\]\s+\[get\]'
Resources                                       Non-Resource URLs                      Resource Names   Verbs
services                                        []                                     []               [create]
endpoints                                       []                                     []               [get list watch create update patch delete]
pods                                            []                                     []               [get list watch update patch]
                                                [/.well-known/openid-configuration/]   []               [get]
                                                [/.well-known/openid-configuration]    []               [get]
                                                [/openid/v1/jwks/]                     []               [get]
                                                [/openid/v1/jwks]                      []               [get]
```

```console
$ kubectl auth can-i --list -n monitoring --as=system:serviceaccount:monitoring:prometheus | grep -vE 'selfsubject|/api|/openapi|/version|/healthz|/livez|/readyz|\[\]\s+\[\]\s+\[get\]'
Resources                                       Non-Resource URLs                      Resource Names   Verbs
                                                [/.well-known/openid-configuration/]   []               [get]
                                                [/.well-known/openid-configuration]    []               [get]
                                                [/openid/v1/jwks/]                     []               [get]
                                                [/openid/v1/jwks]                      []               [get]
```

```console
$ kubectl auth can-i --list -n monitoring --as=system:serviceaccount:monitoring:kube-state-metrics | grep -vE 'selfsubject|/api|/openapi|/version|/healthz|/livez|/readyz|\[\]\s+\[\]\s+\[get\]'
Resources                                       Non-Resource URLs                      Resource Names   Verbs
                                                [/.well-known/openid-configuration/]   []               [get]
                                                [/.well-known/openid-configuration]    []               [get]
                                                [/openid/v1/jwks/]                     []               [get]
                                                [/openid/v1/jwks]                      []               [get]
```

| ServiceAccount | Verb and resource | Namespace | Expected | Got |
|---|---|---|---|---|
| pg-ha:pg | get endpoints | pg-ha | yes | yes |
| pg-ha:pg | patch endpoints | pg-ha | yes | yes |
| pg-ha:pg | patch pods | pg-ha | yes | yes |
| pg-ha:pg | create services | pg-ha | yes | yes |
| pg-ha:pg | get secrets | pg-ha | no | no |
| pg-ha:pg | list secrets | pg-ha | no | no |
| pg-ha:pg | create pods | pg-ha | no | no |
| pg-ha:pg | delete pods | pg-ha | no | no |
| pg-ha:pg | create pods/exec | pg-ha | no | no |
| pg-ha:pg | create pods/portforward | pg-ha | no | no |
| pg-ha:pg | update services | pg-ha | no | no |
| pg-ha:pg | delete statefulsets | pg-ha | no | no |
| pg-ha:pg | get configmaps | pg-ha | no | no |
| pg-ha:pg | create rolebindings | pg-ha | no | no |
| pg-ha:pg | list pods | kube-system | no | no |
| pg-ha:pg | get endpoints | default | no | no |
| pg-ha:pg | get nodes | the cluster | no | no |
| pg-ha:pg | list namespaces | the cluster | no | no |
| monitoring:prometheus | list pods | pg-ha | yes | yes |
| monitoring:prometheus | watch pods | monitoring-host | yes | yes |
| monitoring:prometheus | get secrets | pg-ha | no | no |
| monitoring:prometheus | list pods | default | no | no |
| monitoring:prometheus | list pods | kube-system | no | no |
| monitoring:prometheus | create pods | monitoring | no | no |
| monitoring:prometheus | get nodes | the cluster | no | no |
| monitoring:kube-state-metrics | list jobs | pg-ha | yes | yes |
| monitoring:kube-state-metrics | watch cronjobs | kube-system | yes | yes |
| monitoring:kube-state-metrics | get secrets | pg-ha | no | no |
| monitoring:kube-state-metrics | list pods | pg-ha | no | no |
| monitoring:kube-state-metrics | list jobs | default | no | no |
| monitoring:kube-state-metrics | get nodes | the cluster | no | no |
| pg-ha:default | list pods | pg-ha | no | no |
| pg-ha:default | get secrets | pg-ha | no | no |

## Credentials stay out of git (R8.2)

Every current credential value in `./secrets/credentials` is searched for in the full history of every branch (`git log -p --all`) and in the tracked working tree. Values are compared inside this script and never printed.

```console
$ echo 'credential values checked: 14, found in git history or tracked files: 0'; git -C '/home/shibshankarbose71/pg-ha-k8s' check-ignore -v secrets/credentials/pg-app-password secrets/tls/ca.key
credential values checked: 14, found in git history or tracked files: 0
.gitignore:10:secrets/	secrets/credentials/pg-app-password
.gitignore:10:secrets/	secrets/tls/ca.key
```

```console
$ grep -cE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' '/tmp/tmp.ZQpkRWz6xm/tmp.zPpZ91Rujv' || true
0
```
