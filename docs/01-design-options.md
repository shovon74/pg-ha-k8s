# 01 — Design options

**Status:** Phase 1 decisions accepted by the lead and recorded in `docs/decisions/`. Nothing here is implemented.
**Prompt:** `docs/process/prompts/p1-design-options.md`
**Research date:** Monday 2026-11-23, 13:30 Asia/Dhaka (07:30 UTC)
**Guiding principle:** the smallest system that meets every MUST and that the lead can defend line by line.

## How to read this

- **O1–O13** are the design decisions in this document. **D1–D9** are the lead's existing decisions in `docs/00-requirements.md`.
- **[NICE]** marks a nice-to-have that no MUST depends on.
- **[Verified]** means checked on 2026-11-23 against upstream source, a registry or this host. Patroni claims refer to tag `v4.1.5`, and pgBackRest claims to `release/2.60.1`.
- **[Assumption]** means not proven yet. Each one has a spike or test in the build plan.
- **Effort** is focused hours to implement and test that option.

## Findings that change the plan

1. **Prebuilt MinIO is no longer obtainable.** The upstream repository is archived and marked unmaintained, the release binaries return HTTP 410, and anonymous image pulls from Docker Hub and Quay return 401. The lead rejected shipping unmaintained software, so O9 now uses Garage, and building MinIO from source is only the last fallback. **[Verified]**
2. **The 30 s RTO has a thin margin.** Patroni rejects a `ttl` below 20 s, so a hard failure spends 20 s on lock expiry alone. The estimated worst case is 26–28 s, and only measurement can confirm it (O6). **[Verified floor, estimated total]**
3. **Patroni does not support Leases.** Its Kubernetes DCS uses Endpoints or ConfigMaps only, and its docs call Endpoints the recommended mode (O2). **[Verified]**
4. **A watchdog is unsafe here.** All k3d nodes share one VM kernel, so a software watchdog firing would reboot the entire VM rather than one node (O6). **[Verified: no `/dev/watchdog`, `softdog` module available]**
5. **A dead node stays in selector-based Services for up to 50 s** by default (`node-monitor-grace-period`), which alone could break the RTO target. Patroni-managed Endpoints avoid this for the primary (O7). **[Verified]**
6. **Backups cannot use `kubectl exec` (D4).** A CronJob therefore needs a network path to the database host. pgBackRest's TLS server provides one, which makes a private CA a P2 dependency rather than a P4 hardening item (O9, O12). **[Verified options exist]**

---

## Final decisions

| Decision | Outcome | ADR |
|---|---|---|
| O1 Topology | 1 tainted server + 3 agents, one Postgres pod per agent | ADR-001 |
| O2 HA manager | Patroni with Endpoints, `failsafe_mode` off. An API outage demotes the primary | ADR-002 |
| O3 Image | Official Postgres 17.12 + pinned PGDG Patroni and pgBackRest | ADR-003 |
| O4 Replication | Non-strict `synchronous_mode`. **RPO 0 for any single failure**, and a double replica failure falls back to async | ADR-004 |
| O5 Slots | Patroni slots, `max_slot_wal_keep_size=1GB`, alerts | ADR-005 |
| O6 Fencing | 20/3/5 timing, lock-based demotion + sync replication, no watchdog. "Accepts writes" means **acknowledged commits**. Real RTO is reported per failure mode, with no unsafe tuning | ADR-006 |
| O7 Endpoints | Patroni-managed `pg-rw`, selector-based `pg-ro`, no pooler | ADR-007 |
| O8 Rejoin | `pg_rewind` with re-clone fallback | ADR-008 |
| O9 Backups | pgBackRest, with one `make certs` CA reused for pgBackRest and Postgres TLS | ADR-009 |
| O10 Restore | Patroni custom bootstrap, one restore-test Job for CronJob and make | ADR-010 |
| O11 Observability | Prometheus, Alertmanager, exporters, kube-state-metrics, node_exporter. Grafana out of scope unless every MUST and other SHOULD is done | ADR-011 |
| O12 Security | Layered baseline, **built last** | ADR-012 |
| O13 Packaging | Kustomize, Makefile, `versions.env`, `./bin` | ADR-013 |
| Object storage | **Garage v2.5.0**, with pgBackRest repository encryption | ADR-014 |

---

## Target architecture

A k3d cluster runs one tainted server and three agents on a single VM. Three Postgres 17 pods in a StatefulSet run one per agent, each with Patroni managing Postgres and using the Kubernetes API as its leader lock. Patroni writes the leader's address directly into the `pg-rw` Endpoints, while `pg-ro` selects healthy replicas by label. Replication is synchronous to one standby through Patroni, with slots bounded by `max_slot_wal_keep_size`. pgBackRest archives encrypted WAL continuously to an in-cluster Garage object store, and CronJobs run base backups and a scratch restore test. Prometheus, Alertmanager and small exporters run from our own manifests on the server node, so they survive agent failures. One `make up` builds and deploys everything from a single pinned versions file.

