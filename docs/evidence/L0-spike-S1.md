# L0 spike S1: pgBackRest against Garage

**Result: PASS**

- **Question:** Does pgBackRest complete stanza creation, backup, archive and restore against Garage?
- **Pass criteria:** Against Garage over plain HTTP with path-style URLs and aes-256-cbc repository encryption: stanza-create, check, full backup, WAL archiving, verify and restore all succeed. Restored rows, including rows only in archived WAL, match the source checksum, and a wrong passphrase cannot read the repository.
- **Run:** 2026-11-23T15:07:51Z (UTC), 52 s
- **Reproduce:** `make spike-s1`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **History:** [`L0-spike-S1-history.md`](L0-spike-S1-history.md) (maintained by hand, never written by this harness)

## Checks

| Check | Result |
|---|---|
| Garage is Ready on the tainted server | PASS |
| Garage bootstrapped via Admin API from a Job (no kubectl exec) | PASS |
| stanza-create succeeded | PASS |
| pgbackrest check succeeded | PASS |
| Full backup succeeded | PASS |
| WAL segment archived to Garage | PASS |
| pgbackrest verify reports status ok | PASS |
| Repository file is ciphertext, the right passphrase reads it and a wrong one cannot | PASS |
| Restore command succeeded | PASS |
| Restored rows and checksum match the source, including WAL-only rows | PASS |
| pg_amcheck passed on restored data | PASS |
| Spike Job completed | PASS |

## Setup: Garage (single node, fsync on) on the tainted server

```console
$ kubectl create ns spike-s1
namespace/spike-s1 created
```

```console
$ kubectl -n spike-s1 logs job/garage-bootstrap
curl: (7) Failed to connect to garage.spike-s1.svc.cluster.local:3903 after 23 ms: Could not connect to server
curl: (28) Connection timed out after 3001 milliseconds
curl: (28) Connection timed out after 3001 milliseconds
node id length: 64
LAYOUT_OK
KEY_OK
BUCKET_OK
```

```console
$ kubectl -n spike-s1 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase,IMAGE:.spec.containers[0].image
POD                       NODE                 PHASE       IMAGE
garage-7ff99b54c4-cdlrt   k3d-pg-ha-server-0   Running     dxflrs/garage:v2.5.0@sha256:677e5b758e4425a325b811c425c026bf35a4bf42f7ddbaa773de3f4fd779a5a5
garage-bootstrap-m4vzz    k3d-pg-ha-server-0   Succeeded   curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93
```

## pgBackRest end-to-end run in a UID 999 Job on a database node

```console
$ kubectl -n spike-s1 logs job/s1-run

--- pgBackRest config in use (credentials come from environment variables)
pgBackRest 2.60.1
repo1-type=s3
repo1-s3-endpoint=http://garage.spike-s1.svc.cluster.local:3900
repo1-s3-bucket=pgbackrest
repo1-s3-region=garage
repo1-s3-uri-style=path
repo1-path=/spike
repo1-cipher-type=aes-256-cbc
repo1-retention-full=7

--- initdb and start Postgres with WAL archiving through pgBackRest

--- stanza-create
STANZA_OK

--- check (proves WAL archiving reaches the repository)
CHECK_OK

--- write data, then take a full backup
BACKUP_OK

--- write more data after the backup, which only archived WAL can restore
source: 250000:23cc34023fcb3216751078f08245b262
switched WAL segment: 000000010000000000000006
last archived: 000000010000000000000006
ARCHIVE_OK
archived=7 failed=0

--- pgbackrest info
stanza: s1
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (17): 000000010000000000000001/000000010000000000000006

        full backup: 20261123-150811F
            timestamp start/stop: 2026-11-23 15:08:11+00 / 2026-11-23 15:08:26+00
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 35.9MB, database backup size: 35.9MB
            repo1: backup set size: 8.1MB, backup size: 8.1MB

--- pgbackrest verify (the exit code alone is not trusted, the reported status must be ok)
status: ok
archiveId: 17-1, total WAL checked: 6, total valid WAL: 6
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261123-150811F, status: valid, total files checked: 969, total valid files: 969
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
VERIFY_OK

--- encryption: raw object is ciphertext, right passphrase reads it, wrong one cannot
raw header: Salted__
decrypted header: [backrest
wrong passphrase: refused
CIPHER_OK

--- stop the source and destroy its data directory, then restore
RESTORE_OK
restored: 250000:23cc34023fcb3216751078f08245b262
DATA_MATCH_OK
in_recovery=false timeline=2
AMCHECK_OK
SPIKE_INNER_DONE
```
