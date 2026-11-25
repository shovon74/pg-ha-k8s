# Runbook: restore the whole cluster

Restores the cluster from the pgBackRest repository in Garage into the empty namespace `pg-restore`, as 1 primary and 2 streaming replicas (ADR-010, R5.1, R5.2). For a restore to a point in time, see [`pitr.md`](pitr.md). Times are UTC unless an offset is given.

## Before you start

- The source cluster and Garage are up (`make status`), and `./secrets` is the one the backups were taken with. Without its repository passphrase, backups cannot be decrypted.
- Only `pg-restore` is accepted as a target. The L0 certificates name only `pg-ha` and `pg-restore`.
- `pg-restore` must be empty. If an earlier restore is still there, remove it first:

```bash
make restore-clean
```

## Restore to the latest state

```bash
make restore NS=pg-restore
```

What it does (`scripts/restore.sh`):

1. Creates `pg-restore` and copies the Secrets `pg-credentials`, `pg-tls`, `pgbackrest-tls` and `pgbackrest-repo` from `pg-ha`, server-side, without printing them.
2. Renders `deploy/restore/30-restore.yml` (git-ignored): Patroni custom bootstrap with `pgbackrest restore`, recovery to the end of the archive on timeline `latest`, then promote. It also sets `archive_mode: "off"`, so **the restored cluster never archives into the source stanza**.
3. Applies the `deploy/restore` overlay: the same manifests as production, without the backup and restore-test CronJobs.
4. `pg-0` restores and recovers. `post_bootstrap` then resets the application role passwords to this namespace's Secret. `pg-1` and `pg-2` clone from `pg-0`.
5. Waits until Patroni reports 1 leader, 2 streaming replicas and 1 sync standby, then prints `RESTORE_OK` with the time to a ready primary and to a healthy cluster.

Options: `TARGET_TIMELINE=<n>` restores along a specific timeline instead of `latest`. `RESTORE_WAIT=<s>` changes the timeout (default 1200 s).

## Check the result

```bash
kubectl -n pg-restore get pods -o wide
kubectl get --raw /api/v1/namespaces/pg-restore/pods/pg-0:8008/proxy/cluster | jq '.members[] | {name, role, state, timeline}'
```

Clients connect to `pg-rw.pg-restore.svc.cluster.local:5432` (read-write) or `pg-ro.pg-restore.svc.cluster.local` (read-only), with the same credentials as the source.

`make test-restore-full` runs the whole sequence and compares row counts and checksums with the source. Evidence: `docs/evidence/L4/restore-full.md`.

## If it fails

- `namespace pg-restore is not empty`: run `make restore-clean`, then retry.
- Not healthy before the timeout: look at the restoring member first.

```bash
kubectl -n pg-restore logs pg-0 -c postgres | grep -E 'custom bootstrap|restore|recovery|ERROR|FATAL'
```

- `pgbackrest restore` errors usually mean that the repository or credentials are wrong. Check that `pgbackrest-repo` exists in `pg-restore` and that Garage is Ready in `pg-ha`.

## Clean up

```bash
make restore-clean
```

It deletes only the `pg-restore` StatefulSet, its PVCs and the namespace. It refuses any other namespace.

## Limits

The repository lives in Garage inside the same cluster and VM. This proves namespace-level recovery, not off-site disaster recovery (known limitations, ADR-014).
