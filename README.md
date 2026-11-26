# PostgreSQL HA on Kubernetes, without operators

A three-member PostgreSQL 17 cluster on a local k3d Kubernetes cluster, made highly available by Patroni with the Kubernetes API as its consensus store. Everything is built from our own manifests and scripts: no operators, no third-party Helm charts, no prebuilt HA images and no managed services. One synchronous and one asynchronous standby give automatic failover with zero data loss for acknowledged commits. pgBackRest archives WAL and takes encrypted backups into in-cluster S3 storage (Garage), with tested full restore and point-in-time recovery. Prometheus and Alertmanager watch it with 19 unit-tested alerts, and TLS, SCRAM, NetworkPolicies, Pod Security and RBAC form the security baseline. Every claim below comes from a `make` target that a reviewer can rerun.

## Architecture

```text
 Host VM (Linux x86-64, Docker)                              ./secrets (generated, git-ignored)
 └── k3d cluster "pg-ha"  (k3s v1.35, all images pinned by digest)
     │
     ├── server-0 (tainted: no Postgres; "infra" role)
     │     API server + datastore  ◄── Patroni leader lock (DCS), Endpoints for pg-rw
     │     CoreDNS (pinned here)    Prometheus · Alertmanager · kube-state-metrics
     │     Garage (S3, single node) ◄── pgBackRest: async WAL archive, scheduled full
     │                                  backups + verify, scheduled restore test (CronJobs)
     │
     ├── agent-0 ─────────────┐  ├── agent-1 ─────────────┐  ├── agent-2 ─────────────┐
     │   pg-0                 │  │   pg-1                 │  │   pg-2                 │
     │   Patroni + Postgres 17│  │   Patroni + Postgres 17│  │   Patroni + Postgres 17│
     │   postgres_exporter    │  │   postgres_exporter    │  │   postgres_exporter    │
     │   PVC (local-path)     │  │   PVC (local-path)     │  │   PVC (local-path)     │
     │   node_exporter        │  │   node_exporter        │  │   node_exporter        │
     └────────────────────────┘  └────────────────────────┘  └────────────────────────┘
            PRIMARY  ──── TLS streaming ────►  SYNC standby
                     ──── TLS streaming ────►  ASYNC standby
 Clients ──► Service pg-rw (Endpoints written by Patroni → current primary)
         ──► Service pg-ro (selector role=replica → streaming standbys)
```

Design decisions are in the ADRs below. The short version: one tainted server and three agents (ADR-001), Patroni on the Kubernetes API (ADR-002), our own image from `postgres:17.12` plus PGDG Patroni and pgBackRest packages (ADR-003), `synchronous_mode` with one sync standby (ADR-004), a diverged old primary rejoins by re-clone, not `pg_rewind` (ADR-008).

## Prerequisites

- Linux x86-64 with Docker, at least 4 vCPU, 14 GB RAM (8 GB free) and 20 GB free disk (reference machine D7: 4 vCPU, 16 GB).
- `make`, `git`, `curl`, `openssl`, `sha256sum`, `jq`, `ss` on the host. `make preflight` checks all of this and changes nothing.
- No cloud account and no credentials. `kubectl` and `k3d` are downloaded into `./bin` by `make tools`, checksum-verified. System tools are not changed.

## Quick start

```bash
make preflight    # read-only host checks
make tools        # pinned kubectl and k3d into ./bin
make secrets      # generate credentials into ./secrets (never overwrites)
make up           # certs, cluster, image, Garage, Patroni, backups, NetworkPolicies, monitoring
make seed         # ~150 MB synthetic pgbench dataset through pg-rw
make status       # members, roles, lag, sync standby
```

`make up` runs `preflight`, `tools`, `certs` and `secrets` itself, so `make up && make seed` is enough. It takes about 5 to 8 minutes. `scripts/` uses `./bin` and the cluster's own kubeconfig in `.run/`, so it never touches your default kube context.

## Make targets and what they prove