```text
                        Clients (one connection string each)
                             |                      |
                     pg-rw Service            pg-ro Service
                 (Patroni-managed Endpoints) (selector: role=replica)
                             |                      |
    +------------------------v----------------------v------------------+
    | k3d cluster on one VM                                            |
    |                                                                  |
    |  agent-0            agent-1             agent-2                  |
    | +------------+     +------------+      +------------+            |
    | | pg-0       |====>| pg-1       |      | pg-2       |            |
    | | PRIMARY    | sync| SYNC       |      | REPLICA    |            |
    | | Patroni    |=====|============|=====>| Patroni    |            |
    | | pgBackRest |async| pgBackRest |      | pgBackRest |            |
    | | exporter   |     | exporter   |      | exporter   |            |
    | +-----+------+     +------+-----+      +-----+------+            |
    |       |  leader lock      |                  |                   |
    |       +-------------------+------------------+                   |
    |                           v                                      |
    |  server (tainted, runs infrastructure only)                      |
    | +--------------------------------------------------------------+ |
    | | Kubernetes API | Garage <- WAL + backups | Prometheus        | |
    | | Backup and restore-test CronJobs         | Alertmanager      | |
    | +--------------------------------------------------------------+ |
    +------------------------------------------------------------------+
```

---

## O1. Cluster topology

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. 1 server + 3 agents** | Server is tainted and hosts infrastructure. One Postgres pod per agent | Matches D6, every Postgres node can be failed, object storage and monitoring survive agent loss | API server is a single point of failure | Meets R1.2, R3.2, R7.4, R7.5. Risks R9.7 | 1 h |
| B. 3 servers + 3 agents | Embedded etcd gives an HA control plane | Removes the API single point of failure | Six node containers on 4 vCPU, and etcd adds load that distorts RTO | Meets the same, helps R9.7. Risks D7 | 2 h |
| C. 1 server + 2 agents | One Postgres pod runs on the server | Smallest footprint | Conflicts with D6, because a primary on the server cannot be failed as an agent | Risks R3.2, R3.7 | 1 h |

**Pod placement for option A:**

- **Pinning:** required node affinity on a `pg-ha/role=db` label, which only agents carry.
- **Anti-affinity:** required `podAntiAffinity` on `kubernetes.io/hostname`.
- **Spread:** `topologySpreadConstraints` with `maxSkew: 1` and `DoNotSchedule`.
- **Simulated zones [NICE]:** label agents `topology.kubernetes.io/zone=a|b|c`, which makes the multi-zone explanation (R7.6) concrete at almost no cost.

**Recommendation: A.** Strongest reason: it is the smallest topology where any Postgres node can be killed under D6 while backups and monitoring keep running.

## O2. HA manager and leader election

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Patroni + Kubernetes Endpoints** | Leader lock and leader address live in one Endpoints object | One atomic update moves lock and routing, recommended by Patroni docs, no extra store | Endpoints API is deprecated since v1.33 but still defined in v1.35.10 **[Verified from source. Runtime check in spike S4]** | Meets R3.1–R3.6, R2.1, R6.3 | 3 h |
| B. Patroni + ConfigMaps | Lock is in a ConfigMap, routing follows pod labels | Avoids the deprecated API | Two separate updates, and a dead pod lingers in the Service | Risks R2.3, R3.7 | 3 h |
| C. Patroni + etcd | Separate 3-member etcd StatefulSet | Consensus independent of the API server | Three more stateful pods to secure, monitor and explain | Meets R3.x. Risks D7, R11.8 | 6 h |
| D. repmgr | Replication manager with its own daemon and witness | Simple concepts | No built-in consensus lock, so fencing would be our own code | Risks R3.4, R3.5 | 8 h+ |

Leases are not an option, because Patroni does not implement them. **[Verified]**

**If the API server is unreachable:**

- **Default behaviour:** the primary cannot renew its lock, so Patroni demotes it to read-only. No replica can promote because none can take the lock. Reads continue, writes stop until the API returns, and no split-brain or data loss occurs. **[Verified in docs]**
- **`failsafe_mode` [NICE]:** the primary keeps writing during an API outage only if **all** members acknowledge it over the Patroni REST API. It improves availability but adds a mode to test and defend.

**Why failsafe stays off:** the API server is a known single point of failure here, and a demoted primary means no writes but also no split-brain. Safety outranks write availability for this design.

**Recommendation: A, with `failsafe_mode` off.** Strongest reason: one atomic write moves both leadership and client routing, which removes a whole class of stale-routing failures.

## O3. Postgres image

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Official image + pinned PGDG packages** | `FROM postgres:17.12-trixie@sha256:…`, then `apt-get install` exact `patroni` and `pgbackrest` versions | Short Dockerfile, signed packages, same repo as Postgres | Transitive Debian packages are not individually pinned | Meets R1.1, R7.3, D3 | 1.5 h |
| B. Official image + pip hash lock | Patroni in a venv with `--require-hashes`, pgBackRest from PGDG | Fully pinned Python dependencies | Lock file to generate and explain | Meets the same, stronger on R7.3 | 2.5 h |
| C. Alpine or source build | Compile on a minimal base | Smallest image | Slow builds, more to defend, no benefit for a MUST | Risks R11.8 | 5 h+ |

**Details for option A:**

