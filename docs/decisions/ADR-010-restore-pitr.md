# ADR-010: Restore and PITR

**Status:** Accepted

## Context

The whole cluster must restore into an empty namespace, support PITR to a timestamp, and prove backups through a scheduled or on-demand test.

## Options considered

- **Patroni custom bootstrap:** restored cluster uses the same HA path as production.
- **Pre-restore Job per PVC:** separates steps but repeats work.
- **Test trigger:** one Job template used by CronJob and `make`, or `make` only.

## Decision

- Restore through **Patroni custom bootstrap** in a Kustomize overlay.
- Run PITR with `--type=time` and `--target-action=promote`. `TARGET_TIME` must include a timezone offset.
- Use **one restore-test Job template** for both a daily CronJob and `make test-restore`. It restores into `emptyDir`, starts Postgres without network exposure, checks marker data and `pg_amcheck`, then exits.
- A restored cluster must **not** archive into the source stanza.

## Consequences

- A passing test exercises the real recovery path.
- **Confirmed in L4:** Patroni runs `post_bootstrap` after a custom bootstrap too, and resets the superuser, replicator and rewind passwords itself. `post-bootstrap.sh` is create-or-alter: on a restored cluster it resets the `monitor`, `backup`, `app` and `app_ro` passwords to the target namespace's Secret.
- **Implementation (L4):**
  - `scripts/restore.sh` renders `deploy/restore/30-restore.yml`: bootstrap method `pgbackrest`, recovery target and timeline, and `archive_mode: "off"`.
  - `restore-bootstrap.sh` lets pgBackRest choose the backup set. It then removes the recovery settings pgBackRest wrote to `postgresql.auto.conf`, so Patroni's `recovery_conf` drives recovery, and nothing is copied to replicas or kept after promotion.
- **Restore test data check (L4):** the backup Job records a fingerprint (row counts and `hashtext` sums of the seeded tables) as pgBackRest annotations on each backup. The restore test restores that backup with `--type=immediate` and compares the fingerprint. Its reading role, `app_ro`, is the only database credential the backup Job holds.
- In-cluster object storage is lost with the cluster, so this proves namespace-level recovery and not off-site disaster recovery.

## R-IDs covered

R4.5, R5.1, R5.2, R5.3, R5.4, R5.5