| Target | What it does or proves | Requirements |
|---|---|---|
| `make preflight` | Host has the tools, CPU, RAM and disk | R7 |
| `make tools` | Pinned, checksum-verified kubectl and k3d in `./bin` | R7, HC19 |
| `make certs` / `make secrets` | CA and TLS certs, random credentials, in `./secrets`, never overwritten | R8.2, R8.4 |
| `make up` | Full bootstrap from nothing | R12.2 |
| `make seed` | Loads the ~150 MB dataset | D8 |
| `make status` | Nodes, members, roles, lag, sync standby | R6.1 |
| `make test-replication` | 1 primary, 2 streaming replicas (1 sync), rw/ro endpoints, lag in bytes and seconds, slots, rejoin | R1, R2 |
| `make failover-pod` | Primary pod deleted, 3 runs, RTO and RPO | R3 |
| `make failover-node` | Primary's node (agent container) stopped, 3 runs | R3, R9 |
| `make failover-storage` | Primary's data volume read-only, 3 runs | R3, R9 |
| `make test-split-brain` | Primary cut off from the API server only: it demotes, never two primaries | R3.5, ADR-006 |
| `make switchover` | Planned switchover with REST API auth, RTO measured | R6.3 |
| `make failover-chain` | Node failover, then switchover back; archiving stays healthy | ADR-008 |
| `make failover-diverge` | Forced divergence; old primary re-cloned, then made primary again | ADR-008 |
| `make test-failover` | All of the L2 modes above | R3 |
| `make test-api-outage` | Optional: API server stopped 60 s; writes stop, reads continue | ADR-002 |
| `make backup` | On-demand full backup, expire, verify | R4 |
| `make test-backup` | Archiving, scheduled backup from the CronJob, retention, backup after failover, Garage restart | R4 |
| `make restore` / `make restore-clean` | Restore the whole cluster into `pg-restore` (optionally to `TARGET_TIME`), then remove it | R5 |
| `make test-l4` | Full restore with row counts and checksums, PITR, on-demand and scheduled restore test | R4.5, R5 |
| `make monitoring` | Prometheus, Alertmanager, exporters; waits until all targets are up | R10.1 |
| `make test-alerts` | promtool check and unit tests: every alert fires and stays silent when it should | R10.2 |
| `make test-metrics` | Targets up, key series present, induced lag rises and recovers, alert fires and resolves | R10.1, R1.7 |
| `make alerts-failover` / `make alerts-archive` | Live alerts fire on a node failover and an object-storage outage, then resolve | R10.3 |
| `make test-l5` | All of the L5 targets | R10 |
| `make alerts` | List firing alerts | R10 |
| `make test-security` | TLS, SCRAM, roles, NetworkPolicy, REST API auth, Pod Security, RBAC, git credential scan | R8 |
| `make prometheus-ui` / `make alertmanager-ui` | Port-forward the UIs | R10 |
| `make spikes` | L0 risk spikes S1 to S4 | L0 |
| `make down` | Delete this project's cluster, keep `./secrets` | R12.2 |
| `make clean-secrets` | DANGER: delete `./secrets`, backups become unrecoverable | |

`scripts/l7-clean-run.sh` runs the whole sequence from scratch (`secrets`, `down`, `up`, `seed`, every test) and writes [`docs/evidence/L7-clean-run.md`](docs/evidence/L7-clean-run.md).

## Evidence and headline numbers

All evidence is generated by the `make` targets into `docs/evidence/`, with UTC timestamps. Each phase also has a hand-written `*-history.md` with failures, fixes and decisions.