- **Versions:** `patroni=4.1.5-2.pgdg13+1` and `pgbackrest=2.60.1-1.pgdg13+1`, both present in the PGDG trixie index. **[Verified]**
- **Size:** the base is 159 MiB compressed. **[Verified]** The final image should be about 200–230 MiB compressed. **[Assumption]**
- **Non-root:** run directly as the image's `postgres` user (UID 999), bypassing the root entrypoint.
- **Data path:** set `PGDATA` to a subdirectory of the volume, so Patroni can create it with mode 0700. **[Assumption: local-path permissions, spike S3]**
- **Reproducible load:** `docker build` with a tag derived from the versions file, then `k3d image import`, with no registry and `imagePullPolicy: IfNotPresent`.

**Recommendation: A.** Strongest reason: the Dockerfile stays short enough to explain line by line while every directly used version is pinned.

## O4. Replication mode

| Option | How it works | RPO | Availability trade-off | R-IDs | Effort |
|---|---|---|---|---|---|
| A. Asynchronous | Commit returns before any replica confirms | **> 0**, bounded by `maximum_lag_on_failover` | Best. Writes never wait on replicas | Meets R1.4, R9.5. Weakens R3.4 | 0.5 h |
| **B. `synchronous_mode: true`, 1 sync standby** | Commit waits for one standby, and Patroni promotes only a safe candidate | **0 for any single failure** | One replica lost: writes continue on the other. Both lost: writes continue **unprotected** | Meets R1.4, R3.4, R9.5, R9.7 | 1 h |
| C. `synchronous_mode_strict` | Same, but commit requires a standby at all times | **0 even with both replicas lost** | Both replicas lost: **writes stop** | Meets R1.4. Availability cost on R9.7 | 1 h |
| D. `synchronous_mode: quorum` [NICE] | Commit waits for any 1 of 2 standbys | 0 for any single failure | Lower latency spikes, harder to explain | Meets R1.4 | 2 h |

**Limits to state in the docs, for B and C** **[Verified in Patroni docs]**:

- If the primary and its sync standby fail **together**, the remaining node may be promoted without the latest commits.
- A backend cancelled while waiting for sync confirmation can expose a transaction that was never replicated.
- A client can opt out with `SET synchronous_commit = local`, because Postgres lets ordinary roles change it.

**Stated RPO for the accepted option:** 0 for any single failure. With non-strict `synchronous_mode`, a double replica failure falls back to async, choosing availability over durability.

**Recommendation: B.** Strongest reason: zero loss for any single failure, plus an isolated old primary cannot get commits acknowledged because its standbys have left it.

## O5. Replication slots and disk protection

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Patroni member slots + WAL cap + alerts** | `use_slots: true` manages one slot per member, `max_slot_wal_keep_size` caps retained WAL | Automatic across failover, hard disk bound | A replica past the cap must recover from the archive | Meets R1.5, R1.6 | 1.5 h |
| B. Permanent named slots | Slots declared in Patroni config | Useful for external consumers | Not needed here, and stale slots retain WAL | Risks R1.6 | 2 h |
| C. No slots, `wal_keep_size` only | Fixed WAL window | Simplest | Replicas can fall behind permanently, and the brief asks for slots or equivalent | Weak on R1.5 | 0.5 h |

**Proposed values for option A:**

| Setting | Value | Why |
|---|---|---|
| PVC size | 5 GiB | Ample for a 100–200 MB dataset |
| `max_wal_size` | 512 MB | Limits normal WAL use |
| `max_slot_wal_keep_size` | 1 GB | Hard bound for R1.6 |
| `archive-push-queue-max` | 2 GiB | During an object-storage outage, drops WAL instead of filling the disk, at the cost of a PITR gap that must alert |

- **Test design:** R1.5 uses rate-limited writes that stay below the cap. R1.6 deliberately exceeds it.
- **Recovery past the cap:** the replica fetches missing WAL through `restore_command`. **[Assumption: tested by `T:slot-bound`]**
- **PVC limits are not enforced by local-path.** The WAL cap is therefore the real protection, and the test measures `pg_wal` directly.
- **Alerts:** `pg_replication_slots_slot_safe_wal_size_bytes` and `slot_wal_status` are exposed by the exporter by default. **[Verified: collector and metric suffixes. Final names confirmed at implementation]**

**Recommendation: A.** Strongest reason: it is the only option that both prevents permanent lag and puts a hard limit on disk use.

## O6. Split-brain prevention and fencing

**Timing options** (Patroni requires `loop_wait + 2 × retry_timeout ≤ ttl`, and `ttl ≥ 20`) **[Verified]**

| Option | `ttl` / `loop_wait` / `retry_timeout` | Estimated worst RTO | Pros | Cons | R-IDs | Effort |
|---|---|---:|---|---|---|---|
| A. Patroni defaults | 30 / 10 / 10 | 40 s+ | Most tolerant of API latency | **Fails the 30 s target** | Fails R3.7 | 0.5 h |
| **B. Tuned to the floor** | **20 / 3 / 5** | **26–28 s** | Meets the target, satisfies the rule (3 + 10 ≤ 20) | Slow API responses can cause needless failovers | Meets R3.1–R3.4, R3.7 | 2 h |
| C. Longer loop | 20 / 5 / 5 | 27–30 s | Slightly less API load | Almost no RTO margin | Risks R3.7 | 2 h |

