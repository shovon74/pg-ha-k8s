# L6: security baseline

**Result: PASS**

- **What:** T:tls (R8.4), T:db-authz (R8.5), T:netpol (R8.6), T:pod-security (R8.7), T:rbac (R8.8), Patroni REST API authentication, and a credential scan of the full git history (R8.2). Expected refusals pass only when they fail for the expected reason.
- **Run:** 2026-11-26T16:28:32Z (UTC), 56 s
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
| Replica pg-0 streams with sslmode=verify-full and the L0 CA (pg_stat_wal_receiver.conninfo) | PASS |
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
| Authenticated POST /switchover accepted: 202, switchover scheduled for 2026-11-27T16:29:10+00:00 | PASS |
| Authenticated DELETE /switchover accepted: the scheduled switchover is cancelled (200) | PASS |
| Leader unchanged after the REST API checks (pg-1) | PASS |
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
pg-0 role=sync_standby state=streaming timeline=24
pg-1 role=leader state=running timeline=24
pg-2 role=replica state=streaming timeline=24
```

Leader `pg-1` (10.42.4.9), sync standby `pg-0`, Garage pod 10.42.0.52.

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
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.195.240), port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "10.42.0.55", user "app", database "app", no encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx wrong 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require' 'select 1'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.195.240), port 5432 failed: FATAL:  password authentication failed for user "app"
command terminated with exit code 2
[exit code 2]
```

```console
$ cx none 'host=pg-rw.pg-ha.svc.cluster.local user=postgres dbname=postgres sslmode=require' 'select 1'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.195.240), port 5432 failed: FATAL:  pg_hba.conf rejects connection for host "10.42.0.55", user "postgres", database "postgres", SSL encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require replication=true' 'IDENTIFY_SYSTEM'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.195.240), port 5432 failed: FATAL:  pg_hba.conf rejects replication connection for host "10.42.0.55", user "app", SSL encryption
command terminated with exit code 2
[exit code 2]
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require replication=database' 'IDENTIFY_SYSTEM'
psql: error: connection to server at "pg-rw.pg-ha.svc.cluster.local" (10.43.195.240), port 5432 failed: FATAL:  permission denied to start WAL sender
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
pg-0 streaming sync ssl=true TLSv1.3
pg-2 streaming async ssl=true TLSv1.3
```

```console
$ cx monitor 'host=pg-0.pg-headless.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select status, regexp_replace(conninfo, 'password=[^ ]*', 'password=********') from pg_stat_wal_receiver"
streaming user=replicator passfile=/tmp/pgpass channel_binding=prefer dbname=replication host=pg-1.pg-headless.pg-ha.svc.cluster.local port=5432 application_name=pg-0 fallback_application_name=pg-rw sslmode=verify-full sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslrootcert=/etc/pg-tls/ca.crt sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable
```

```console
$ cx monitor 'host=pg-2.pg-headless.pg-ha.svc.cluster.local user=monitor dbname=postgres sslmode=require' "select status, regexp_replace(conninfo, 'password=[^ ]*', 'password=********') from pg_stat_wal_receiver"
streaming user=replicator passfile=/tmp/pgpass channel_binding=prefer dbname=replication host=pg-1.pg-headless.pg-ha.svc.cluster.local port=5432 application_name=pg-2 fallback_application_name=pg-rw sslmode=verify-full sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslrootcert=/etc/pg-tls/ca.crt sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable
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
monitoring-host   default-deny              <none>                                      100m
monitoring-host   node-exporter             app.kubernetes.io/name=node-exporter        100m
monitoring        alertmanager              app.kubernetes.io/name=alertmanager         100m
monitoring        allow-dns-egress          <none>                                      100m
monitoring        default-deny              <none>                                      100m
monitoring        kube-state-metrics        app.kubernetes.io/name=kube-state-metrics   100m
monitoring        prometheus                app.kubernetes.io/name=prometheus           100m
pg-ha             allow-dns-egress          <none>                                      102m
pg-ha             backup-egress             app.kubernetes.io/name=pg-backup            102m
pg-ha             db-client-egress          pg-ha/db-client=true                        102m
pg-ha             default-deny              <none>                                      102m
pg-ha             garage-bootstrap-egress   app.kubernetes.io/name=garage-bootstrap     102m
pg-ha             garage-ingress            app.kubernetes.io/name=garage               102m
pg-ha             pg-egress                 app.kubernetes.io/name=pg                   102m
pg-ha             pg-ingress                app.kubernetes.io/name=pg                   102m
pg-ha             restore-test-egress       app.kubernetes.io/name=pg-restore-test      102m
```

