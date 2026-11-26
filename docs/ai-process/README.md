# How this was built with AI

This is the playbook for how the system was built (R11.1). It is written so a reviewer can follow the work from the brief to the last evidence file, and so the same method can be reused by another engineer or another agent.

## Roles

- **The lead** (the human) made every decision, reviewed every phase and owns every line (R11.8).
- **Claude Code** was the implementer. It ran in this repository on the VM, wrote the code and docs, ran the tests and wrote the evidence.
- **A separate Claude chat acted as consultant.** Planning, reviews of design options, and review of each phase prompt before it was given to Claude Code were done there. The consultant never touched the repository. Its suggestions reached Claude Code only through prompts the lead wrote or approved.

The raw Claude Code session logs are in [`ai-logs/`](../../ai-logs/README.md), redacted under D5, with a table mapping each session to its phase. The consultant chats are not Claude Code sessions and are not included there.

## The method

```text
brief.pdf ─► requirements with R-IDs and acceptance tests (P0)
          ─► lead decisions D1-D9 (P0)
          ─► design options, 2-3 per decision, with R-IDs and effort (P1)
          ─► lead picks; ADRs record each choice (P1)
          ─► lean plan: phases L0-L8 with exit checks and cut lines (P1)
          ─► per phase: prompt ─► plan ─► small steps with checks ─► evidence by `make` ─► lead review ─► commit
```

The generic rules every agent follows are in [`docs/process/working-rules.md`](../process/working-rules.md): plan before code, small verified steps, stay in scope, state assumptions, prove claims, report honestly, pin versions, keep secrets out, ask before destructive or host changes, commit only when asked.

## Phases

Each phase started from a prompt written by the lead (reviewed with the consultant) and ended with a lead review and one commit. The prompts are in the session logs. The Phase 1 prompt was also saved verbatim, so it can be rerun by another agent.

| Phase | Input and prompt | Output | Verification and evidence |
|---|---|---|---|
| P0 Requirements | Brief; prompt in session `b2ebea08` | [`00-requirements.md`](../00-requirements.md) with R-IDs, acceptance tests, hard constraints, D1-D9; [`environment.md`](../environment.md); working rules | Lead review of every R-ID against the brief (commit `a03ecaa`) |
| P1 Design | [`prompts/p1-design-options.md`](../process/prompts/p1-design-options.md) | [`01-design-options.md`](../01-design-options.md), ADR-001 to ADR-014, version pins, lean plan | Lead decisions recorded in each ADR (commits `d1c707f`, `f86a3b8`) |
| L0 Bootstrap | Session `38dd8981`, then `e73dfe31` | `make tools/certs/secrets/cluster/image`, spikes S1-S4 | `make spikes`; `docs/evidence/L0-spike-*.md` (commit `5b064b5`) |
| L1 Replication | Session `e73dfe31` | StatefulSet, Patroni on the Kubernetes API, sync standby, slots, `pg-rw`/`pg-ro`, seed | `make test-replication`; `L1-replication.md` (commit `6966edf`) |
| L2 Failover | Session `e73dfe31` | One failure harness for pod, node, storage, split-brain, switchover | `make test-failover`; `L2-failover.md` with RTO and RPO per run (commit `b53d48f`) |
| L3 Backup | Session `e73dfe31` | Garage, pgBackRest, archiving, CronJob, retention, re-clone rejoin | `make test-backup`; `L3-backup.md` (commit `8ffa86c`) |
| L4 Restore | Session `e73dfe31` | `make restore`, PITR, restore-test Job, runbooks | `make test-l4`; `L4-restore.md` (commit `88cc7b9`) |
| L5 Monitoring | Sessions `d597e1ae`, `ef576bb9` | Prometheus, Alertmanager, exporters, 19 alerts | `make test-l5`; `L5-monitoring.md` (commits `baf5db1`, `454969f`) |
| L6 Security | Session `ef576bb9` | TLS, SCRAM, roles, NetworkPolicies, REST API auth, Pod Security, RBAC | `make test-security`; `L6-security.md` (commits `454969f`, `3bd5765`) |
| L7 Clean run | Session `cf5397ce` | `scripts/l7-clean-run.sh`: `make down`, `make up`, `make seed`, every test | [`L7-clean-run.md`](../evidence/L7-clean-run.md) |
| L8 Docs | Session `cf5397ce` | README, runbooks, known limitations, this folder, `scripts/export-logs.sh` | Lead review; log export with secret scan |

**Commit note.** Commit `454969f` contains the L6 security work (TLS, NetworkPolicies, REST API auth and the rest of the security baseline) although its message says `feat(l5)`. Commit `3bd5765` says so in its own message. History was not rewritten.

## Human decisions

**Lead decisions before design (D1-D9, in [`00-requirements.md`](../00-requirements.md)):**

| ID | Decision |
|---|---|
| D1 | No operators of any kind, including for supporting components |
| D2 | No third-party Helm charts; our own minimal manifests |
| D3 | Our own Postgres image from the official image plus Patroni |
| D4 | `kubectl exec` only in committed, automated test scripts, each use documented |
| D5 | Redact only credentials and personal or cloud identifiers, visibly, with a log |
| D6 | Node failure = stop a k3d agent; storage failure = make the data volume unavailable |
| D7 | Reference machine: 4 vCPU, 16 GB, reduced footprint |
| D8 | RTO target 30 s, real RTO per mode; RPO measured; 100-200 MB dataset |
| D9 | Public repository, no secrets committed |

**Key review decisions during the build:**

- **Garage instead of MinIO** (ADR-014). MinIO's upstream repository is archived and its prebuilt artifacts are gone. Building it from source was on the table; the lead rejected shipping unmaintained software as the main path. Garage was chosen over SeaweedFS, and spike S1 proved pgBackRest works against it before any build work.
- **Re-clone instead of `pg_rewind`** (ADR-008, revised in L3). A rewound member that later became primary blocked WAL archiving permanently (pgBackRest error 045). A wrapper that ignores error 045 was considered and rejected, because it would silence a real split-brain signal exactly where it must be loud. The lead chose re-clone, and L4 added `make failover-diverge` to prove it.
- **Honest RTO.** Node failover RTO was first over 30 s because CoreDNS ran on a database node. Unsafe tuning (a shorter leader TTL) was ruled out by the lead's constraints. The fix was structural (pin CoreDNS to the server node, ADR-001), and runs over 30 s are reported as OVER TARGET, never hidden.
- **No `failsafe_mode`** (ADR-002). Writes stop during an API outage rather than risk two primaries.
- **Grafana, the second-agent comparison (R11.6) and the GCS overlay (R4.7) cut** to protect every MUST ([`known-limitations.md`](../known-limitations.md)).
- **Backup connectivity race** (L6). After three backup Jobs failed, the lead stopped the regression for a read-only diagnosis instead of a retry. The cause (kube-router admits a new pod a fraction of a second after start) was proven with a probe Job before the fix.

## Rules that kept it honest

- **Two strikes.** A failing step is retried once. If it fails again, the agent stops, diagnoses read-only and reports, instead of looping on changes.
- **Gates.** A phase is done only when its `make test-*` gate passes and the evidence file is regenerated. The lead reviews before commit.
- **History files.** Every phase has a hand-written `*-history.md` recording failures, test bugs, fixes and decisions, next to the generated evidence.

More detail: [determinism](determinism.md), [agent-agnostic method](agent-agnostic.md), [generalisation](generalisation.md).