Worst-case estimate for B: lock expiry 20 s, replica notices ≤ 3 s, election and promotion 2–4 s, client reconnect ≤ 1 s. **[Assumption: measured in `T:failover-*`]**

Also set **`primary_start_timeout: 0`**. The default would spend up to 300 s restarting a crashed primary in place. At 0, Patroni releases the lock if a healthy replica can take over. **[Verified in `ha.py`]**

**Fencing options**

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Lock-based demotion + synchronous replication** | Primary demotes when it cannot renew the lock. Sync mode blocks commits once standbys leave it | No privileges needed, works in k3d | A frozen Patroni cannot demote itself, though its commits still cannot be acknowledged | Meets R3.4, R3.5 | Included |
| B. Software watchdog | `softdog` resets the machine if Patroni stalls | Strongest protection on real nodes | **Reboots the whole VM here**, needs host module and device access | Risks R8.7, R7.2 | 3 h |
| C. Custom Kubernetes fencing | Controller deletes or isolates the old pod | Explicit fencing | Depends on the API that may be down, and is effectively a homemade operator | Risks D1, R11.8 | 6 h+ |

**Why two primaries cannot both accept writes (option A):**

1. Only the holder of the leader lock may run as primary, and the Kubernetes API's optimistic concurrency lets only one member win.
2. A primary that cannot renew demotes itself before the lock expires, which is what the timing rule guarantees.
3. If demotion fails, for example because Patroni is frozen, the old primary's `synchronous_standby_names` remains set while its standbys follow the new leader. Its commits wait and are never acknowledged. **[Assumption: proven by `T:split-brain`]**
4. Client routing moves in the same atomic update as the lock, so new connections reach only the new primary.

`T:split-brain` counts **acknowledged commits** (lead decision), because a blocked commit is not an accepted write. The fault is `docker network disconnect` on the primary's agent.

**Residual risk to document:** on real nodes we would add a watchdog (R7.6).

**Recommendation: timing B and fencing A.** Strongest reason: it is the only combination that meets the RTO and retains write fencing without a privileged device that could reboot the host.

## O7. Client endpoints and pooling

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Patroni-managed `pg-rw` + selector-based `pg-ro`** | `pg-rw` has no selector and Patroni writes its Endpoints. `pg-ro` selects `role=replica` and ready pods | Primary routing changes atomically with leadership, no extra hop | Relies on EndpointSlice mirroring **[Assumption: latency measured in spike S4]** | Meets R2.1–R2.4, R3.7 | 1.5 h |
| B. Label selectors for both | Patroni patches `role` labels and Services follow | Standard Kubernetes pattern | A dead node's pod can remain for up to 50 s | Risks R2.1, R3.2, R3.7 | 1 h |
| C. HAProxy in front | Proxy health-checks Patroni REST | Fast routing, common on VMs | Another HA component to run and explain | Meets R2.x. Risks D7 | 4 h |

- **Read endpoint on node loss:** set `node-monitor-grace-period=20s` through k3s so a dead replica leaves `pg-ro` sooner (R2.4).
- **Clients:** the test probe must set a short `connect_timeout` and TCP keepalives. Otherwise, a connection to a dead pod hangs and inflates the measured RTO.

**Pooling options**

| Option | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|
| **A. No pooler** | Fewer failure modes, direct RTO measurement | No connection multiplexing | Meets R2.5 (omission justified) | 0 h |
| B. PgBouncer [NICE] | Protects Postgres from connection storms | Extra hop, more auth config, must be HA itself | Optional | 3 h |

**Recommendation: A and no pooler.** Strongest reason: the primary endpoint cannot point at a stale pod after failover, and the brief does not require pooling.

## O8. Old primary rejoin

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. `pg_rewind`, with re-clone fallback** | `use_pg_rewind: true`, and `remove_data_directory_on_rewind_failure: true` | Fast normal path, and still recovers automatically when rewind fails | Fallback deletes that member's data dir | Meets R3.6 | 1.5 h |
| B. Always re-clone | Remove data and copy from primary | Simple logic | Slower, more I/O on a shared disk | Meets R3.6 | 1 h |
| C. `pg_rewind` only | No fallback | No automatic deletion | Can leave a member stuck | Risks R3.6 | 1 h |

**Requirements:**

- `pg_rewind` needs **`wal_log_hints=on` or data checksums**. **[Verified]**
- Enable **both**: initialise with `--data-checksums`, which also detects corruption, and keep `wal_log_hints=on`, which Patroni sets. **[Verified]**
- Create a dedicated rewind role with only the required function privileges.
- `restore_command` lets rewind fetch older WAL from the archive when needed.

**Recommendation: A.** Strongest reason: it gives the fast path while guaranteeing the old primary always returns with no human step.

## O9. Backups

