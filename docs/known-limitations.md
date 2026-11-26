# Known limitations

This file lists what the system does not protect against or does not implement (R12.5, HC10). Entries are added as each phase confirms them.

## Topology

### Cluster DNS shares the server node's single point of failure

k3s runs one CoreDNS replica, and `make up` pins it to the server node (ADR-001, L3). A failed database node can no longer take DNS down. A server-node outage takes out the API server and DNS together, though. New connections by name (`pg-rw`, `pg-ro`, Garage) then fail, while existing connections and the running primary continue.

- **Why:** a single tainted server is the topology of ADR-001. Running CoreDNS on a database node made a node failure also a DNS failure, which pushed node-failure RTO over 30 s.
- **In production:** run at least two CoreDNS replicas spread across nodes or zones, or use NodeLocal DNSCache, on a control plane with three or more servers.
- **Decision:** ADR-001.

### One VM, one kernel, one disk

All four k3d "nodes" are containers on one VM. They share a kernel, a disk, a network stack and a power supply. A node failure is simulated by stopping an agent container (D6). That is close to a sudden power loss of a node, but it cannot show a slow or flapping network, a zone outage, a kernel panic on one node only, or a disk that fails under one node. Replication across "nodes" never crosses a real network, so the measured lag and RTO are best-case for network latency.

- **In production:** three or more real nodes across failure domains (zones), with a pod anti-affinity rule on the zone label.
- **Decision:** ADR-001, D6, D7.

### The API server is a single point of failure for writes

Patroni uses the Kubernetes API as its DCS (ADR-002). There is one server node, so one API server. When it is unreachable the leader cannot renew its lock and demotes, with `failsafe_mode` off. Writes stop for the whole outage plus recovery, while reads continue on all members. Measured: a 60 s outage gave about 86 s without writes. This is the deliberate safe choice: no member can keep writing without a lock.

- **In production:** a control plane with three or more servers (HA etcd), which removes this single point of failure.
- **Decision:** ADR-002, ADR-006.

### The API-outage evidence predates the final rebuild

`make test-api-outage` is OPTIONAL and was last run on 25 Nov at 07:53 UTC (`docs/evidence/L2/api-outage.md`). That is before the L3 change to re-clone rejoin, the pinned CoreDNS and the L6 NetworkPolicies, and it was not part of the L7 clean run, because stopping the server node is the slowest and most disruptive test. Its result is believed to still hold, because none of those changes touch lock handling, but that is not re-proven.

- **To re-prove:** `make test-api-outage` on a running cluster.

## Failure simulation

### Storage faults are simulated, not real

`make failover-storage` makes the primary's data volume read-only, which Postgres sees as I/O errors on write (D6). It does not reproduce a disk that hangs (I/O stuck in uninterruptible sleep), silent corruption, a full disk or a slow disk. A hung disk is the hardest case: Postgres may neither crash nor answer, and Patroni's liveness check would have to detect it. Data checksums are on, so corrupted pages are detected on read, but no corruption was injected. There is no hardware watchdog in containers, so fencing relies on Patroni demoting itself (ADR-006).

- **In production:** a real watchdog device, plus monitoring of I/O latency and disk errors.
- **Decision:** ADR-006, D6.

## Backups

### Backup repository is not off-site

The in-cluster Garage repository shares the VM and disk with the database, so it is not off-site disaster protection. In production, the pgBackRest repository points at GCS/S3 with bucket versioning and a retention lock, off-site from the cluster, using keyless workload identity where available.

- **Why it is the default:** `make up` must work for any reviewer with no cloud account or credentials.
- **Optional overlay not built:** R4.7 (`BACKUP_TARGET=gcs make up`) is OPTIONAL and the lowest priority. It was cut deliberately and is not implemented.
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

## Security

The full lists of what is implemented and what is left out are in [`security.md`](security.md). These are the gaps a reviewer is most likely to ask about.

### Object-storage traffic and the Patroni REST API are not TLS

Garage has no native TLS, so S3 requests cross the pod network in clear. The repository content is encrypted (`aes-256-cbc`) and SigV4 keeps the secret key off the wire, but object names and sizes are visible. Patroni's REST API uses basic auth for state-changing calls over plain HTTP. In both cases, NetworkPolicy limits who can reach the port.

