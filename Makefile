# Entry point for the project (ADR-013). Versions come only from versions.env.
SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help preflight tools certs secrets cluster image up down status clean-secrets \
        deploy seed test-replication failover-pod failover-node failover-storage test-split-brain switchover test-api-outage spike-s1 spike-s2 spike-s3 spike-s4 spikes

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

up: preflight tools certs secrets cluster image deploy ## Bootstrap everything built so far
	@scripts/status.sh

deploy: ## Deploy the Patroni cluster and wait until healthy
	@scripts/deploy.sh

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

test-api-outage: ## L2 optional: stop the k3d server (API) for OUTAGE=60 s
	@tests/api-outage.sh

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