**Backup tool**

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. pgBackRest** | `archive-push` from Postgres. A CronJob connects to each pod's pgBackRest TLS server and finds the primary | Built-in `expire` and `verify`, works without `kubectl exec`, handles timelines | Needs TLS server, client certs and a stanza step | Meets R4.1–R4.5, R4.6, D4 | 4 h |
| B. WAL-G | Single binary that must run where `PGDATA` is mounted | Small, simple WAL archiving | Needs an in-pod scheduler to run base backups without `exec` **[Assumption]**, weaker built-in verification | Risks D4, R4.5 | 4–5 h |

**Object storage** (Finding 1, full reasoning in ADR-014)

| Criterion | **A. Garage v2.5.0** | B. SeaweedFS 4.54 | C. MinIO from source (last fallback) |
|---|---|---|---|
| Official pinned image | Yes | Yes | **No** |
| Maintained | Yes | Yes, about weekly | **No, archived** |
| pgBackRest S3 calls | All required calls documented as implemented **[Verified in docs, not run]** | All required calls have route handlers **[Verified in source, not run]** | Known S3 target **[Assumption]** |
| Bootstrap without `kubectl exec` | Admin API v2 from a Job **[Verified API exists]** | Startup flags or config | Job with `curl --aws-sigv4` **[Assumption]** |
| Compressed image | **26 MiB** | **269 MiB** | Not built |
| Native TLS | **No** | Yes | Yes |
| Main concern | Needs another control for transport | Larger attack surface, 57 published advisories | Unmaintained, rejected by the lead |

Garage runs as one node with `replication_factor = 1`, and `metadata_fsync` and `data_fsync` enabled because both default to off. Since it has no native TLS, pgBackRest encrypts the repository client-side. The brief names "S3, GCS, Azure Blob or MinIO" and not Garage, so the docs must state this substitution and the reason for it.

**Policy for pgBackRest + Garage:**

| Item | Proposal |
|---|---|
| Base backup | Full, daily at 20:00 UTC (02:00 Asia/Dhaka), via CronJob |
| WAL archiving | Continuous, `archive-async=y` |
| Retention | `repo1-retention-full=7`, enforced by automatic `expire` after each backup |
| Integrity | `pgbackrest verify` daily, after the backup |
| Restore proof | Daily scratch restore (O10) |
| Differential backups | [NICE] Not needed for a 200 MB dataset |
| Repository encryption | `aes-256-cbc`, required because the object store has no native TLS. Also meets R8.10 |

R4.1 needs a truly scheduled run. Evidence will be a Job created by the CronJob **without** the `cronjob.kubernetes.io/instantiate: manual` annotation, captured from a cluster left running across a schedule.

**Decision: pgBackRest with Garage.** If spike S1 fails, evaluate SeaweedFS next, and build MinIO from source only as a last resort. Strongest reason: Garage is a maintained, 26 MiB single binary that documents every S3 operation pgBackRest uses, while pgBackRest provides retention, verification and network-triggered backups without `kubectl exec`.

## O10. Restore and PITR

**Full restore into an empty namespace**

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Patroni custom bootstrap** | Deploy the same manifests through an overlay. Patroni's `bootstrap.method` runs `pgbackrest restore`, then replicas clone normally | Reuses all HA config, ends as a real 1+2 cluster | Bootstrap script needs care | Meets R5.1–R5.3 | 3 h |
| B. Pre-restore Job per PVC | Restore into PVCs, then start Patroni | Separates the steps | Repeats work per member, harder to promote cleanly | Meets R5.1. Risks R5.3 | 4 h |

**Scheduled verification**

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. One Job template, both triggers** | A CronJob runs daily, and `make test-restore` creates a Job from it | Same code proves both paths, and alerts can watch it | Needs CPU headroom | Meets R4.5, R5.4 | 2 h |
| B. `make` target only | Runs on demand | Simple | Backups are not verified unattended | Weak on R4.5 | 1.5 h |

**Restore details:**

- **Scratch instance:** the Job restores into its own `emptyDir`, starts Postgres with no network exposure, checks data and exits, so cleanup is automatic.
- **Checks:** recovery reaches its target, a marker table matches expected row counts and checksums, and `pg_amcheck` passes.
- **PITR input:** `make restore TARGET_TIME='2026-11-25 14:30:00+06'`, using `--type=time` and `--target-action=promote`. A timezone offset is **required**, because the VM runs UTC and the lead works in UTC+6.
- **Protect the source:** a restored cluster must **not** archive into the source stanza, or it would pollute the source's WAL history.
- **Credentials:** the restored database contains the source's role passwords. A `post_bootstrap` step should reset them to the target namespace's Secret. **[Assumption: confirm in Phase 2]**
- **Limit to document:** in-cluster object storage is lost with the cluster, so this proves namespace-level recovery and not off-site disaster recovery.

**Recommendation: Patroni custom bootstrap plus one Job template triggered by both CronJob and make.** Strongest reason: the restored system goes through the same HA path as production, so a passing test proves what would actually run.

