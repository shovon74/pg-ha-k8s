# Project context

**Goal:** A PostgreSQL 15+ HA cluster on Kubernetes, built without operators or turnkey charts, with everything as code and reproducible by a reviewer.

**Timezones:** The VM runs on UTC and the lead works in UTC+6.

**Priorities:** replication and failover, then backup and PITR, then monitoring, then security. The optional second-agent comparison comes next, and the optional GCS backup overlay (R4.7) is the lowest priority.

## Key constraints

- No operators of any kind, third-party Helm charts, prebuilt HA images or managed databases.
- Postgres image is built by us from the official `postgres` image plus Patroni.
- Garage (object storage, see `docs/decisions/ADR-014-object-storage.md`), Prometheus and Alertmanager use our own minimal manifests.
- `kubectl exec` only in committed, automated test or fault-injection scripts, and documented.
- The repository is public. No real credentials in files, chat or logs.
- Work directly on `main`. Do not create branches.
- All versions pinned, no `:latest`. Project tools go in `./bin`, and system tools stay unchanged.
- Automatic failover RTO target is ≤ 30 s. Report the real RTO per failure mode, and never use unsafe tuning to hit the target. RPO is measured and stated. Dataset is about 100–200 MB.
- Session logs stay real. Redact only credentials and personal or cloud identifiers, with visible placeholders and a redaction log.

## Read these

- `docs/process/working-rules.md`: the agent-agnostic working rules, which you must follow.
- `docs/00-requirements.md`: requirements, acceptance criteria and hard constraints.
- `docs/environment.md`: host facts, current blockers and the tool-pinning proposal.