A throwaway namespace `l6-outsider` with one pod, `outsider`, made to look like an insider: it carries both `app.kubernetes.io/name=pg` and `pg-ha/db-client=true`. Labels in another namespace grant nothing, because every allow names pg-ha pods or a labelled namespace. Probes go to pod IPs and to Service names. kube-router (the k3s policy controller) rejects a denied connection at once, so a block shows as *rejected*. That each port really listens is shown by the allowed paths: the test client reaches the same leader IP on 5432, the API proxy and Prometheus reach 8008 and 9187, the backup Job reaches 8432, the members reach Garage 3900 (archiving) and the bootstrap Job reaches 3903.

| Source | Destination | Expected | Got |
|---|---|---|---|
| outsider | 10.43.0.10:53 | open | open |
| outsider | 10.42.4.9:5432 | blocked | blocked (rejected, rc=1) |
| outsider | pg-rw.pg-ha.svc.cluster.local:5432 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.4.9:8008 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.4.9:8432 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.4.9:9187 | blocked | blocked (rejected, rc=1) |
| outsider | garage.pg-ha.svc.cluster.local:3900 | blocked | blocked (rejected, rc=1) |
| outsider | 10.42.0.52:3903 | blocked | blocked (rejected, rc=1) |
| outsider | prometheus.monitoring.svc.cluster.local:9090 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | pg-rw.pg-ha.svc.cluster.local:5432 | open | open |
| test client (pg-ha, db-client) | 10.42.4.9:8008 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | 10.42.4.9:8432 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | 10.42.0.52:3900 | blocked | blocked (rejected, rc=1) |
| test client (pg-ha, db-client) | kubernetes.default.svc.cluster.local:443 | blocked | blocked (rejected, rc=1) |

Allowed paths still work under the policies:

```console
$ patroni_cluster | jq -r '.members[] | "\(.name) \(.role) \(.state)"'
pg-0 sync_standby streaming
pg-1 leader running
pg-2 replica streaming
```

```console
$ lock; echo; date -u +%FT%TZ
pg-1 2026-11-26T16:28:57.842092+00:00 2026-11-26T16:08:47.746661+00:00
2026-11-26T16:29:00Z
```

