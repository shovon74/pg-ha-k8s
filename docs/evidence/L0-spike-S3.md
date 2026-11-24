# L0 spike S3: UID 999 and PGDATA on local-path

**Result: PASS**

- **Question:** Can UID 999 create a 0700 PGDATA on a local-path volume?
- **Pass criteria:** With no init container, no fsGroup and Pod Security restricted, a UID 999 pod creates PGDATA as 0700, runs initdb and starts Postgres, and the data survives a new pod on the same PVC.
- **Run:** 2026-11-23T11:13:14Z (UTC), 19 s
- **Reproduce:** `make spike-s3`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Checks

| Check | Result |
|---|---|
| First pod completed under Pod Security restricted | PASS |
| PGDATA created with mode 0700 by UID 999 | PASS |
| initdb left PGDATA at 0700 | PASS |
| Data checksums enabled | PASS |
| Second pod read the row from the same PVC | PASS |
| Second pod completed | PASS |

## Setup: namespace with Pod Security restricted, and a local-path PVC

```console
$ kubectl create ns spike-s3 && kubectl label ns spike-s3 pod-security.kubernetes.io/enforce=restricted
namespace/spike-s3 created
namespace/spike-s3 labeled
```

```console
$ kubectl get storageclass
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  3m18s
```

## First pod: create PGDATA, initdb with checksums, start Postgres, write a row

```console
$ kubectl -n spike-s3 logs job/s3-init
uid=999 gid=999
volume: 777 0:0
pgdata: 700 999:999
pgdata after initdb: 700 999:999
on
INIT_OK
```

## Second pod on the same PVC: data survives

```console
$ kubectl -n spike-s3 logs job/s3-reattach
survived
```

```console
$ kubectl -n spike-s3 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase; kubectl -n spike-s3 get pvc
POD                 NODE                PHASE
s3-init-nt2zm       k3d-pg-ha-agent-1   Succeeded
s3-reattach-v2bgk   k3d-pg-ha-agent-1   Succeeded
NAME      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
s3-data   Bound    pvc-6263872c-a09d-4b9c-abdc-d1e2f6bd4c40   1Gi        RWO            local-path     <unset>                 18s
```

Run history: the first run on 2026-11-23 failed because this test script used a bash-only construct under `sh` before initdb. PGDATA had already been created as 0700 by UID 999 in that run. The script was fixed and this is the complete re-run.
