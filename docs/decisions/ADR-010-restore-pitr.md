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
- Restored role passwords must be reset through `post_bootstrap`, to be confirmed during implementation.
- In-cluster object storage is lost with the cluster, so this proves namespace-level recovery and not off-site disaster recovery.

## R-IDs covered

R4.5, R5.1, R5.2, R5.3, R5.4, R5.5