```console
$ jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health) lastScrape=\(.lastScrape)"' <<<'{"status":"success","data":{"activeTargets":[{"discoveredLabels":{"__address__":"alertmanager.monitoring.svc:9093","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"alertmanager"},"labels":{"instance":"alertmanager.monitoring.svc:9093","job":"alertmanager"},"scrapePool":"alertmanager","scrapeUrl":"http://alertmanager.monitoring.svc:9093/metrics","globalUrl":"http://alertmanager.monitoring.svc:9093/metrics","lastError":"","lastScrape":"2026-11-26T16:28:58.579087177Z","lastScrapeDuration":0.006265252,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"kube-state-metrics.monitoring.svc:8080","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"kube-state-metrics"},"labels":{"instance":"kube-state-metrics.monitoring.svc:8080","job":"kube-state-metrics"},"scrapePool":"kube-state-metrics","scrapeUrl":"http://kube-state-metrics.monitoring.svc:8080/metrics","globalUrl":"http://kube-state-metrics.monitoring.svc:8080/metrics","lastError":"","lastScrape":"2026-11-26T16:28:57.249988214Z","lastScrapeDuration":0.001763869,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"kube-state-metrics.monitoring.svc:8081","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"kube-state-metrics-self"},"labels":{"instance":"kube-state-metrics.monitoring.svc:8081","job":"kube-state-metrics-self"},"scrapePool":"kube-state-metrics-self","scrapeUrl":"http://kube-state-metrics.monitoring.svc:8081/metrics","globalUrl":"http://kube-state-metrics.monitoring.svc:8081/metrics","lastError":"","lastScrape":"2026-11-26T16:28:56.018881714Z","lastScrapeDuration":0.003419638,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.19:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://2b1c9cd5e3b09d6d58ad389479218eecbf4bdbc7f25fad3df0e69561e5c5fad2","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.1.19","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-bq2t2","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"d318e7bf-bd75-449e-812a-49fb9dec62d6","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-2","job":"node","node":"k3d-pg-ha-agent-2"},"scrapePool":"node","scrapeUrl":"http://10.42.1.19:9100/metrics","globalUrl":"http://10.42.1.19:9100/metrics","lastError":"","lastScrape":"2026-11-26T16:28:51.050274092Z","lastScrapeDuration":0.006198523,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.0.10:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://ba676da946ec6ea0283edca555c256142f87afe2451158f98104f7345713dff1","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.2","__meta_kubernetes_pod_ip":"10.42.0.10","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-2pxcd","__meta_kubernetes_pod_node_name":"k3d-pg-ha-server-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"a354930a-b6e0-4b3a-b3b5-808a62bd6281","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-server-0","job":"node","node":"k3d-pg-ha-server-0"},"scrapePool":"node","scrapeUrl":"http://10.42.0.10:9100/metrics","globalUrl":"http://10.42.0.10:9100/metrics","lastError":"","lastScrape":"2026-11-26T16:28:59.889363858Z","lastScrapeDuration":0.006470392,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.2.33:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://cfd62b8cf25307d9e00400f5b8e7b0efd778356a761ab79e15daa68242ce9984","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.2.33","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-5w9t4","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"cf84ae1e-cdd6-4a01-a820-77afc4524801","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-0","job":"node","node":"k3d-pg-ha-agent-0"},"scrapePool":"node","scrapeUrl":"http://10.42.2.33:9100/metrics","globalUrl":"http://10.42.2.33:9100/metrics","lastError":"","lastScrape":"2026-11-26T16:28:54.703896554Z","lastScrapeDuration":0.008792323,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.7:9100","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"monitoring-host","__meta_kubernetes_pod_container_id":"containerd://454380af63decced8a37bc4cbcfe0986cf4191a55f407071e1f42ac235cf90db","__meta_kubernetes_pod_container_image":"prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"node-exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9100","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"DaemonSet","__meta_kubernetes_pod_controller_name":"node-exporter","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.4.7","__meta_kubernetes_pod_label_app_kubernetes_io_name":"node-exporter","__meta_kubernetes_pod_label_controller_revision_hash":"68d77c497d","__meta_kubernetes_pod_label_pod_template_generation":"1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_pod_template_generation":"true","__meta_kubernetes_pod_name":"node-exporter-7zp8p","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"48f2ea67-c07a-48c8-ade8-76fee7d655f2","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"node"},"labels":{"instance":"k3d-pg-ha-agent-1","job":"node","node":"k3d-pg-ha-agent-1"},"scrapePool":"node","scrapeUrl":"http://10.42.4.7:9100/metrics","globalUrl":"http://10.42.4.7:9100/metrics","lastError":"","lastScrape":"2026-11-26T16:28:52.30441549Z","lastScrapeDuration":0.006380881,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.2.32:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-0.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.2.32:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"replay_lsn\":3338665984,\"receive_lsn\":3338665984,\"replication_state\":\"streaming\",\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://422b0371336bd9594e2e7a8182a3d9c0ccbce18064c42db5e8df5f0b82315fd0","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.2.32","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"0","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-0","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-0","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"ae715581-f4b7-48aa-bd15-d4cbfe8cd9d6","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-0","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-0","pod":"pg-0"},"scrapePool":"patroni","scrapeUrl":"http://10.42.2.32:8008/metrics","globalUrl":"http://10.42.2.32:8008/metrics","lastError":"","lastScrape":"2026-11-26T16:28:57.975531284Z","lastScrapeDuration":0.006314424,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.18:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-2.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.1.18:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"replay_lsn\":3338665984,\"receive_lsn\":3338665984,\"replication_state\":\"streaming\",\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://089f30eb2b36b88d3752ad92a292b62525a6591c25999bf2d78affae380e8369","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.1.18","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"2","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-2","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-2","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"3dc2c26f-c86c-4a72-aa16-51c76b5fcc93","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-2","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-2","pod":"pg-2"},"scrapePool":"patroni","scrapeUrl":"http://10.42.1.18:8008/metrics","globalUrl":"http://10.42.1.18:8008/metrics","lastError":"","lastScrape":"2026-11-26T16:28:51.950124656Z","lastScrapeDuration":0.003775438,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.9:8008","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-1.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.4.9:8008/patroni\",\"state\":\"running\",\"role\":\"primary\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://2098080885fc2323fba8f0455ddc54e2f5621093ed474aabd6883eb20b345e83","__meta_kubernetes_pod_container_image":"pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"postgres","__meta_kubernetes_pod_container_port_name":"patroni","__meta_kubernetes_pod_container_port_number":"8008","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.4.9","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"1","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"primary","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-1","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"f9be0d95-61e9-4a92-80e7-760c3194d387","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"patroni"},"labels":{"instance":"pg-1","job":"patroni","namespace":"pg-ha","node":"k3d-pg-ha-agent-1","pod":"pg-1"},"scrapePool":"patroni","scrapeUrl":"http://10.42.4.9:8008/metrics","globalUrl":"http://10.42.4.9:8008/metrics","lastError":"","lastScrape":"2026-11-26T16:29:00.489896481Z","lastScrapeDuration":0.005436437,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.4.9:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-1.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.4.9:8008/patroni\",\"state\":\"running\",\"role\":\"primary\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://2186a7a52fed68fa5a98355ea198e47bef0921a6c4a08d2efd5f2bdaa11a2e28","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.4","__meta_kubernetes_pod_ip":"10.42.4.9","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"1","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"primary","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-1","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-1","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-1","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"f9be0d95-61e9-4a92-80e7-760c3194d387","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-1","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-1","pod":"pg-1"},"scrapePool":"postgres","scrapeUrl":"http://10.42.4.9:9187/metrics","globalUrl":"http://10.42.4.9:9187/metrics","lastError":"","lastScrape":"2026-11-26T16:28:55.921349941Z","lastScrapeDuration":0.065451886,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.2.32:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-0.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.2.32:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"replay_lsn\":3338665984,\"receive_lsn\":3338665984,\"replication_state\":\"streaming\",\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://e51e3d88217268ff5dcde98a24199ec85e12b3909b2eedff3ad50699de403ec9","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.3","__meta_kubernetes_pod_ip":"10.42.2.32","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"0","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-0","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-0","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-0","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"ae715581-f4b7-48aa-bd15-d4cbfe8cd9d6","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-0","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-0","pod":"pg-0"},"scrapePool":"postgres","scrapeUrl":"http://10.42.2.32:9187/metrics","globalUrl":"http://10.42.2.32:9187/metrics","lastError":"","lastScrape":"2026-11-26T16:28:55.809680851Z","lastScrapeDuration":0.067172152,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"10.42.1.18:9187","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__meta_kubernetes_namespace":"pg-ha","__meta_kubernetes_pod_annotation_status":"{\"conn_url\":\"postgres://pg-2.pg-headless.pg-ha.svc.cluster.local:5432/postgres\",\"api_url\":\"http://10.42.1.18:8008/patroni\",\"state\":\"running\",\"role\":\"replica\",\"version\":\"4.1.5\",\"xlog_location\":3338665984,\"replay_lsn\":3338665984,\"receive_lsn\":3338665984,\"replication_state\":\"streaming\",\"timeline\":24}","__meta_kubernetes_pod_annotationpresent_status":"true","__meta_kubernetes_pod_container_id":"containerd://9f7ded3ade38d89b81e31ee06f5f3090fd33069adecdcfff5b4c456982692947","__meta_kubernetes_pod_container_image":"quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e","__meta_kubernetes_pod_container_init":"false","__meta_kubernetes_pod_container_name":"exporter","__meta_kubernetes_pod_container_port_name":"metrics","__meta_kubernetes_pod_container_port_number":"9187","__meta_kubernetes_pod_container_port_protocol":"TCP","__meta_kubernetes_pod_controller_kind":"StatefulSet","__meta_kubernetes_pod_controller_name":"pg","__meta_kubernetes_pod_host_ip":"172.18.0.5","__meta_kubernetes_pod_ip":"10.42.1.18","__meta_kubernetes_pod_label_app_kubernetes_io_name":"pg","__meta_kubernetes_pod_label_apps_kubernetes_io_pod_index":"2","__meta_kubernetes_pod_label_cluster_name":"pg-rw","__meta_kubernetes_pod_label_controller_revision_hash":"pg-5b46b9dd5c","__meta_kubernetes_pod_label_role":"replica","__meta_kubernetes_pod_label_statefulset_kubernetes_io_pod_name":"pg-2","__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name":"true","__meta_kubernetes_pod_labelpresent_apps_kubernetes_io_pod_index":"true","__meta_kubernetes_pod_labelpresent_cluster_name":"true","__meta_kubernetes_pod_labelpresent_controller_revision_hash":"true","__meta_kubernetes_pod_labelpresent_role":"true","__meta_kubernetes_pod_labelpresent_statefulset_kubernetes_io_pod_name":"true","__meta_kubernetes_pod_name":"pg-2","__meta_kubernetes_pod_node_name":"k3d-pg-ha-agent-2","__meta_kubernetes_pod_phase":"Running","__meta_kubernetes_pod_ready":"true","__meta_kubernetes_pod_uid":"3dc2c26f-c86c-4a72-aa16-51c76b5fcc93","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"postgres"},"labels":{"instance":"pg-2","job":"postgres","namespace":"pg-ha","node":"k3d-pg-ha-agent-2","pod":"pg-2"},"scrapePool":"postgres","scrapeUrl":"http://10.42.1.18:9187/metrics","globalUrl":"http://10.42.1.18:9187/metrics","lastError":"","lastScrape":"2026-11-26T16:28:57.916548278Z","lastScrapeDuration":0.113693726,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"},{"discoveredLabels":{"__address__":"localhost:9090","__always_scrape_classic_histograms__":"false","__convert_classic_histograms_to_nhcb__":"false","__metrics_path__":"/metrics","__scheme__":"http","__scrape_interval__":"10s","__scrape_native_histograms__":"false","__scrape_timeout__":"5s","job":"prometheus"},"labels":{"instance":"localhost:9090","job":"prometheus"},"scrapePool":"prometheus","scrapeUrl":"http://localhost:9090/metrics","globalUrl":"http://prometheus-6fd6845ff8-96lvc:9090/metrics","lastError":"","lastScrape":"2026-11-26T16:28:54.263457657Z","lastScrapeDuration":0.009777818,"health":"up","scrapeInterval":"10s","scrapeTimeout":"5s"}],"droppedTargets":[],"droppedTargetCounts":null}}' | sort
alertmanager alertmanager.monitoring.svc:9093 up lastScrape=2026-11-26T16:28:58.579087177Z
kube-state-metrics kube-state-metrics.monitoring.svc:8080 up lastScrape=2026-11-26T16:28:57.249988214Z
kube-state-metrics-self kube-state-metrics.monitoring.svc:8081 up lastScrape=2026-11-26T16:28:56.018881714Z
node k3d-pg-ha-agent-0 up lastScrape=2026-11-26T16:28:54.703896554Z
node k3d-pg-ha-agent-1 up lastScrape=2026-11-26T16:28:52.30441549Z
node k3d-pg-ha-agent-2 up lastScrape=2026-11-26T16:28:51.050274092Z
node k3d-pg-ha-server-0 up lastScrape=2026-11-26T16:28:59.889363858Z
patroni pg-0 up lastScrape=2026-11-26T16:28:57.975531284Z
patroni pg-1 up lastScrape=2026-11-26T16:29:00.489896481Z
patroni pg-2 up lastScrape=2026-11-26T16:28:51.950124656Z
postgres pg-0 up lastScrape=2026-11-26T16:28:55.809680851Z
postgres pg-1 up lastScrape=2026-11-26T16:28:55.921349941Z
postgres pg-2 up lastScrape=2026-11-26T16:28:57.916548278Z
prometheus localhost:9090 up lastScrape=2026-11-26T16:28:54.263457657Z
```