## O11. Observability

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Prometheus, Alertmanager, postgres_exporter, Patroni `/metrics`, kube-state-metrics, node_exporter** | Plain Deployments and a DaemonSet from our manifests | Covers every required alert with standard metrics | Two components beyond the requested list | Meets R10.1, R10.2, R10.5 | 3.5 h |
| B. Same, with Pushgateway instead of kube-state-metrics | Backup Jobs push their results | Direct job metrics | Stale-metric pitfalls and custom push code | Meets R10.x | 4 h |
| C. Option A + Grafana [NICE] | One provisioned dashboard | Better video and reviewer experience, meets R10.4 | More memory and manifests | Adds R10.4 | +1 h |

Kube-state-metrics provides CronJob and Job status for backup and restore alerts. Node_exporter provides disk space. Both were added because no requested component exposes those signals.

**Alert list (R10.2)**

| Alert | Signal | Severity |
|---|---|---|
| `PostgresNoPrimary` | `sum(patroni_primary) == 0` | critical |
| `PostgresMultiplePrimaries` | `sum(patroni_primary) > 1` | critical |
| `PostgresInstanceDown` | `patroni_postgres_running == 0` or scrape failed | critical |
| `ReplicationLagHigh` | Patroni WAL positions (bytes) and `pg_replication_lag_seconds` | warning |
| `ReplicationSlotWalHigh` | Slot retained WAL or low safe WAL size | warning |
| `ReplicationSlotLost` | Slot `wal_status` is `lost` | critical |
| `WalArchiveFailing` | `pg_stat_archiver_failed_count` increasing | critical |
| `BackupStale` | CronJob last success older than 26 h | critical |
| `RestoreTestFailed` | Latest restore Job failed, or last success older than 26 h | critical |
| `DiskSpaceLow` | Filesystem available below 15% | warning |

Rules are unit-tested with `promtool test rules`. Alertmanager routes to a no-op receiver, and evidence comes from its API, so no webhook secret is needed.

**Decision: A. Grafana is out of scope unless every MUST and every other SHOULD is done.** Strongest reason: it covers every required alert with standard exporters, and Grafana serves only R10.4.

## O12. Security baseline

| Option | Scope | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| A. Minimal | Generated secrets and SCRAM only | Fast | Traffic is plaintext, and no pod or network isolation | Meets R8.1–R8.3 only | 1.5 h |
| **B. Layered baseline** | Everything in the table below | Covers every SHOULD at modest cost | Most effort to test | Meets R8.1–R8.8 | 4 h |
| C. Full hardening [NICE] | B plus client certs, rotation, image scan, encrypted repo | Closest to production | Far more effort than the scope needs | Adds R8.9, R8.10 | 8 h+ |

**Option B contents**

| Area | Proposal |
|---|---|
| **Secrets** | `make up` generates random values with `openssl rand` into Kubernetes Secrets, only if absent. Nothing is written to the repo |
| **CA and certs** | One private CA per deployment, generated once by `make certs` in the bootstrap phase and reused for pgBackRest and Postgres TLS. cert-manager is excluded because it is an operator (D1) |
| **Auth** | `password_encryption=scram-sha-256`, `pg_hba` with `hostssl` and SCRAM only, and no `trust` over the network |
| **TLS** | Client and replication traffic. Replication uses `verify-full` with a wildcard SAN for the headless Service |
| **NetworkPolicy** | Default-deny in and out, with explicit allows for DNS, Kubernetes API, peers, object storage and metrics |
| **k3s enforcement** | k3s ships an embedded controller, on unless `--disable-network-policy` is set. **[Verified in docs]** Enforcement and API egress are proven in spike S2 and `T:netpol` |
| **RBAC** | Namespaced Role for Patroni, trimmed from upstream's sample to the verbs actually needed and checked with `kubectl auth can-i` |
| **securityContext** | UID 999, `runAsNonRoot`, no privilege escalation, drop all capabilities, `RuntimeDefault` seccomp, and Pod Security `restricted` on the database namespace |
| **Exception** | node_exporter needs host filesystem access, so it runs in the monitoring namespace with a documented exception |
| **DB roles** | Separate `postgres`, `replicator`, `rewind`, `monitor`, `backup`, `app` and `app_ro` roles |

**Decision: B, built last, per the brief's FAQ priority.** Only `make certs` and generated Secrets run earlier, because pgBackRest depends on them. Strongest reason: it covers every security SHOULD without custom tooling.

## O13. Packaging and entry point

| Option | How it works | Pros | Cons | R-IDs | Effort |
|---|---|---|---|---|---|
| **A. Raw manifests + Kustomize** | `base/` plus overlays such as `restore`, applied with pinned `kubectl` | No templating language, built into kubectl, every resource is readable | Limited parameterisation | Meets R6.1, R7.1, R7.2, D2 | 2 h |
| B. Our own Helm chart | First-party templates | Strong parameterisation | Templating to defend, and it could be mistaken for a turnkey chart | Risks D2 optics, R11.8 | 4 h |
| C. Plain YAML + `envsubst` | Shell substitution | Fewest tools | Fragile and hard to validate | Risks R6.5 | 2 h |

**Proposed Makefile targets**

| Group | Targets |
|---|---|
| Setup | `preflight`, `tools`, `certs`, `image` |
| Lifecycle | `up`, `down`, `status` |
| Tests | `test`, `test-replication`, `test-endpoints`, `test-backup`, `test-restore`, `test-pitr`, `test-alerts`, `test-security` |
| Faults | `failover-pod`, `failover-node`, `failover-storage`, `failover-partition`, `chaos` |
| Operations | `backup`, `restore`, `switchover`, `upgrade-minor` |

