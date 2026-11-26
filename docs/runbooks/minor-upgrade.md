# Runbook: PostgreSQL minor-version upgrade

Raises the PostgreSQL minor version (for example 17.12 to 17.13) on all three members with one controlled switchover (R6.4).

**Status: documented only, not executed.** No newer pinned 17.x image was built and no upgrade was run. R6.4 allows a documented procedure; [`../known-limitations.md`](../known-limitations.md) records that it was not executed. The building blocks it relies on (`make image`, `make deploy`, `make switchover`, rejoin with a restart) are each tested elsewhere.

A minor upgrade replaces binaries only. The data directory format is the same, so no `pg_upgrade` and no re-clone are needed. Read the release notes of every skipped minor for extra steps (for example a `REINDEX` after a fix).

## 1. Pin the new version

Edit `versions.env`:

```text
POSTGRES_BASE_IMAGE=postgres:17.13-trixie@sha256:<digest of that tag>
```

Pin both the tag and the digest. Get the digest with `docker buildx imagetools inspect postgres:17.13-trixie`. If PGDG has newer Patroni or pgBackRest packages you want, change `PATRONI_DEB_VERSION` and `PGBACKREST_DEB_VERSION` separately, in a different change, so one upgrade changes one thing.

The image tag is derived from these pins (`scripts/lib.sh`), so the new image gets a new tag, for example `pg-ha-postgres:17.13-patroni4.1.5-pgbackrest2.60.1`.

## 2. Build and import the image

```bash
make image
```

It builds from the pinned inputs, prints `postgres --version`, and imports the image into every k3d node.

## 3. Stop the StatefulSet from rolling by itself

`make deploy` changes the StatefulSet's image. With the default `RollingUpdate` strategy Kubernetes would restart pods from the highest ordinal down, whichever member is primary. Switch to `OnDelete` first, so a pod gets the new image only when we delete it:

```bash
kubectl -n pg-ha patch sts pg --type merge -p '{"spec":{"updateStrategy":{"type":"OnDelete","rollingUpdate":null}}}'
make deploy
```

The manifest does not set `updateStrategy`, so `make deploy` (`kubectl apply`) leaves the patched value alone. The backup and restore-test CronJobs pick up the new image for their next run, which is fine: pgBackRest is unchanged.

## 4. Upgrade the replicas, one at a time

```bash
make status                                   # note the leader, for example pg-0
kubectl -n pg-ha delete pod pg-2              # a replica: it is recreated on the new image
make status                                   # wait until pg-2 is streaming with near-zero lag
kubectl -n pg-ha delete pod pg-1              # the other replica
make status
```

Never delete the leader pod in this step. Check each upgraded replica:

```bash
kubectl -n pg-ha get pod pg-2 -o jsonpath='{.spec.containers[0].image}'
```

and `SELECT version();` on it through the test client.

## 5. Switch over to an upgraded replica

```bash
make switchover TO=pg-2
```

See [`switchover.md`](switchover.md). This is the only interruption for clients: a few seconds of write gap, measured by the harness, with RPO 0.

## 6. Upgrade the old primary

The old primary is now a replica on the old image:

```bash
kubectl -n pg-ha delete pod pg-0
make status
```

It restarts on the new image and rejoins with a restart only (it did not diverge).

## 7. Verify and clean up

- `make status`: 1 leader, 2 streaming replicas, 1 sync standby.
- Every pod's image is the new tag, and `SELECT version()` reports the new minor on all three.
- `make backup`, then `make test-restore`. A fresh backup on the new binaries proves the backup path.
- Restore the default strategy: `kubectl -n pg-ha patch sts pg --type merge -p '{"spec":{"updateStrategy":{"type":"RollingUpdate"}}}'`.

## Rollback

A minor downgrade is also binary-compatible. Revert `versions.env`, `make image`, and repeat steps 3 to 6 with the old tag.
