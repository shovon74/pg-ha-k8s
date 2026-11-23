# 00 — Requirements

**Status:** Phase 0, lead review applied
**Source:** `docs/brief.pdf` (6 pages, dated 2026-11-19). `p.N` below is the brief's page number.
**Scope:** This file says *what* must be true and how we will prove it. It deliberately makes no architecture or tooling choice.

## How to read this

| Field | Meaning |
|---|---|
| **Level** | **MUST**: the brief states it as required, or as a scored item that needs a stated outcome. **SHOULD**: not literally required, but our interpretation of "treat this as a production system" (marked *derived*). **OPTIONAL**: the brief calls it optional, or it is a nice-to-have. |
| **Pri** | Build order from the brief's FAQ (p.6): **P1** replication and failover, **P2** backup and PITR, **P3** monitoring and alerting, **P4** security hardening. **P0** is foundation or submission work that every priority depends on. |
| **Acceptance** | A pass/fail check. Thresholds marked † are not from the brief and were approved by the lead. |
| **Evidence** | What we will commit. `T:name` is a logical automated test. Its file path is decided at design time. |

Every `T:` test must exit non-zero on failure and save its timestamped output to the repo's evidence directory.

## Assumptions & decisions

### Lead decisions

These resolve the Phase 0 open questions. The lead made them directly, and they were not confirmed by the recruiter.

| ID | Topic | Decision |
|---|---|---|
| D1 | Operators | No operators of any kind, including for supporting components. |
| D2 | Helm charts | No third-party Helm charts. Garage (object storage, ADR-014), Prometheus, Alertmanager and any other supporting component are deployed from our own minimal manifests, so nothing can be mistaken for a turnkey component. |
| D3 | Postgres image | We build our own image from the official `postgres` image plus Patroni. No Spilo or other prebuilt HA images. |
| D4 | `kubectl exec` | Allowed only inside committed, automated test or fault-injection scripts, and every use is documented. Never used in deploy, backup, restore or failover paths. |
| D5 | Log redaction | Redact credentials and personal or cloud identifiers with visible placeholders, and keep a redaction log. |
| D6 | Failure simulation | Node failure means stopping a k3d **agent** container. Storage failure means making the data volume unavailable. Known limitations must document how these differ from a real multi-zone cluster. |
| D7 | Reference machine | Linux x86-64 with Docker, 4 vCPU and 16 GB RAM. The deployment keeps a reduced footprint to fit it. |
| D8 | Targets and data | RTO target ≤ 30 s, with the real RTO measured and reported per failure mode. RPO measured and stated, synthetic dataset of about 100–200 MB. |
| D9 | Repository | The repository is public. Secrets are never committed. |

### Assumptions

- **A1.** The VM runs on UTC and the lead works in Asia/Dhaka (UTC+6), so timestamps must always state a timezone.
- **A2.** When prioritising, MUST items in a lower priority still outrank SHOULD items in a higher one.
- **A3.** Security, fault tolerance and observability are scored, but the brief leaves their content to us (p.3). Only "document what you implemented, what you left out, and why" is a literal MUST. Specific controls are SHOULD (derived), except basic alerting and failure testing, which we treat as MUST because they are named scoring areas.
- **A4.** † thresholds are engineering targets for a local cluster, not figures from the brief.
- **A5.** "Failure" tests run at least **3 times per failure mode†**, reporting median and worst case.
- **A6.** The **RTO target is ≤ 30 s†** for automatic failover. We compare it with the **worst run** of each failure mode (pod, node, storage), so a good median cannot hide a slow failover. It is our target, not a pass/fail gate, and a miss is reported rather than tuned away unsafely (ADR-006).

---