- **In production:** an off-site repository over HTTPS (R4.7), and `restapi` TLS for Patroni.
- **Decision:** ADR-014, ADR-012.

### No secret rotation tooling, and Secrets are not encrypted at rest

Credentials are generated once per deployment. Rotation is a manual file replacement followed by `make deploy` and a role password reset. k3s stores Secrets unencrypted in its datastore on the same VM.

- **In production:** an external secret store with rotation, and KMS envelope encryption for Secrets.
- **Decision:** ADR-012 (layered baseline, not full hardening).

### The restored cluster in `pg-restore` has no NetworkPolicies

`make restore` creates a temporary namespace with a copy of production data and no policies. Pod Security is not enforced there either, because the namespace has no label, although its pods come from the same restricted-compliant manifests. It is deleted by `make restore-clean`.

- **In production:** apply the same rendered policies to the restore namespace, or restore into an isolated cluster.
- **Decision:** L6, `security.md`.

## Operations

### Minor-version upgrade is documented only

[`runbooks/minor-upgrade.md`](runbooks/minor-upgrade.md) describes the procedure (replicas first, one switchover, then the old primary), but no upgrade was executed. R6.4 accepts a documented procedure. The steps it relies on (`make image`, `make deploy`, `make switchover`, rejoin with a restart) are each tested on their own.

## AI process

### The second-agent comparison was cut

R11.6 (run the Phase 1 design-options prompt through a second agent and compare) is OPTIONAL and was cut deliberately to protect the MUST requirements. The prompt is saved verbatim in `docs/process/prompts/p1-design-options.md`, so the comparison can still be run.

### Grafana was cut

See "No dashboards" above. Cut deliberately (ADR-011).

## L7 clean run

Results of the final from-scratch run are in [`evidence/L7-clean-run.md`](evidence/L7-clean-run.md). Anything that failed twice there is listed here.

### `test-restore-full`: history-file check depends on test order

In the L7 run, one of the ten checks failed twice: it expects a history file for every timeline since timeline 2, but the L3 retention test had legitimately expired the older ones (21 failovers happened before the first backup on the fresh cluster). The restore itself passed every other check, including row counts and checksums. The check should only require history files from the oldest retained backup's timeline onward. Not changed tonight. Details: [`evidence/L7-clean-run-history.md`](evidence/L7-clean-run-history.md).

### Seed Job hit the NetworkPolicy admission race

`make seed` failed twice in the L7 run on the same kube-router race as the L6 backup Job, and was fixed with the same `pg_isready` wait. Other one-shot Jobs that connect to Postgres immediately after start were not audited for this race.

### `test-metrics` lag induction is timing-sensitive

In the L7 run the first attempt did not build enough lag to hold `ReplicationLagHigh` for its 2 minutes. The retry passed with large margins. The test throttles for a fixed time instead of until the alert fires, so on a busy host it can fail without anything being wrong with the alert. Details in [`evidence/L7-clean-run-history.md`](evidence/L7-clean-run-history.md).

### `alerts-archive` fault injection did not always block archiving

In the L7 run the first attempt's block of the primary's traffic to Garage leaked: archiving continued (about 31 segments, one failure), so `ArchiveStale` correctly did not fire and the test failed. The retry blocked properly and passed. The cause of the leak was not diagnosed. Details in [`evidence/L7-clean-run-history.md`](evidence/L7-clean-run-history.md).

### Diverge failover RTO has almost no margin

All three `make failover-diverge` runs in L7 measured 29.41 to 29.50 s against the 30 s target. The scenario holds back replication before stopping the node, so this is the worst case of the modes tested. It passes as measured, and the timing settings were not tuned to widen the margin. A slower host could push it over 30 s, which the harness would report as OVER TARGET.

### Other modes in the L7 run

Every other failure mode passed with margin (node 22.5 to 26.2 s, split-brain 19.6 to 20.6 s, pod 3.3 to 4.3 s, storage 3.0 to 4.7 s, switchover 2.6 to 2.7 s), with RPO 0 in every run. Full table: [`evidence/L7-clean-run.md`](evidence/L7-clean-run.md).
