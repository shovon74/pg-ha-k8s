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
