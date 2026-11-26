# L6 history: security baseline

Hand-written notes for L6. The generated results are in [`L6-security.md`](L6-security.md), and the design is in [`../security.md`](../security.md). Times are UTC (the lead works in UTC+6). Sessions on 2026-11-25 and 2026-11-26. Deadline Thu 26 Nov 23:59 Asia/Dhaka (17:59 UTC).

## Order of work

| Time (UTC) | Step |
|---|---|
| 17:07 | Start. Read CLAUDE.md, working rules, ADR-012, the L0, L4 and L5 phase notes, R8.x, and spike S2 |
| 17:10 | Step 0: helper Jobs (stanza, check) made from the `pg-backup` template no longer get an ownerReference, so they cannot take a slot in the CronJob's history (below). `make test-alerts` PASS |
| 17:12 | Postgres change deployed first (`make deploy`): `hostssl` + SCRAM `pg_hba`, verify-full for replication and rewind, Patroni REST API auth, new `pg-restapi-password`. **This rolled the three Postgres pods, before any test.** Rollout took 43 s, then Patroni healthy on timeline 39 |
| 17:14 | NetworkPolicies applied (`make netpol`): 16 policies in `pg-ha`, `monitoring` and `monitoring-host`. Patroni stayed healthy, API-proxy reads worked, 14 of 14 targets up |
| 17:15 | `make deploy` again for the new pod labels (`pg-ha/db-client`, `garage-bootstrap`). Garage bootstrap, stanza-create and check passed under default deny. Postgres pods not rolled |
| 17:19 | First `make test-security`: 82 PASS, 20 FAIL, all harness bugs (below). Fixed |
| 17:21 | `make test-security` rerun: 102 of 102 PASS |
| 17:22 | Regression run, one target at a time (table below) |
| 17:26 | `make backup` failed twice. Regression stopped, read-only diagnosis, report |
| 26 Nov 14:07 | Lead re-sent the phase instructions. Resumed on the open backup failure |
| 14:08 | Hypothesis confirmed with a credential-free probe Job, then fixed in `backup-job.sh` (below) |
| 14:08 | `make deploy` with the fix. **Rolled the three Postgres pods** (43 s), Patroni healthy |
| 14:09 | Regression resumed: backup, restore test, alerts, metrics (one test bug found and fixed), then replication, failover-pod and security rerun on the final state |
| 14:21 | All regression targets PASS |

## Regression after hardening

First pass (25 Nov), stopped by the backup failure:

| Target | Start (UTC) | Result | Notes |
|---|---|---|---|
| `make test-replication` | 17:22:40 | PASS (27 s) | |
| `make failover-pod RUNS=1` | 17:23:07 | PASS (87 s) | RTO 2.72 s, RPO 0 (134 acknowledged rows), one primary throughout |
| `make switchover` | 17:24:34 | PASS (65 s) | Authenticated `POST /switchover`, lock pg-0 to pg-1 |
| `make backup` | 17:25:39 | **FAIL** (5 s) | `FINGERPRINT_FAILED`: `psql` to `pg-rw:5432` refused (below) |
| `make backup` (one retry) | 17:26:13 | **FAIL** | Same error, about 1 s after the pod started. **Second failure, so the phase stopped here** |
| `make test-restore` | 17:25:44 | **FAIL** (35 s) | Its first step is a backup Job, which failed the same way. The negative run (injected mismatch) behaved correctly. `L4/restore-test.md` now records this FAIL |
| `make test-alerts` | 17:26:19 | PASS (4 s) | |
| `make test-metrics` | 17:26:23 | **Not completed** | Stopped by the agent after the second backup failure. Its pre-check had already failed ("no warning or critical alert firing"), because the failed backup Jobs raised alerts. No fault was injected, no evidence file was written, and no iptables rule was left behind (checked on all three agents) |

Final pass (26 Nov), after the backup fix. The fix rolled the Postgres pods, so replication, failover and security were rerun on the final state:

| Target | Start (UTC) | Result | Notes |
|---|---|---|---|
| `make backup` | 14:09:30 | PASS (45 s) | "pg-rw reachable after 3 attempts", backup `20261126-140935F`, verify `status: ok` |
| `make test-restore` | 14:10:21 | PASS (72 s) | Every fingerprint value matched; the negative run failed as it should |
| `make test-alerts` | 14:11:46 | PASS (4 s) | |
| `make test-metrics` | 14:11:51 | **FAIL** (177 s) | Peaks read 0 although ReplicationLagHigh/bytes fired. Test bug, below |
| `make test-metrics` (after the test fix) | 14:15:42 | PASS (153 s) | Peak 218.6 MB and 124.6 s, alert fired and resolved, no iptables rule left on any agent |
| `make test-replication` | 14:18:25 | PASS (27 s) | |
| `make failover-pod RUNS=1` | 14:18:52 | PASS (84 s) | RTO 4.40 s, RPO 0 (132 acknowledged rows), one primary throughout |
| `make test-security` | 14:20:16 | PASS (56 s) | 102 of 102 |

`make switchover` passed in the first pass (authenticated) and was not repeated: the fix changed only the backup script.

## Resolved: backup Job could not reach pg-rw under the NetworkPolicies

**Symptom (25 Nov).** The backup Job's first action, the read-only fingerprint query (`psql host=pg-rw` as `app_ro`), got "Connection refused" about 1 s after the pod started. Both manual runs and the scheduled run at 20:00 failed this way. A refusal (not a timeout) is how kube-router rejects a denied connection. Pod labels and policies were correct, and the long-lived test client with the same label connected fine.

**Cause, confirmed 26 Nov.** kube-router admits a new pod's IP to its policy sets a fraction of a second after the pod starts. A helper Job from the same template (`scripts/pgbr-job.sh pg-netpol-race-probe`, no exec, no credentials) ran `pg_isready -h pg-rw` every 200 ms from start: "no response" at 217 ms, "accepting connections" at 506 ms. psql made one attempt inside that window. pgBackRest's stanza and check Jobs connect later, which is why they passed.

**Fix.** `backup-job.sh` waits up to 30 s (60 × 0.5 s) for `pg_isready` on pg-rw before the fingerprint query. It sends no credentials, and it does nothing measurable without policies. The fixed backup logged "pg-rw reachable after 3 attempts". A real outage still fails the Job, with `FINGERPRINT_FAILED` after the wait.

**Side effects left.** The failed Jobs `pg-backup-29927280`, `pg-backup-manual-20261125172539` and `pg-backup-manual-20261125172613` remain until the CronJob's failed-history limit or a manual cleanup removes them. `BackupJobFailed` stopped firing once a backup succeeded.

## Test bug found in the regression: lag peak read from a stale series

`tests/l5-metrics.sh` read the peak as `max_over_time(lag[10m])` and took the first result. The fix's rolling restart moved the leader 2 minutes before the test, so the query returned three series: two from earlier pg-1 instances (peak 0) and the current primary pg-2 (218 MB). The test reported peak 0 while ReplicationLagHigh fired. Every lag read now aggregates with `max()`. This also protects the "back to near zero" check, which could otherwise pass on a stale zero series.

## Step 0: helper Jobs and BackupStale

`kubectl create job --from=cronjob/pg-backup` sets an ownerReference to the CronJob. The CronJob controller counts every owned, finished Job against `successfulJobsHistoryLimit: 3` and deletes the oldest. `make deploy` and several L3 tests create `pg-stanza-create` and `pg-check-*` Jobs this way. A few of them could evict the last real `pg-backup-*` Job, and `BackupStale` (which counts only `pg-backup-.+` Jobs) would then fire although a backup had succeeded. Seen at the start of L6: `pg-stanza-create` was owned by `pg-backup`.

Fix in `scripts/pgbr-job.sh`. A Job with its own command is a helper: no ownerReference, no `cronjob.kubernetes.io/instantiate` annotation, label `pg-ha/job-kind=helper`, and `ttlSecondsAfterFinished: 86400`. Its pod keeps the template's labels, so the same NetworkPolicies apply. Verified live (`pg-check-l6-step0` had no owner, label `helper`, TTL 86400). The existing unit tests already cover "a recent stanza Job does not count". `make test-alerts` PASS.