**Version pinning:**

- One `versions.env` file holds every tool version and image digest. The Makefile includes it.
- `make tools` installs `kubectl` and `k3d` into a git-ignored `./bin`, verifying upstream checksums. **[Verified: downloads and checksum files exist]**
- Project commands put `./bin` first on `PATH`, so system tools remain untouched (HC19).
- `make down` deletes only this project's named k3d cluster.

**Recommendation: A.** Strongest reason: a reviewer can read exactly what is deployed, and nothing resembles a turnkey chart.

---

## MUST coverage

All 55 MUST requirements are listed. "Build" means the requirement is delivered by a build-plan phase rather than an architecture decision.

| Req | Covered by | Req | Covered by |
|---|---|---|---|
| R1.1 | O3 | R6.2 | O13 |
| R1.2 | O1, O2 | R6.3 | O2, O7 |
| R1.3 | O2, O4 | R6.4 | O2, O3 |
| R1.4 | O4 | R7.1 | O13 |
| R1.5 | O5 | R7.2 | O3, O13 |
| R1.6 | O5, O11 | R7.3 | O3, O13 |
| R1.7 | O5, O11 | R7.4 | O1 |
| R2.1 | O2, O7 | R7.6 | O1, O6 |
| R2.2 | O7 | R8.1 | O12 |
| R2.3 | O7 | R8.2 | O12, O13 |
| R3.1 | O2, O6 | R9.1 | O2, O4, O6 |
| R3.2 | O1, O2, O6, O7 | R9.2 | O13, Build B3 |
| R3.3 | O2, O6 | R10.1 | O11 |
| R3.4 | O2, O4, O6 | R10.2 | O11 |
| R3.5 | O2, O6 | R10.5 | O11 |
| R3.6 | O8 | R11.1 | Build B9 |
| R3.7 | O6, O7 | R11.2 | Build B9 |
| R4.1 | O9 | R11.3 | Build B9 |
| R4.2 | O9 | R11.4 | Build B9 |
| R4.3 | O9 | R11.5 | Build B9 |
| R4.4 | O9 | R11.7 | O12, Build B9 |
| R4.5 | O9, O10 | R11.8 | Build, every phase |
| R5.1 | O10 | R12.1 | Build B9 |
| R5.2 | O10 | R12.2 | O13, Build B9 |
| R5.3 | O10 | R12.3 | Build B9 |
| R5.4 | O10 | R12.4 | Build B9 |
| R6.1 | O13 | R12.5 | Build B8, B9 |
| | | R12.6 | Build B8, B9 |

**MUSTs left uncovered: none.** Thirteen are process or submission items with no architecture decision: R11.1–R11.5, R11.7, R11.8 and R12.1–R12.6. They are covered by the build plan.

**MUSTs at highest risk:** R3.7 (thin RTO margin), R3.3 (storage failure may not crash Postgres cleanly) and R4.3 (Garage with pgBackRest is not yet proven).

---

## Candidate pinned versions

Every entry was verified to exist on 2026-11-23, and `versions.env` is now the source of truth. Where the newest release was under about two weeks old, an older stable release is used unless the newer one contains needed fixes.

