# ADR-014: Object storage

**Status:** Accepted, subject to spike S1

## Context

Backups need in-cluster, S3-compatible storage. MinIO's upstream repository is archived and marked unmaintained, and its prebuilt artifacts are unavailable. The lead rejected building it from archived source as the main path, because shipping unmaintained software is a security weakness in a production design.

## Options considered

| Criterion | **Garage v2.5.0** | SeaweedFS 4.54 |
|---|---|---|
| Official pinned image | Yes, `dxflrs/garage`, digest pinned | Yes, `chrislusf/seaweedfs`, digest pinned |
| Maintained | Yes, stable release 2026-10-24 | Yes, about weekly releases |
| pgBackRest S3 calls | All required operations, path-style URLs and SigV4 are documented as implemented | All required operations have route handlers in the 4.54 source |
| Bootstrap without `kubectl exec` | Yes, Admin API v2 from a Job, including key import | Yes, startup flags or config |
| Compressed image size | **26 MiB** | **269 MiB** |
| Runtime | Single binary, no shell | Multi-service. `mini` mode is documented for small/dev use |
| Non-root | Runs under an assigned UID **[Assumption]** | Entrypoint starts as root, then drops privileges unless already non-root |
| Native TLS | **No**, its docs use a reverse proxy | **Yes** |
| Security record | Recent fixes in v2.5.0 | 57 published advisories, including several high severity on 2026-11-09 |
| Licence | AGPL-3.0 | Apache-2.0 |

Building **MinIO from source** remains the last fallback only.

## Decision

Use **Garage v2.5.0** as a single node with `replication_factor = 1`.

- Set `metadata_fsync = true` and `data_fsync = true`, because both default to off and this store has only one copy.
- Bootstrap through a Job using the Admin API, with pinned `curlimages/curl`.
- Connect pgBackRest over HTTP with path-style URLs. pgBackRest 2.60.1 supports `http://` S3 endpoints.
- Because Garage has no native TLS, enable **pgBackRest repository encryption** (`aes-256-cbc`). Backup content is encrypted before it leaves the client, and SigV4 means the secret key is not sent.
- Restrict access to the S3 port with NetworkPolicy.

## Consequences

- The smallest footprint and a narrow attack surface.
- Object metadata and object names are still visible on the network, and pgBackRest does not authenticate the server. A TLS reverse proxy is the production improvement.
- One storage node has no redundancy, so it is a documented limitation.
- **The brief lists "S3, GCS, Azure Blob or MinIO running in the cluster" and does not name Garage.** We treat Garage as S3-compatible object storage in the cluster, and the docs must state this substitution and why MinIO was not used.
- **Compatibility with pgBackRest has not been run yet.** Spike S1 must pass stanza creation, backup, archive and restore. If it fails, evaluate SeaweedFS next, and use MinIO from source only as a last resort.

## R-IDs covered

R4.2, R4.3, R4.4, R5.1, R8.10, R9.6