## R1. Topology and streaming replication (p.1–2)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R1.1 | MUST | P1 | PostgreSQL 15 or newer | `server_version_num` ≥ 150000 on every instance, and the image tag is pinned | `T:topology` output |
| R1.2 | MUST | P1 | At least 1 primary and 2 replicas | Exactly 1 instance has `pg_is_in_recovery()=false`, at least 2 have `true` | `T:topology` output |
| R1.3 | MUST | P1 | Physical streaming replication | `pg_stat_replication` on the primary shows ≥ 2 rows with `state=streaming`. A row written on the primary is readable on both replicas | `T:replication` output |
| R1.4 | MUST | P1 | Justify sync vs async and state the implied RPO | Doc states the mode, the trade-off and the RPO. A test under write load confirms the stated RPO against acknowledged writes | Design doc section, `T:rpo` output |
| R1.5 | MUST | P1 | Replication slots or equivalent, so replicas cannot fall behind permanently | A replica stopped for 5 minutes† under write load catches up unaided after restart | `T:replica-catchup` output |
| R1.6 | MUST | P1 | Protect against slots filling the disk | With one replica stopped under sustained writes, retained WAL stays under the configured bound, the primary keeps accepting writes, and the lost replica recovers automatically | `T:slot-bound` output, WAL-size graph or metric |
| R1.7 | MUST | P1 | Show how replication lag is measured | Lag is exposed in both bytes and seconds, rises under induced lag and returns to near zero | Doc section, `T:lag` output, metric query |

## R2. Client connectivity (p.2)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R2.1 | MUST | P1 | One stable endpoint that always reaches the current primary | Connections return `pg_is_in_recovery()=false` before and after every failover and switchover | `T:endpoints` output |
| R2.2 | MUST | P1 | Separate read-only endpoint | Connections return `true`, and a write attempt is rejected | `T:endpoints` output |
| R2.3 | MUST | P1 | Clients reconnect after failover with no manual change | A probe with one unchanged connection string resumes writes after failover, and no manifest or Service is edited by hand | `T:failover-*` probe log |
| R2.4 | SHOULD | P1 | Read endpoint stops routing to unhealthy replicas (*derived*) | A stopped replica leaves the read endpoint within the readiness window | `T:endpoints` output |
| R2.5 | OPTIONAL | P4 | Connection pooling | If added: the reason is documented and R2.1–R2.3 still pass through it. If not: the omission is justified | Design doc section |

## R3. Automatic failover (p.2)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R3.1 | MUST | P1 | Automatic promotion when the primary **pod** fails | After a forced pod kill, a replica is promoted and the write probe recovers in every run, with RTO recorded under R3.7. The only command issued is the fault itself | `T:failover-pod` output |
| R3.2 | MUST | P1 | Automatic promotion when the primary's **node** fails | Same as R3.1, after stopping the k3d agent container hosting the primary (D6) | `T:failover-node` output |
| R3.3 | MUST | P1 | Automatic promotion when the primary's **storage** fails | Same as R3.1, after making the primary's data volume unavailable (D6) | `T:failover-storage` output |
| R3.4 | MUST | P1 | Two primaries never accept writes at once. "Accept" means **acknowledge a commit** | During primary isolation, the probe records **no** interval where two instances both acknowledge commits, and the isolated primary acknowledges no commit after promotion. A commit that blocks or fails is not an accepted write | `T:split-brain` timeline |
| R3.5 | MUST | P1 | Explain fencing and leader election or consensus | Doc covers the mechanism, timing values, the failure cases it handles and those it does not | Design doc section |
| R3.6 | MUST | P1 | Old primary rejoins automatically as a replica | After each failover, the old primary returns with `pg_is_in_recovery()=true`, streaming from the new primary on the new timeline, with no human step | `T:failover-*` output |
| R3.7 | MUST | P1 | Measure and report the real RTO and method per failure mode | RTO = fault injection to first committed write through the primary endpoint, probe interval ≤ 500 ms†. Median and worst case are reported per failure mode. **≤ 30 s† is our target, not a pass/fail gate:** a miss is reported and explained, and never justifies unsafe tuning (ADR-006) | RTO table with raw probe logs |

