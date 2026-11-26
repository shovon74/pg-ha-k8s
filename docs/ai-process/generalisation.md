# Generalising the playbook

How the same method would build another HA system on Kubernetes without operators (R11.5). Two examples: **Redis with Sentinel** and **HashiCorp Vault with integrated Raft storage**.

## What carries over

The method (requirements with IDs, lead decisions, options, ADRs, lean plan, phases with gates, evidence by `make`) is unchanged. So is most of the scaffolding: pinned tools, the k3d cluster, secret generation, the evidence format, and the log export.

## Files reused unchanged or rewritten

| File or area | Redis + Sentinel | Vault + Raft | Note |
|---|---|---|---|
| `docs/process/working-rules.md` | Unchanged | Unchanged | Tool- and domain-independent |
| `CLAUDE.md` (or another agent's context file) | Small edit | Small edit | Goal line and constraints only |
| `docs/00-requirements.md` structure, D-list format | Reused | Reused | Content rewritten from the new brief |
| `docs/decisions/` ADR template | Reused | Reused | ADRs rewritten |
| `docs/ai-process/*` | Reused | Reused | Phase table updated |
| `versions.env` format, `scripts/tools.sh`, `scripts/preflight.sh` | Unchanged | Unchanged | Only the pinned values change |
| `scripts/cluster.sh`, `deploy/k3d/` (1 server + 3 agents) | Unchanged | Unchanged | Same topology fits 3 Sentinels or 3 Raft voters |
| `scripts/lib.sh`, `scripts/down.sh`, `scripts/clean-secrets.sh` | Small edit | Small edit | Names and namespaces |
| `scripts/certs.sh` (CA and TLS) | Unchanged | Unchanged | Same CA, new server certificate names |
| `scripts/secrets.sh` | Small edit | Small edit | Different credential names |
| `scripts/image.sh`, `docker/postgres/` | Rewritten | Rewritten | Official `redis` or `hashicorp/vault` image, pinned by digest |
| `deploy/pg/` (StatefulSet, Patroni config, Services) | Rewritten | Rewritten | Redis + Sentinel StatefulSets; Vault StatefulSet with `retry_join` |
| Client endpoints (ADR-007 pattern) | Rewritten | Mostly reused | Sentinel-aware clients, or a Service updated on failover; Vault's leader label in a Service selector |
| `tests/failover.sh` harness (fault injection, probe, RTO/RPO, 3 runs) | Mostly reused | Mostly reused | Fault injection unchanged; the probe and leader query change |
| `tests/lib.sh`, `tests/l*-summary.sh` evidence writers | Unchanged | Unchanged | Generic check and table helpers |
| Backup and restore (`pgBackRest`, Garage, L3/L4 tests) | Rewritten | Rewritten | RDB/AOF snapshots to Garage; `vault operator raft snapshot` to Garage. Garage manifests reused unchanged |
| `deploy/garage/`, `scripts/garage.sh` | Unchanged | Unchanged | Same S3 store |
| `deploy/monitoring/` (Prometheus, Alertmanager, kube-state-metrics, node_exporter) | Unchanged | Unchanged | New scrape job only |
| Alert rules and unit tests | Rewritten | Rewritten | Same structure (firing and silent test per alert) |
| `deploy/netpol/`, `scripts/netpol.sh` | Small edit | Small edit | Ports and labels |
| `tests/test-security.sh` | Partly reused | Partly reused | Pod Security, RBAC and git-scan checks reused; protocol checks rewritten |
| `scripts/export-logs.sh` | Unchanged | Unchanged | Same redaction and secret scan |
| `scripts/l7-clean-run.sh` | Small edit | Small edit | Target list |

## Domain points that change the design

- **Redis + Sentinel.** Replication is asynchronous, so RPO is not zero. State it and measure it as here. `min-replicas-to-write` limits loss during a partition. Sentinel quorum (3) replaces the Kubernetes API as the decider, so the split-brain test cuts a master off from the Sentinels instead of from the API server.
- **Vault + Raft.** Raft gives consensus inside Vault, so no external DCS is needed. Failover is leader election among voters, and RPO is zero for committed writes. New concerns: unsealing after every restart (auto-unseal needs a KMS and so a cloud credential, or manual unseal keys that must never enter logs or prompts), and snapshot restore as the backup path.