```console
$ kubectl get --raw '/api/v1/namespaces/monitoring/services/alertmanager:9093/proxy/api/v2/status' | jq -r '.cluster.status, .versionInfo.version'
disabled
0.34.2
```

```console
$ JOB_WAIT=300 /home/shibshankarbose71/pg-ha-k8s/scripts/pgbr-job.sh pg-check-l6 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -E 'check command end|CHECK_OK'
2026-11-26 16:29:03.948 P00   INFO: check command end: completed successfully (1724ms)
CHECK_OK
```

```console
$ cx app 'host=pg-rw.pg-ha.svc.cluster.local user=app dbname=app sslmode=require' "select 'dns+5432 ok from ' || host(inet_server_addr())"
dns+5432 ok from 10.42.4.9
```

## Patroni REST API authentication

Reached over `kubectl port-forward` to the leader, as the switchover harness does. The credential is read from `./secrets` and handed to curl on stdin, never on a command line. Every unauthenticated request is chosen to be harmless even if auth were missing: a switchover and a restart scheduled a day ahead, an empty config patch, and a reinitialize sent to the leader (which Patroni refuses anyway).

```console
$ rest GET /cluster none | cut -c1-60
HTTP 200 {"members": [{"name": "pg-0", "role": "sync_standby
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
$ rest POST /switchover none '{"leader": "pg-1", "candidate": "pg-0", "scheduled_at": "2026-11-27T16:29:10+00:00"}'
HTTP 401 no auth header received
```