## Decisions taken during the phase

- **Policies live in `deploy/netpol`, not `deploy/pg`.** The restore overlay inherits `deploy/pg`, and the policies name pg-ha-specific sources. `pg-restore` stays without policies (documented).
- **API-proxy sources are three server-node addresses.** The API server's pod and service proxy connects from the server node: its InternalIP, its flannel tunnel address (podCIDR `.0`) or its cni0 address (podCIDR `.1`, for pods on the server node, such as Prometheus). `scripts/netpol.sh` derives all three from the control-plane node object. Which one is used on each path was not isolated. All three are addresses owned by the node, not pod addresses.
- **One client label instead of a list of names.** `pg-ha/db-client=true` marks every pod that may connect to 5432 (test client, probe, seed, API-outage probe, backup Job). A namespace with the same label can hold application clients.
- **Remote superuser login is rejected outright.** Patroni, `post_bootstrap` and pgBackRest all use the local socket, and replication and the divergence check use their own roles. The regression (failover, switchover, re-clone paths, backup, restore test) confirms nothing needs it.
- **Loopback stays `host`, not `hostssl`.** The two `127.0.0.1/32` lines serve the exporter sidecar and Patroni's local replication check. That traffic never leaves the pod. The exporter uses `sslmode=require` anyway.
- **REST API auth without TLS.** Basic auth on state-changing calls, with GET open. Adding TLS would also change the probes, the scrape job and the proxy-based helpers. Left out and documented.
- **The authenticated REST test is a scheduled switchover, then its cancellation.** It proves the credential is accepted on a state-changing endpoint without moving the leader. Each unauthenticated request was chosen to be harmless even if auth were missing. `make switchover` covers a real authenticated switchover.

## Bugs found while building the test (first run, 17:19)

All 20 failures of the first run were in the test script, not in the system:

1. **Quoting.** Checks pasted command output into `bash -c '...'`. The `pg_hba` rules contain "Patroni's", whose apostrophe broke the quoting. All such checks were rewritten as functions that read the output from a variable.
2. **Field separator.** psql's unaligned output uses `|`, and the role checks expected spaces. Fixed with `-F " "`. The role values themselves were already correct.
3. **`set -u` and `local`.** `local m=$1 ... args=(... -X "$m")` expands `$m` before it is assigned, so every REST request went out with an empty method. Patroni answered 501 even for GET. The locals were split.
4. **Replication probe.** `replication=database` (logical walsender) matches the `all` database rule, and is then refused because `app` has no REPLICATION attribute. That is a valid refusal, but not the `pg_hba` one the check expected. The test now runs both: physical (`replication=true`, refused by `pg_hba`) and logical (refused by the role attribute).
5. **Cosmetic.** `${4/-/the cluster}` replaced the first `-` of `pg-ha` in check names.

Also corrected after reading the evidence: kube-router *rejects* a denied connection (immediate refusal), it does not drop it. The note and probe label now say "rejected". Each port's listening state is proven by an allowed path in the same run.

## kubectl exec disclosure (D4)

`kubectl exec` was used only inside committed test scripts: `tests/test-security.sh` (its own `pg-test-client` and throwaway `outsider` pod) and the existing L1 to L5 harnesses during regression. No exec was run by hand, and none targeted a Postgres, Garage or monitoring pod. On 26 Nov one hand-typed command included `kubectl exec deploy/alertmanager -- true`. The permission check blocked it before it ran, and it was removed. Read-only `docker exec <agent> iptables -S FORWARD` was run by hand to confirm that test-metrics left no rule behind. The race probe was a Job, not an exec. The REST API was reached by `kubectl port-forward`, as in the L2 switchover harness.

## Cuts

No R-ID was cut. The regression gate (step 6) is met as of 26 Nov 14:21 UTC (all targets PASS, final pass above). Left out by design, as listed in `security.md`: client certificate auth, secret rotation tooling, image scanning (R8.9), TLS for Garage and the REST API, cert-manager, Secrets encryption at rest, policies in `pg-restore`, an API audit policy, and the raw-bucket encryption proof (R8.10).