| Component | Candidate | Verified at | Digest or note |
|---|---|---|---|
| k3s | `rancher/k3s:v1.35.10-k3s1` | Docker Hub | `sha256:8262ca99a558dca0c0437443421986480b2359f9118f2371359f88a41514522f` |
| kubectl | `v1.35.10` | dl.k8s.io | Same minor as k3s. SHA-256 file available |
| k3d | `v5.9.0` | GitHub | Checksums file available |
| PostgreSQL | `postgres:17.12-trixie` | Docker Hub | `sha256:223efeb196329b55b3b9a13db144956411dbc18e727e59f681c3e0aede6475cf` |
| Patroni | `4.1.5-2.pgdg13+1` | PGDG | Upstream `v4.1.5`, 2026-08-12 |
| pgBackRest | `2.60.1-1.pgdg13+1` | PGDG | Released 2026-11-16. Chosen over 2.60.0 for its bug fixes |
| Garage | `dxflrs/garage:v2.5.0` | Docker Hub | `sha256:677e5b758e4425a325b811c425c026bf35a4bf42f7ddbaa773de3f4fd779a5a5` |
| curl (Garage bootstrap) | `curlimages/curl:8.23.0` | Docker Hub | `sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93` |
| Prometheus | `prom/prometheus:v3.16.0` | Docker Hub | `sha256:e04987641b57704f408e31f6373ba4138ecf27cb4a165d24aabb6c38fddd0f06` |
| Alertmanager | `prom/alertmanager:v0.34.2` | Docker Hub | `sha256:39d8bb3966c694a124428a3a88fbcffd40bd069129ecd47c059f8a3f17c55f3b` |
| postgres_exporter | `quay.io/prometheuscommunity/postgres-exporter:v0.20.1` | Quay | `sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e`. CI-tested on PG 17 |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0` | registry.k8s.io | `sha256:42cfe3723a5f058171c627537fb57a3ea0f26e4380fa18555a95cb1a1b4cfc5b`. Built against client-go v1.36, one minor from k3s |
| node_exporter | `prom/node-exporter:v1.12.1` | Docker Hub | `sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0` |
**Why PostgreSQL 17 rather than 18.7:** both are available, but 18 adds no benefit for any MUST, and 17 has a longer field history with this toolchain.

**Estimated memory for the recommended design [Assumption]:** about 8.3 GiB of 15.6 GiB at peak, including host, four k3s nodes, three Postgres pods and transient backup and restore Jobs. The capacity table in `docs/environment.md` still assumes three nodes and should be replaced with measured values in B8.

---

## Build plan

The lean plan is **16 focused hours** and keeps every MUST. It has no spare contingency, so the cut lines are part of the plan. Docs, playbook, video and submission (L8) are separate.

| Phase | Work | Key exit check | Hours | Cumulative |
|---|---|---|---:|---:|
| **L0** | `make tools`, `preflight`, `certs`, generated Secrets, k3d cluster, image, **spikes S1–S4** | Spikes pass and 4 nodes Ready | 2.5 | 2.5 |
| **L1** | StatefulSet, Patroni, RBAC, Services, sync replication, slots, rewind | `T:topology`, `T:replication`, `T:endpoints` pass | 2.5 | 5.0 |
| **L2** | One parameterised failure harness: pod, node, storage, isolation, switchover, RTO | All modes run 3 times, with real RTO recorded | 3.0 | 8.0 |
| **L3** | Garage, pgBackRest, archiving, backup CronJob, retention | Archive, backup and retention tests pass | 2.0 | 10.0 |
| **L4** | Full restore, PITR, shared restore-test Job | `T:restore-full`, `T:pitr`, `T:restore-verify` pass | 2.5 | 12.5 |
| **L5** | Prometheus, Alertmanager, exporters, required alert rules | `T:metrics` and rule unit tests pass | 1.5 | 14.0 |
| **L6** | Remaining security baseline, security doc | Security tests pass | 1.0 | 15.0 |
| **L7** | Clean-host run, evidence, traceability, measured capacity | `make down && make up && make test` passes | 1.0 | **16.0** |
| **L8** | Docs, playbook, session logs, redaction, video, submission | Submission sent | Separate | |

**What changed from the 23.5-hour plan**

| Change | Saved |
|---|---:|
| Decisions and ADRs completed before the build starts | 1.0 h |
| Bootstrap combined: one `make certs`, no MinIO build | 0.5 h |
| Patroni core built with rewind in one pass | 0.5 h |
| One failure harness instead of separate scripts | 1.0 h |
| Garage image and repository encryption instead of a store build plus TLS work | 1.0 h |
| One restore path and shared test Job | 0.5 h |
| Monitoring limited to required rules first, no Grafana | 1.0 h |
| Security reuses the bootstrap CA and Secrets, built last | 1.5 h |
| Evidence captured during each phase instead of at the end | 0.5 h |
| **Total** | **7.5 h** |

**Out of scope from the start:** Grafana and R10.4, connection pooling, image scanning, simulated zones, `failsafe_mode`, differential backups and quorum replication.

**Spikes in L0, run first because they can invalidate a decision:**

| Spike | Question | If it fails |
|---|---|---|
| S1 | Does pgBackRest complete stanza creation, backup, archive and restore against Garage? | Evaluate SeaweedFS, with MinIO from source as last resort |
| S2 | Does k3s enforce NetworkPolicy, including egress to the API server? | Use ingress-only policy and document it |
| S3 | Can UID 999 create a 0700 `PGDATA` on a local-path volume? | Add a minimal init step and document the exception |
| S4 | Is v1 Endpoints served at runtime, and how long does EndpointSlice mirroring take? | Reassess O7 before L2 |

**SHOULD cut lines**

MUST items are never cut. SHOULDs are cut from the lowest priority upward, so security goes first and replication and failover go last. R11.6 (Gemini comparison, OPTIONAL) is dropped before any SHOULD.

| Cut | Trigger (cumulative hours) | Cut | Priority |
|---|---|---|---|
| **C1** | L2 exits after 9.0 h | R8.8 RBAC audit, R8.7 Pod Security `restricted` | Security |
| **C2** | L3 exits after 11.5 h | R8.6 NetworkPolicy, R8.4 TLS enforcement for clients | Security |
| **C3** | L4 exits after 14.0 h | R10.3 proof that alerts fire on real faults | Monitoring |
| **C4** | L5 exits after 15.5 h | R9.6 archive-outage test, R5.5 PITR across a timeline, R4.6 backup after failover | Backup and PITR |
| **C5** | L6 exits after 16.5 h | R9.3, R9.5 and R2.4 tests. R9.7 stays as documentation only | Replication and failover |

**Kept even at C5** because they cost almost nothing or other work depends on them: R8.3, R8.5, R6.5, R7.5 and R9.4.

**Feature freeze** comes when L7 ends. Unfinished items go to known limitations with the reason (HC10).