```console
$ rest POST /switchover bad '{"leader": "pg-1", "candidate": "pg-0", "scheduled_at": "2026-11-27T16:29:10+00:00"}'
HTTP 401 not authenticated
```

```console
$ rest POST /restart none '{"schedule": "2026-11-27T16:29:10+00:00"}'
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
$ rest POST /switchover good '{"leader": "pg-1", "candidate": "pg-0", "scheduled_at": "2026-11-27T16:29:10+00:00"}'
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
NAME              STATUS   AGE    ENFORCE      WARN         AUDIT
pg-ha             Active   103m   restricted   restricted   restricted
monitoring        Active   100m   restricted                
monitoring-host   Active   100m   privileged   restricted   restricted
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
garage-bootstrap-rk6lf/bootstrap nonRoot=true uid=100 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
garage-c8cd6c48d-lcdbs/garage nonRoot=true uid=10001 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-0/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-1/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/postgres nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/pgbackrest nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-2/exporter nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-backup-29928460-s54gl/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-check-l6-xfc4j/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-restore-test-29928480-bh4j6/restore-test nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-stanza-create-jmdwp/backup nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
pg-test-client/client nonRoot=true uid=999 seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false
```

```console
$ kubectl get pods -n monitoring -o json | jq -r '.items[] | .metadata.name as $p | .spec.securityContext as $s | .spec.containers[] | "\($p)/\(.name) nonRoot=\($s.runAsNonRoot) seccomp=\($s.seccompProfile.type) escalation=\(.securityContext.allowPrivilegeEscalation) drop=\(.securityContext.capabilities.drop | join(",")) roRootFS=\(.securityContext.readOnlyRootFilesystem)"'
alertmanager-7bfd9ccc56-72zvg/alertmanager nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
kube-state-metrics-745cf745bf-mj29z/kube-state-metrics nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
prometheus-6fd6845ff8-96lvc/prometheus nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true
```

