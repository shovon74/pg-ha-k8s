# ADR-009: Backups

**Status:** Accepted

## Context

We need scheduled base backups, continuous WAL archiving, enforced retention and automatic verification. D4 forbids `kubectl exec` in backup paths, so a CronJob needs a network route to the database host.

## Options considered

- **pgBackRest:** built-in `expire` and `verify`, plus a TLS server that scheduled Jobs can reach.
- **WAL-G:** small and simple, but base backups need an in-pod trigger.

## Decision

Use **pgBackRest 2.60.1** with the object store from ADR-014:

- A full backup daily at 20:00 UTC through a CronJob.
- Continuous asynchronous WAL archiving.
- `repo1-retention-full=7`, enforced by automatic `expire`.
- `pgbackrest verify` daily after the backup.
- A single **`make certs`** bootstrap step creates one CA, reused for the pgBackRest TLS server and Postgres TLS.

**Repository settings live in one place.** Every `repo1-*` setting goes in a single `repo.conf`, loaded from pgBackRest's `conf.d` include path. The main config holds only stanza, Postgres and process settings.

- Backup, archive, restore and restore-test workloads all read the same `repo.conf`.
- Credentials never go in `repo.conf`. They come from Kubernetes Secrets at runtime.
- The default `repo.conf` targets Garage with `repo1-type=s3`.
- A later GCS overlay (R4.7) replaces that one file with `repo1-type=gcs`, `repo1-gcs-bucket` and `repo1-gcs-key-type`, and leaves out the Garage workloads. Use `auto` for keyless identity where available. Otherwise use `service`, with a key file supplied at runtime from outside the repo.
- **The overlay is not built yet.**

## Consequences

- A check at L3 must confirm that no `repo1-*` setting exists outside `repo.conf`.
- The GCS overlay must also allow egress to GCS in NetworkPolicy and create its stanza in an empty bucket path.
- TLS certificates become a bootstrap dependency, so that work is done once.
- R4.1 needs evidence from a truly scheduled Job, so a cluster must stay up across one schedule.
- The repository cipher passphrase becomes critical: losing it makes backups unrecoverable.

## R-IDs covered

R4.1, R4.2, R4.3, R4.4, R4.5, R4.6, R4.7, R8.10
