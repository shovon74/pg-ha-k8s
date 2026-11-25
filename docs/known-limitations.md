# Known limitations

This file lists what the system does not protect against or does not implement (R12.5, HC10). Entries are added as each phase confirms them.

## Topology

### Cluster DNS shares the server node's single point of failure

k3s runs one CoreDNS replica, and `make up` pins it to the server node (ADR-001, L3). A failed database node can no longer take DNS down. A server-node outage takes out the API server and DNS together, though. New connections by name (`pg-rw`, `pg-ro`, Garage) then fail, while existing connections and the running primary continue.

- **Why:** a single tainted server is the topology of ADR-001. Running CoreDNS on a database node made a node failure also a DNS failure, which pushed node-failure RTO over 30 s.
- **In production:** run at least two CoreDNS replicas spread across nodes or zones, or use NodeLocal DNSCache, on a control plane with three or more servers.
- **Decision:** ADR-001.

## Backups

### Backup repository is not off-site

The in-cluster Garage repository shares the VM and disk with the database, so it is not off-site disaster protection. In production, the pgBackRest repository points at GCS/S3 with bucket versioning and a retention lock, off-site from the cluster, using keyless workload identity where available.

- **Why it is the default:** `make up` must work for any reviewer with no cloud account or credentials.
- **Planned option:** R4.7 adds `BACKUP_TARGET=gcs make up`. It is OPTIONAL and not built yet.
- **Decision:** ADR-014.

## Monitoring

### No dashboards (R10.4 not met)

There is no Grafana and no dashboard as code. Metrics are viewed in the Prometheus UI (`make prometheus-ui`) and alerts with `make alerts` or the Alertmanager UI.

- **Why:** ADR-011 keeps Grafana out unless every MUST and every other SHOULD is done. It would serve only R10.4.
- **In production:** provision Grafana from code (datasource and dashboard JSON in ConfigMaps) next to Prometheus.
- **Decision:** ADR-011.

### Alerts are not delivered anywhere

Alertmanager routes every alert to a receiver with no integrations, so nobody is notified. Alerts are visible only through its API and UI.

- **Why:** a real receiver (webhook, Slack, email) needs a secret, and the repository is public.
- **In production:** add a receiver whose credential comes from a Secret created at deploy time, and route `critical` alerts to paging.
- **Decision:** ADR-011.

### Monitoring is a single, non-persistent instance on the server node

Prometheus and Alertmanager run as one replica each on the server node, with emptyDir storage (Prometheus keeps 3 days, at most 1 GB). A server-node outage stops alerting, and a pod restart loses metric history and pending alert state. FailoverOccurred compares the timeline with its value 5 minutes earlier, so it cannot fire in the first 5 minutes after Prometheus restarts.

- **Why:** one server node by design (ADR-001). Metrics serve alerting, not history.
- **In production:** two Prometheus replicas with persistent volumes and a clustered Alertmanager, ideally outside the database cluster, plus an external "dead man's switch" alert that pages when Prometheus itself goes silent.
- **Decision:** ADR-011.

### node_exporter runs with a Pod Security exception

node_exporter needs a read-only hostPath mount of the node's root filesystem to report disk space, which `baseline` and `restricted` forbid. It runs alone in the `monitoring-host` namespace, which enforces `privileged` and warns and audits at `restricted`. It runs as non-root with no capabilities, and without hostNetwork or hostPID.

- **Why:** disk space has no other source here. local-path volumes report no volume statistics.
- **Decision:** ADR-011, documented exception for R8.7.