<!-- HEADLINE-START -->
| Area | Result | Evidence |
|---|---|---|
| Clean run from scratch (26 Nov, 2 h 4 min) | `make up` 311 s. 25 of 27 steps PASS first time, 2 on retry; seed needed a fix; restore-full fails one check on test order. See the [history](docs/evidence/L7-clean-run-history.md) | [`L7-clean-run.md`](docs/evidence/L7-clean-run.md) |
| Replication | PASS | [`L1-replication.md`](docs/evidence/L1-replication.md) |
| RTO, pod deleted | min 3.33 s, median 3.74 s, max 4.34 s (3 runs) | [`L2/pod.md`](docs/evidence/L2/pod.md) |
| RTO, node stopped | min 22.52 s, median 23.27 s, max 26.16 s (3 runs) | [`L2/node.md`](docs/evidence/L2/node.md) |
| RTO, storage read-only | min 3.01 s, median 4.54 s, max 4.65 s (3 runs) | [`L2/storage.md`](docs/evidence/L2/storage.md) |
| RTO, split-brain (API cut) | min 19.56 s, median 20.61 s, max 20.62 s (3 runs) | [`L2/split-brain.md`](docs/evidence/L2/split-brain.md) |
| RTO, planned switchover | min 2.56 s, median 2.60 s, max 2.72 s (3 runs) | [`L2/switchover.md`](docs/evidence/L2/switchover.md) |
| Chain: node failover, then switchover back (3 runs) | failover 23.06 to 25.47 s, switchovers 2.51 to 3.69 s; archiving healthy | [`L2/chain.md`](docs/evidence/L2/chain.md) |
| Diverge: forced divergence, re-clone rejoin, switch back (3 runs) | failover 29.41 to 29.50 s (**within target by only about 0.5 s**), rejoin by re-clone, switchovers 2.46 to 2.67 s | [`L2/diverge.md`](docs/evidence/L2/diverge.md) |
| RPO | 0 acknowledged rows lost in every failover and switchover run | [`L2-failover.md`](docs/evidence/L2-failover.md) |
| Backup | 5 of 5 parts PASS (40 of 40 checks): archiving, scheduled backup, retention, backup after failover, Garage restart | [`L3-backup.md`](docs/evidence/L3-backup.md) |
| Full restore | Restored and healthy in 34.15 s, row counts and checksums match; 9 of 10 checks, the history-file count fails on test order ([known limitation](docs/known-limitations.md)) | [`L4/restore-full.md`](docs/evidence/L4/restore-full.md) |
| PITR | Restored to T in 32.49 s; marker before T present, marker after T absent (7 of 7) | [`L4/pitr.md`](docs/evidence/L4/pitr.md) |
| Restore test Job | On demand and scheduled PASS; fingerprints match, pg_amcheck clean, an injected mismatch fails the Job | [`L4-restore.md`](docs/evidence/L4-restore.md) |
| Alerts | 19 rules, each with a firing and a silent unit test; 59 of 59 L5 checks PASS, including live firing and resolving on lag, node failover and object-storage outage (two passed on retry) | [`L5-monitoring.md`](docs/evidence/L5-monitoring.md) |
| Security | 102 of 102 checks PASS | [`L6-security.md`](docs/evidence/L6-security.md) |
<!-- HEADLINE-END -->

RTO is measured from fault injection to the first commit acknowledged by the new primary, by a probe writing through `pg-rw` every 500 ms. The target is at most 30 s with safe Patroni settings (ttl 20, loop_wait 3, retry_timeout 5). A run over 30 s is reported as OVER TARGET, never tuned away.

## Teardown

```bash
make down            # deletes only the k3d cluster "pg-ha"; ./secrets stays, so `make up` reuses it
make clean-secrets   # optional and destructive: the encrypted backups can no longer be read
```

## Documentation

- Requirements and acceptance criteria: [`docs/00-requirements.md`](docs/00-requirements.md). Design options: [`docs/01-design-options.md`](docs/01-design-options.md). Host facts: [`docs/environment.md`](docs/environment.md).
- Decisions: [ADR-001 topology](docs/decisions/ADR-001-cluster-topology.md), [ADR-002 HA manager](docs/decisions/ADR-002-ha-manager-leader-election.md), [ADR-003 image](docs/decisions/ADR-003-postgres-image.md), [ADR-004 replication mode](docs/decisions/ADR-004-replication-mode.md), [ADR-005 slots](docs/decisions/ADR-005-slots-disk-protection.md), [ADR-006 fencing](docs/decisions/ADR-006-fencing-timing.md), [ADR-007 endpoints](docs/decisions/ADR-007-client-endpoints.md), [ADR-008 rejoin](docs/decisions/ADR-008-old-primary-rejoin.md), [ADR-009 backups](docs/decisions/ADR-009-backups.md), [ADR-010 restore](docs/decisions/ADR-010-restore-pitr.md), [ADR-011 observability](docs/decisions/ADR-011-observability.md), [ADR-012 security](docs/decisions/ADR-012-security-baseline.md), [ADR-013 packaging](docs/decisions/ADR-013-packaging-entry-point.md), [ADR-014 object storage](docs/decisions/ADR-014-object-storage.md).
- Runbooks: [switchover](docs/runbooks/switchover.md), [restore](docs/runbooks/restore.md), [PITR](docs/runbooks/pitr.md), [minor upgrade](docs/runbooks/minor-upgrade.md) (documented only).
- [Security](docs/security.md), [observability](docs/observability.md), [known limitations](docs/known-limitations.md).
- How the work was done with AI: [`docs/ai-process/`](docs/ai-process/README.md). Working rules: [`docs/process/working-rules.md`](docs/process/working-rules.md). Redactions: [`docs/process/redaction-log.md`](docs/process/redaction-log.md).