## R4. Automated backups (p.2)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R4.1 | MUST | P2 | Scheduled full (base) backups | A declared schedule exists and at least one scheduled (not hand-triggered) run has completed | Schedule manifest, `T:backup` output |
| R4.2 | MUST | P2 | Continuous WAL archiving | `pg_stat_archiver` shows advancing `archived_count` and no growing failure count. A forced WAL switch appears in the bucket | `T:wal-archive` output |
| R4.3 | MUST | P2 | Backups go to object storage. The brief names S3, GCS, Azure Blob or in-cluster MinIO. We use in-cluster, S3-compatible **Garage**, pending spike S1 (ADR-014) | Backup and WAL objects are listed from the bucket | `T:backup` output |
| R4.4 | MUST | P2 | Retention policy defined and enforced | Policy is stated. A test with more backups than allowed shows the oldest expired while the remaining backups stay restorable | Doc section, `T:retention` output |
| R4.5 | MUST | P2 | Backups are verified automatically by restoring them | An automated restore check runs on a schedule or on demand and fails loudly on bad data | `T:restore-verify` output |
| R4.6 | SHOULD | P2 | Backup and archiving survive failover (*derived*) | After failover, the new primary archives WAL and a new base backup succeeds with no manual change | `T:backup-after-failover` output |
| R4.7 | OPTIONAL | P4 | `BACKUP_TARGET=gcs make up` uses a Kustomize overlay to switch the pgBackRest repository to a GCS bucket (`repo-type=gcs`). Credentials are supplied at runtime from an environment variable or file outside the repo and are never committed. **Lowest-priority item:** built only after all security SHOULDs, and cut before R11.6 | With the variable unset, the target is Garage. With `gcs`, stanza creation, backup, archive and restore pass against the bucket, and a secret scan finds no credential | `T:backup-gcs` output |

## R5. Restoration (p.2–3)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R5.1 | MUST | P2 | Automated restore of the whole cluster into an empty namespace or cluster | One command produces a working 1-primary, 2-replica cluster in an empty target, with row counts and checksums matching the source | `T:restore-full` output |
| R5.2 | MUST | P2 | Restore procedure is documented | A reader can follow the runbook using only the documented command and inputs | Restore runbook |
| R5.3 | MUST | P2 | PITR to a given timestamp | Given timestamp T between two marked writes, the row before T exists and the row after T does not | `T:pitr` output |
| R5.4 | MUST | P2 | Scheduled or on-demand restore test into a scratch instance | Test restores to a scratch instance, checks data, reports pass/fail and cleans up | `T:restore-verify` output |
| R5.5 | SHOULD | P2 | PITR works across a failover timeline (*derived*) | A target time after a failover restores correctly | `T:pitr-timeline` output |

## R6. Operability (p.3)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R6.1 | MUST | P0 | Single documented entry point brings up everything | From a clean host with prerequisites, one command ends with all health checks passing | `T:clean-up` log with duration |
| R6.2 | MUST | P0 | Equally clean tear-down | One command leaves no project clusters, containers, volumes or networks | `T:clean-down` before/after listing |
| R6.3 | MUST | P1 | Document planned switchover, or justify leaving it out | Runbook exists. If implemented, the switchover completes with the old primary rejoining | Runbook, `T:switchover` output |
| R6.4 | MUST | P2 | Document a minor-version upgrade, or justify leaving it out | Runbook exists. If implemented, the version rises on all instances with one controlled switchover | Runbook, `T:minor-upgrade` output |
| R6.5 | SHOULD | P0 | Entry point is idempotent (*derived*) | Running it twice succeeds and the second run changes nothing material | `T:idempotent` output |

## R7. Platform and build rules (p.1, p.3, p.6)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R7.1 | MUST | P0 | Every requirement automated and declared as code | Each MUST above maps to committed code or a doc, with no undocumented manual step | Traceability matrix |
| R7.2 | MUST | P0 | A reviewer can reproduce it | A fresh clone on a clean machine passes the full test suite using only the README | Clean-run log |
| R7.3 | MUST | P0 | All versions pinned, no `:latest` (*lead rule*) | A repo scan finds no `:latest` or untagged image, and all tools have exact versions | `T:pins` output |
| R7.4 | MUST | P1 | Anti-affinity and topology spread configured | Postgres instances land on distinct nodes, and manifests declare both controls | `T:placement` output |
| R7.5 | SHOULD | P1 | Use a multi-node cluster (brief: "better") | At least 3 Ready nodes | `T:topology` output |
| R7.6 | MUST | P1 | Explain what changes on a real multi-zone cluster | Doc section covers zones, storage, failure domains and fencing | Doc section |

