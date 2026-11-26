# Runbook: planned switchover

Moves the primary role to a chosen replica with no data loss, for maintenance on the current primary's node or as one step of a [minor upgrade](minor-upgrade.md) (R6.3). **Status: implemented and executed.** `make switchover` is part of the L2 gate and the L7 clean run; evidence in [`../evidence/L2/switchover.md`](../evidence/L2/switchover.md).

## 1. Check the cluster is healthy

```bash
make status
```

Expect 1 leader, 2 streaming replicas, 1 sync standby and lag near zero. Do not switch over to a replica that is lagging or not streaming. Patroni refuses a candidate that is not healthy, but checking first avoids a refused request.

## 2. Switch over

```bash
make switchover                 # to the current sync standby (no data loss, shortest catch-up)
make switchover TO=pg-1         # to a named member
```

What it does (`tests/failover.sh switchover`):

- Sends `POST /switchover` with `{"leader": <current>, "candidate": <target>}` to the leader's Patroni REST API over `kubectl port-forward`.
- Authenticates with the REST API credential from `./secrets` (L6). The credential is passed to curl on stdin, never on the command line or in the evidence.
- Runs a probe Job that writes through `pg-rw` every 500 ms, so the write gap (RTO) and missing rows (RPO) are measured.

Patroni stops the old primary cleanly, the target promotes, and the `pg-rw` endpoint follows the leader key. The old primary has not diverged, so it rejoins as a replica with a restart only (no re-clone, ADR-008).

## 3. Confirm

```bash
make status
```

- The target is the leader and the timeline went up by one.
- The old primary is a streaming replica. One of the replicas is the sync standby.
- The evidence file reports RPO 0 and the RTO. The measured RTO is in [`../evidence/L2-failover.md`](../evidence/L2-failover.md).

## If it fails

- **HTTP 401:** the REST API credential in `./secrets` does not match the deployed Secret. Run `make deploy` to reapply it.
- **HTTP 412 or "candidate not healthy":** the target is not streaming or lags. Wait, or choose the sync standby.
- **Lock did not move within 90 s:** the harness fails the run. Check `kubectl -n pg-ha logs pg-N -c postgres` on both members. Patroni keeps the old leader if the switchover fails, so the cluster stays writable.

## Manual alternative

Without the harness, the same request can be sent with curl through `kubectl -n pg-ha port-forward pod/<leader> 8008:8008`, using the REST API user and password from `./secrets`. Do not paste the password into a command line that is logged.
