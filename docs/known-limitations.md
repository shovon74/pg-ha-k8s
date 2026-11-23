# Known limitations

This file lists what the system does not protect against or does not implement (R12.5, HC10). Entries are added as each phase confirms them.

## Backups

### Backup repository is not off-site

The in-cluster Garage repository shares the VM and disk with the database, so it is not off-site disaster protection. In production, the pgBackRest repository points at GCS/S3 with bucket versioning and a retention lock, off-site from the cluster, using keyless workload identity where available.

- **Why it is the default:** `make up` must work for any reviewer with no cloud account or credentials.
- **Planned option:** R4.7 adds `BACKUP_TARGET=gcs make up`. It is OPTIONAL and not built yet.
- **Decision:** ADR-014.