## R8. Security (p.3)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R8.1 | MUST | P4 | Document what was implemented, left out and why | Security doc has all three lists | Security doc |
| R8.2 | MUST | P0 | No real credentials committed | A secret scan of the **full git history** finds nothing | `T:secret-scan` output |
| R8.3 | SHOULD | P4 | Credentials generated at deploy time and held in Kubernetes Secrets (*derived*) | A clean deploy needs no pre-written secret, and values differ between deployments | `T:secrets` output |
| R8.4 | SHOULD | P4 | TLS for client and replication traffic (*derived*) | `pg_stat_ssl` shows TLS in use, and non-TLS connections are rejected | `T:tls` output |
| R8.5 | SHOULD | P4 | Least-privilege DB roles and strict `pg_hba` with SCRAM (*derived*) | Separate roles exist per purpose, an app role cannot replicate or act as superuser, and password auth uses SCRAM | `T:db-authz` output |
| R8.6 | SHOULD | P4 | Default-deny NetworkPolicy with explicit allows (*derived*) | An unauthorised pod **cannot** connect to Postgres, and an authorised one can | `T:netpol` output |
| R8.7 | SHOULD | P4 | Hardened pods: non-root, no privilege escalation, dropped capabilities (*derived*) | Namespace passes the Pod Security `restricted` profile, or each exception is documented | `T:pod-security` output |
| R8.8 | SHOULD | P4 | Least-privilege Kubernetes RBAC (*derived*) | `kubectl auth can-i` matrix shows only the needed verbs | `T:rbac` output |
| R8.9 | OPTIONAL | P4 | Image vulnerability scan | Report is committed with a triage note | Scan report |
| R8.10 | OPTIONAL | P4 | Backups encrypted at rest | Raw bucket objects are unreadable without the key, and restore still passes | `T:backup-encryption` output |

## R9. Fault tolerance (p.3)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R9.1 | MUST | P1 | Document the failure modes handled, not handled, and why | Failure-mode table covers each component, with expected behaviour and test link | Fault-tolerance doc |
| R9.2 | MUST | P1 | Repeatable failure test suite | One command runs the pod, node, storage and isolation scenarios and prints a results table | `T:chaos` output |
| R9.3 | SHOULD | P1 | PodDisruptionBudget prevents voluntary loss of quorum or availability (*derived*) | A node drain cannot evict below the budget | `T:pdb` output |
| R9.4 | SHOULD | P1 | Health probes and resource requests/limits on every workload (*derived*) | A manifest check finds none missing | `T:manifest-policy` output |
| R9.5 | SHOULD | P1 | Replica loss does not interrupt writes, or the behaviour is documented (*derived*) | Losing 1 replica matches the behaviour stated for the chosen replication mode | `T:replica-loss` output |
| R9.6 | SHOULD | P2 | Object-storage outage does not take down the primary (*derived*) | During an outage writes continue and an alert fires. After recovery the archive catches up with no gap | `T:archive-outage` output |
| R9.7 | SHOULD | P1 | Behaviour with two simultaneous failures is stated (*derived*) | Doc states the outcome, and the system never produces two writers | Fault-tolerance doc |

## R10. Monitoring and alerting (p.3)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R10.1 | MUST | P3 | Collect metrics for Postgres, replication, backups and the platform | All scrape targets are `up`, and key series exist | `T:metrics` output |
| R10.2 | MUST | P3 | Alert rules for: no primary, more than one primary, instance down, high lag, slot WAL growth, archive failure, stale backup, failed restore test, low disk | Each rule is loaded and passes rule unit tests | Rule files, rule test output |
| R10.3 | SHOULD | P3 | Key alerts proven to fire on real faults (*derived*) | Injected faults move at least primary-down, lag and archive-failure alerts to `firing`, then resolved | `T:alerts` output |
| R10.4 | SHOULD | P3 | Provisioned dashboard as code (*derived*) | Dashboard loads on a clean deploy and shows live data | Dashboard JSON, screenshot |
| R10.5 | MUST | P3 | Document what is monitored, left out and why | Doc lists signals and alerts with a response for each | Observability doc |

