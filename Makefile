# Entry point for the project (ADR-013). Versions come only from versions.env.
SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help preflight tools certs secrets cluster image up down status clean-secrets \
        deploy backup restore restore-clean test-restore test-restore-full test-pitr test-restore-schedule test-l4 monitoring alerts test-alerts test-metrics alerts-failover alerts-archive test-l5 prometheus-ui alertmanager-ui seed test-replication failover-pod failover-node failover-storage test-split-brain switchover failover-chain failover-diverge test-failover test-api-outage \
        test-archive test-backup-schedule test-retention test-backup-failover test-garage-restart test-backup spike-s1 spike-s2 spike-s3 spike-s4 spikes

help: ## List targets
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t 16

preflight: ## Check host prerequisites
	@scripts/preflight.sh

tools: ## Install checksum-verified kubectl and k3d into ./bin
	@scripts/tools.sh

certs: ## Create the CA and TLS certs in ./secrets (never overwrites)
	@scripts/certs.sh

secrets: ## Generate credentials in ./secrets (never overwrites)
	@scripts/secrets.sh

cluster: tools ## Create the k3d cluster (1 tainted server + 3 agents)
	@scripts/cluster.sh

image: tools ## Build our Postgres image and import it into k3d
	@scripts/image.sh

up: preflight tools certs secrets cluster image deploy monitoring ## Bootstrap everything built so far
	@scripts/status.sh

deploy: ## Deploy Garage + Patroni with archiving, create the stanza (BACKUP_SCHEDULE, default '0 20 * * *')
	@scripts/deploy.sh

backup: ## On-demand full backup, expire and verify, from the pg-backup CronJob template
	@scripts/pgbr-job.sh pg-backup-manual-$$(date -u +%Y%m%d%H%M%S)

restore: ## L4: restore the whole cluster into NS=pg-restore [TARGET_TIME='YYYY-MM-DD HH:MM:SS+06'] [TARGET_TIMELINE=latest]
	@scripts/restore.sh

restore-clean: ## L4: delete only the pg-restore namespace and its PVCs
	@scripts/restore-clean.sh

monitoring: ## L5: Prometheus, Alertmanager, kube-state-metrics, node_exporter; waits until all targets are up
	@scripts/monitoring.sh

alerts: ## L5: list firing alerts from Alertmanager (ALL=1 adds pending ones)
	@scripts/alerts.sh

test-alerts: ## L5 R10.2: promtool check and unit tests for every alert rule (Docker only)
	@scripts/test-alerts.sh

test-metrics: ## L5 R10.1/R1.7: all targets up, key series present, lag in bytes and seconds rises and recovers
	@tests/l5-metrics.sh

alerts-failover: ## L5 R10.3: node failover; MemberDown, ReplicaNotStreaming, FailoverOccurred fire, then resolve
	@tests/l5-alerts-failover.sh

alerts-archive: ## L5 R10.3/R9.6: block the primary's traffic to Garage; archive alerts fire, then resolve and catch up
	@tests/l5-alerts-archive.sh

test-l5: test-alerts test-metrics alerts-failover alerts-archive ## L5 gate: all of the above

prometheus-ui: ## Port-forward the Prometheus UI to http://127.0.0.1:9090 (Ctrl-C to stop)
	@. scripts/lib.sh && kubectl -n monitoring port-forward svc/prometheus 9090:9090

alertmanager-ui: ## Port-forward the Alertmanager UI to http://127.0.0.1:9093 (Ctrl-C to stop)
	@. scripts/lib.sh && kubectl -n monitoring port-forward svc/alertmanager 9093:9093

seed: ## Load a synthetic ~150 MB pgbench dataset through pg-rw (SEED_SCALE=10)
	@scripts/seed.sh

test-replication: ## L1 gate: topology, sync standby, endpoints, lag, slots, replica rejoin
	@tests/test-replication.sh

failover-pod: ## L2: delete the primary pod, 3 runs (RUNS=n)
	@tests/failover.sh pod

failover-node: ## L2: stop the primary's agent container, 3 runs
	@tests/failover.sh node

failover-storage: ## L2: primary's data volume read-only, 3 runs
	@tests/failover.sh storage

test-split-brain: ## L2: cut the primary off from the API server only, 3 runs
	@tests/failover.sh split-brain

switchover: ## Planned switchover to TO=pg-N (default the sync standby), RTO measured
	@tests/failover.sh switchover

failover-chain: ## L2: node failover, then switchover back to the old primary; archiving must stay healthy
	@tests/failover-chain.sh

failover-diverge: ## L2/ADR-008: primary diverges (replication blocked, then node stopped), rejoins by re-clone, switch back
	@tests/failover-chain.sh diverge

test-failover: failover-pod failover-node failover-storage test-split-brain switchover failover-chain failover-diverge ## L2 gate: all modes

test-api-outage: ## L2 optional: stop the k3d server (API) for OUTAGE=60 s
	@tests/api-outage.sh

test-archive: ## L3: Garage, repo.conf, WAL archiving, stanza, make backup with verify
	@tests/l3-archive.sh

test-backup-schedule: ## L3 R4.1: a Job created by the CronJob on a 10-min schedule, then default restored
	@tests/l3-scheduled.sh

test-retention: ## L3: 3 backups with temporary retention 2, oldest expired with its WAL
	@tests/l3-retention.sh

test-backup-failover: ## L3 R4.6: one node failover, then archiving + backup + verify on the new timeline
	@tests/l3-failover.sh

test-garage-restart: ## L3: restart Garage while writing; archiving recovers within a bound
	@tests/l3-garage-restart.sh

test-backup: test-archive test-backup-schedule test-retention test-backup-failover test-garage-restart ## L3 gate: all of the above

test-restore: ## L4 R4.5/R5.4: backup, then the restore-test Job from the CronJob template; plus a negative run
	@tests/l4-restore-test.sh

test-restore-full: ## L4 R5.1: make restore (latest) into pg-restore, row counts and checksums vs the source
	@tests/l4-restore-full.sh

test-pitr: ## L4 R5.3: markers A and B around T, restore to T, A present and B absent
	@tests/l4-pitr.sh

test-restore-schedule: ## L4 R4.5: a restore-test Job created by the CronJob itself, then default restored
	@tests/l4-restore-scheduled.sh

test-l4: test-restore-full test-pitr test-restore test-restore-schedule ## L4 gate: all of the above

status: ## Show nodes, resource use, Patroni members, lag and the sync standby
	@scripts/status.sh

down: ## Delete only this project's cluster; keeps ./secrets
	@scripts/down.sh

clean-secrets: ## DANGER: delete ./secrets; backups become unrecoverable
	@scripts/clean-secrets.sh

spike-s1: ## S1: pgBackRest against Garage
	@scripts/spikes/s1.sh

spike-s2: ## S2: NetworkPolicy enforcement, including API egress
	@scripts/spikes/s2.sh

spike-s3: ## S3: UID 999 creates a 0700 PGDATA on local-path
	@scripts/spikes/s3.sh

spike-s4: ## S4: v1 Endpoints and EndpointSlice mirroring latency
	@scripts/spikes/s4.sh

spikes: spike-s1 spike-s2 spike-s3 spike-s4 ## Run all L0 spikes
