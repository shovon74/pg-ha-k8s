Phase 1: Design. Read CLAUDE.md, docs/00-requirements.md (including Assumptions & decisions
D1-D9) and docs/environment.md first.

Before anything else, save this prompt verbatim to docs/process/prompts/p1-design-options.md.
I'll run the same prompt through Gemini later for a comparison, so it must be portable.

Goal of this step: present design OPTIONS for me to decide on. Do not write manifests, code or
ADRs yet. Guiding principle from the brief: the smallest system that meets every MUST and that
I can defend line by line. Flag anything that is nice-to-have.

For each decision below, give 2-3 realistic options. For each option: how it works in one or two
lines, pros, cons, which R-IDs it satisfies or risks, and the effort on our timeline. End each
decision with your recommendation and the single strongest reason. Mark anything you're unsure
of as an assumption.

Decisions:
1. Cluster topology: 1 server + 3 agents in k3d (your recommendation) vs alternatives; how
   Postgres pods are pinned to agents; anti-affinity and topology spread.
2. HA manager and leader election: Patroni with the Kubernetes API as DCS (Endpoints vs
   ConfigMaps/Leases) vs etcd vs repmgr. Include how it behaves if the API server is unreachable.
3. Postgres image: how we build it (official postgres base + Patroni + backup tool), size,
   non-root, and how it's built and loaded into k3d reproducibly.
4. Replication mode: async vs Patroni synchronous_mode (incl. synchronous_mode_strict).
   State the RPO and the availability trade-off for each.
5. Replication slots and disk protection: permanent slots, max_slot_wal_keep_size, alerting.
6. Split-brain prevention and fencing: leader-key TTL / loop_wait / retry_timeout values, demotion
   on lost lock, watchdog availability in containers, and why two primaries can't accept writes.
7. Client endpoints: rw and ro Services (label selectors driven by Patroni vs Patroni-managed
   Endpoints); connection pooling yes/no and why.
8. Old primary rejoin: pg_rewind vs re-clone; what's required (wal_log_hints / data checksums).
9. Backups: pgBackRest vs WAL-G to in-cluster MinIO; base-backup schedule, WAL archiving,
   retention enforcement, automatic verification.
10. Restore and PITR: restoring into an empty namespace; PITR to a timestamp; how the automated
    restore test runs (CronJob vs make target) and what it checks.
11. Observability: postgres_exporter + Prometheus + Alertmanager from our own manifests
    (no operators, no charts per D1/D2); the alert list; Grafana yes/no.
12. Security baseline: secrets generation/handling, SCRAM, TLS (client and replication), default-
    deny NetworkPolicies (k3s enforces them?), Patroni RBAC least privilege, securityContext,
    separate DB roles.
13. Packaging and entry point: raw manifests + Kustomize vs our own Helm chart; Makefile targets
    (preflight, tools, up, down, test-*, failover-*, backup, restore); version pinning in one file
    with project-local ./bin tools.

Also produce:
- A one-paragraph target architecture summary plus a simple ASCII diagram.
- A table mapping every MUST requirement to the decision(s) that cover it; list any MUST
  left uncovered.
- Candidate pinned versions (k3s, kubectl, PostgreSQL, Patroni, backup tool, MinIO, Prometheus,
  Alertmanager, exporter). Verify each version exists before proposing it, or mark it unverified.
- A phase-by-phase build plan with hour estimates, with explicit cut lines if we fall behind.

Write all of this to docs/01-design-options.md, then reply with a concise summary and your 13
recommendations as a numbered list. Stop and wait for my decisions.