## T:rbac: ServiceAccounts and kubectl auth can-i (R8.8)

```console
$ kubectl get sa -n pg-ha; kubectl get sa -n monitoring; kubectl get sa -n monitoring-host
NAME      AGE
default   103m
pg        102m
NAME                 AGE
default              100m
kube-state-metrics   100m
prometheus           100m
NAME      AGE
default   100m
```

```console
$ kubectl get roles,rolebindings -n pg-ha -o wide; kubectl get roles,rolebindings -n monitoring-host -o wide; kubectl get roles,rolebindings -n kube-system -o wide | grep -E '^NAME|kube-state-metrics'
NAME                                                CREATED AT
role.rbac.authorization.k8s.io/kube-state-metrics   2026-11-26T14:48:33Z
role.rbac.authorization.k8s.io/pg-patroni           2026-11-26T14:46:27Z
role.rbac.authorization.k8s.io/prometheus-sd        2026-11-26T14:48:33Z

NAME                                                       ROLE                      AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/kube-state-metrics   Role/kube-state-metrics   100m                    monitoring/kube-state-metrics
rolebinding.rbac.authorization.k8s.io/pg-patroni           Role/pg-patroni           102m                    pg-ha/pg
rolebinding.rbac.authorization.k8s.io/prometheus-sd        Role/prometheus-sd        100m                    monitoring/prometheus
NAME                                           CREATED AT
role.rbac.authorization.k8s.io/prometheus-sd   2026-11-26T14:48:33Z

NAME                                                  ROLE                 AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/prometheus-sd   Role/prometheus-sd   100m                    monitoring/prometheus
NAME                                                                            CREATED AT
role.rbac.authorization.k8s.io/kube-state-metrics                               2026-11-26T14:48:33Z
NAME                                                                                       ROLE                                                  AGE    USERS                                                   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/kube-state-metrics                                   Role/kube-state-metrics                               100m                                                                    monitoring/kube-state-metrics
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
$ grep -cE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' '/tmp/tmp.SIjzmXTjS8/tmp.bEQoMtKT8N' || true
0
```
