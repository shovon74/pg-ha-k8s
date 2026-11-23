# ADR-003: Postgres image

**Status:** Accepted

## Context

D3 requires our own image from the official `postgres` image plus Patroni, with no prebuilt HA images. The image also needs pgBackRest and must run as non-root.

## Options considered

- **Official image + pinned PGDG packages:** short Dockerfile, signed packages.
- **Official image + pip hash lock:** fully pinned Python dependencies, with a lock file to maintain.
- **Alpine or source build:** smallest image, but slower and harder to defend.

## Decision

Build `FROM` the digest-pinned `postgres:17.12-trixie`, and install the exact PGDG `patroni` and `pgbackrest` versions from `versions.env`. Run as UID 999, bypassing the root entrypoint. Build with `docker build` and load with `k3d image import`.

## Consequences

- The Dockerfile stays short enough to explain line by line.
- Transitive Debian packages are not individually pinned, which is a documented reproducibility limit.
- PGDATA must be a subdirectory of the volume so Patroni can create it with mode 0700. Spike S3 proves this.
- The estimated compressed size of 200–230 MiB is measured at build time.

## R-IDs covered

R1.1, R6.4, R7.2, R7.3