## R11. AI-assisted process (p.4–5)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R11.1 | MUST | P0 | Process documentation lets a reviewer follow it start to finish | Each phase lists inputs, prompt, outputs and verification | Playbook |
| R11.2 | MUST | P0 | Real session logs included, unedited except for redaction under D5 | Raw logs for **every** phase are committed, redactions use visible placeholders, and a redaction log lists each change | Logs, redaction log |
| R11.3 | MUST | P0 | Determinism: what is fixed vs model judgement, and how output stayed consistent | Dedicated section with concrete examples | Playbook section |
| R11.4 | MUST | P0 | Agent-agnostic: what changes with another agent, vendor specifics kept separate | General method contains no vendor-specific instructions, which live in a separate location | Playbook section, repo layout |
| R11.5 | MUST | P0 | Generalisation to another task (e.g. HA Redis or Vault) | Lists the files reused unchanged and those rewritten | Playbook section |
| R11.6 | OPTIONAL | P0 | Run the **Phase 1 design-options step only** with a second agent (Gemini) using the identical prompt, and compare. **Second-lowest priority, above only R4.7** | Identical prompt and both raw outputs are committed with a written comparison | Prompt, both outputs, comparison doc |
| R11.7 | MUST | P0 | No real credentials or confidential data in AI tools | Secret scan of session logs is clean | `T:secret-scan` output |
| R11.8 | MUST | P0 | Lead can explain every submitted line without AI | Lead completes a review pass per component before merging | Lead sign-off checklist |

## R12. Documentation and deliverables (p.5–6)

| ID | Level | Pri | Requirement | Acceptance | Evidence |
|---|---|---|---|---|---|
| R12.1 | MUST | P0 | Public GitHub repository (D9) | An unauthenticated `git clone` succeeds | Repo URL, clone output |
| R12.2 | MUST | P0 | Contains everything built, with clear run instructions | README covers prerequisites, up, test, down | README, clean-run log |
| R12.3 | MUST | P0 | Video of about 10–15 minutes: approach, how to run, challenges and how they were solved | Duration in range and all three topics covered | Video link |
| R12.4 | MUST | P0 | Submit by replying to the brief's email with repo link, video link and rough hours | Reply sent with all three items | Sent-mail check by lead |
| R12.5 | MUST | P0 | Known limitations documented, with no hidden gaps | Every unmet or partly met requirement here appears in that section | Known-limitations doc |
| R12.6 | MUST | P0 | Every claim is backed by evidence | Traceability matrix maps each requirement to status and evidence link | Traceability matrix |

---

## Hard constraints

Breaking any of these counts directly against the submission or violates a lead rule.

**From the brief**

- **HC1.** No Postgres operators: CloudNativePG, Crunchy PGO, Zalando, StackGres, Percona, KubeBlocks "or similar" (p.3).
- **HC2.** No turnkey HA Helm charts, such as Bitnami `postgresql-ha` (p.3).
- **HC3.** No managed databases (p.3).
- **HC4.** Patroni and repmgr are allowed only if we deploy, configure and wire them into Kubernetes ourselves (p.6).
- **HC5.** Manual `kubectl exec` steps do not count as automation (p.1). Scripted use is limited by HC20.
- **HC6.** No real credentials committed (p.3).
- **HC7.** No real credentials or confidential data pasted into AI tools (p.5).
- **HC8.** Session logs must be real and unedited except for secret removal. Logs that look edited or reconstructed count against us (p.4–5).
- **HC9.** No claims without evidence (p.5).
- **HC10.** No hidden gaps. Incomplete work goes under known limitations (p.6).
- **HC11.** No code the lead cannot explain in the review session (p.5–6).
- **HC12.** A reviewer must be able to reproduce the system (p.3).

**From the lead**

- **HC13.** Plan before code, in small steps, each with a verification command and expected output.
- **HC14.** Pin all versions. No `:latest`.
- **HC15.** Never put real secrets in files or chat.
- **HC16.** Ask before any destructive command.
- **HC17.** State every assumption the lead did not give explicitly.
- **HC18.** No operators of any kind, including the Prometheus Operator and `kube-prometheus-stack` (D1).
- **HC19.** Do not change system-wide tool versions to fix version skew. Project tools are pinned and installed locally (proposal in `docs/environment.md`, implemented in Phase 1).
- **HC20.** `kubectl exec` appears only in committed, automated test or fault-injection scripts, with each use documented. It never appears in deploy, backup, restore or failover paths (D4).
- **HC21.** No third-party Helm charts. Supporting components use our own minimal manifests (D2).
- **HC22.** The Postgres image is built by us from the official `postgres` image plus Patroni. No Spilo or other prebuilt HA image (D3).
- **HC23.** The repository is public, so nothing secret or personally identifying may be committed (D5, D9).
