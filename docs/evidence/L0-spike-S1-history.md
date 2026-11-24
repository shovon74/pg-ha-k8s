# L0 spike S1: history and investigations

This file is maintained by hand. `make spike-s1` writes only the generated results in [`L0-spike-S1.md`](L0-spike-S1.md) and never touches this file.

## Run history

The clean L0 run was made at 11:11 UTC after `make down && make up`. Earlier attempts on 2026-11-23 (UTC), kept here so the result is not overstated:

1. **Failed at 11:06.** The bootstrap Job outlasted the harness's 90 s wait, because one connection to the Garage admin port hung for 136 s. pgBackRest therefore ran before its key existed and got HTTP 403. The trigger is a startup race, and the curl connect timeout is the fix. See "Resolution" below.
2. **The same run exposed two vacuous checks.** `pgbackrest verify` **exited 0 while reporting `status: error`**, and the wrong-passphrase check passed against an empty repository. Verify now requires `status: ok`. The cipher check now requires ciphertext on disk, a successful read with the right passphrase and a refused read with a wrong one.
3. **Failed at 11:09.** Stanza, backup, archive, verify, encryption and restore passed, but `pg_amcheck` stopped because the `amcheck` extension was not installed. It now runs with `--install-missing`.

## Resolution: the 136 s Garage connection hang

**Verdict:** The startup-race explanation is correct about the trigger, and the earlier "cause unknown" statement is superseded. Two details of the original explanation were wrong or incomplete:

- The hang is not simply "admin port not ready". A connection attempted during Garage startup can stall for about 135 s and never recover, even after Garage is serving.
- The readiness probe does not gate the bootstrap Job. The Job and Garage are applied together, and the Job started 4 to 5 s before the Garage container in every trial. **The connect timeout with retry is the fix.**

**Not established:** why these connections stall instead of being refused. No packet capture was taken. The 132 to 136 s duration is consistent with kernel SYN retry exhaustion (`net.ipv4.tcp_syn_retries = 6` on the host), but that mechanism is inferred.

### Evidence (2026-11-23, UTC)

Original failure at 11:06, from the bootstrap Job log:

```console
curl: (7) Failed to connect to garage.spike-s1.svc.cluster.local:3903 after 15 ms: Could not connect to server
curl: (28) Failed to connect to garage.spike-s1.svc.cluster.local:3903 after 136050 ms: Could not connect to server
```

**Reproduction, 14:20 to 14:28.** Three fresh namespaces used the same Garage image, config, PVC, readiness probe and node placement. A probe Job started one curl every 0.5 s with no connect timeout, 60 per trial.

| Trial | Probe Job start | Garage container start | Pod Ready | Refused | Hung (duration) | Succeeded (max time) | Last hung attempt started |
|---|---|---|---|---|---|---|---|
| 1 | 14:20:06 | 14:20:10 | 14:20:11 | 1 | 10 (132.6 to 136.2 s) | 49 (9 ms) | 14:20:12 |
| 2 | 14:22:47 | 14:22:51 | 14:22:52 | 3 | 8 (132.5 to 136.1 s) | 49 (6 ms) | 14:22:52 |
| 3 | 14:25:26 | 14:25:31 | 14:25:32 | 1 | 10 (132.4 to 136.0 s) | 49 (7 ms) | 14:25:32 |

The hang reproduced in 3 of 3 trials, across 28 of 180 connections. Attempt start times have 1 s resolution. Attempts started in the same second as Ready, and in trial 1 one second after it, still hung, so waiting for Ready alone would not fully close the window.

**Fix check.** Five more fresh startups ran curl with the bootstrap Job's options (`--connect-timeout 3 --max-time 15 --retry 20 --retry-delay 1 --retry-all-errors`). All five reached Garage's admin port after 1 or 2 connect timeouts and 1 or 2 refusals. The HTTP 503 they received is expected from `/health` before a layout exists. Their 23 to 26 s run time includes retries of that 503, so it is not a time-to-connect measurement.

The retry budget covers the observed window: 21 connect attempts at 3 s plus 20 delays of 1 s is at most 83 s, inside the harness's 120 s wait. The clean S1 run at 11:11 UTC showed the same recovery in its bootstrap log: one refusal, four 3 s timeouts, then success.

### Rerun the trials

`scripts/spikes/s1-garage-startup-race.sh` is the committed form of this probe. It needs a running cluster (`make up`), creates one throwaway namespace per trial, always deletes it, uses random one-time tokens and masks its saved output in `.run/s1-garage-startup-race/`.

```console
$ MODE=unbounded TRIALS=3 scripts/spikes/s1-garage-startup-race.sh   # about 3 min per trial
$ MODE=bounded TRIALS=5 scripts/spikes/s1-garage-startup-race.sh     # under 1 min per trial
```

The committed script probes an unauthenticated admin route, so a reachable Garage returns HTTP 403 at once and bounded runs measure real time to connect. Its validation run on 2026-11-23 (UTC) gave:

```console
$ MODE=bounded TRIALS=3 scripts/spikes/s1-garage-startup-race.sh
trial 1: BOUNDED exit=0 http=403 retries=3 elapsed_s=9
trial 2: BOUNDED exit=0 http=403 retries=3 elapsed_s=9
trial 3: BOUNDED exit=0 http=403 retries=3 elapsed_s=10
$ MODE=unbounded TRIALS=1 scripts/spikes/s1-garage-startup-race.sh
trial 1: ok=49 refused=3 hung=8 hung_seconds=132.8-136.4 other=0
```

### Diagnostic `docker exec` disclosure

At 2026-11-23T14:19:20Z (UTC), during this investigation, one read-only `docker exec` ran on the k3d server node `k3d-pg-ha-server-0`:

```console
$ docker exec k3d-pg-ha-server-0 sh -c 'iptables-save 2>/dev/null | grep -c KUBE; nft list ruleset 2>/dev/null | grep -c -i kube; cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_syn_sent'
126
122
120
```

- **What it inspected:** the number of Kubernetes firewall rules visible through iptables and nftables, and the connection-tracking timeout for unanswered SYNs.
- **What it changed:** nothing. All three commands only read state.
- **Dependence:** none. No result or conclusion in this file uses its output, and the committed probe does not use `exec`.
- **Policy:** the lead accepted this diagnostic-only use. Delivery paths stay exec-free under D4.

### L3 watch item

The S1 bootstrap hang is closed. The untested question of a Garage restart affecting running clients is tracked in the L3 notes of [`docs/01-design-options.md`](../01-design-options.md#phase-notes-from-l0).

## S3 access key rotation and S1 rerun

The Garage S3 access key **ID** was printed in session logs while debugging (see [`redaction-log.md`](../process/redaction-log.md)). The secret key was not exposed. On 2026-11-23 at about 15:07 UTC, the ID and secret key were both regenerated with `scripts/secrets.sh`, and no other credential changed. The old pair was only ever valid on Garage instances in spike namespaces that no longer exist, and it has been destroyed.

`make spike-s1` then passed all 12 checks on the new key (run 2026-11-23T15:07:51Z, 52 s, backup `20261123-150811F`). That run is the current [`L0-spike-S1.md`](L0-spike-S1.md). Its bootstrap log shows the same startup race, bounded: one refusal, two 3 s timeouts, then success. This history file was byte-identical before and after the rerun.

## Superseded result: clean L0 run at 11:11 UTC

This is the generated result from before the key rotation, preserved unchanged apart from heading levels.

<details>
<summary>Show the 11:11 UTC result</summary>

**Result: PASS**

- **Question:** Does pgBackRest complete stanza creation, backup, archive and restore against Garage?
- **Pass criteria:** Against Garage over plain HTTP with path-style URLs and aes-256-cbc repository encryption: stanza-create, check, full backup, WAL archiving, verify and restore all succeed. Restored rows, including rows only in archived WAL, match the source checksum, and a wrong passphrase cannot read the repository.
- **Run:** 2026-11-23T11:11:00Z (UTC), 67 s
- **Reproduce:** `make spike-s1`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

#### Checks

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

#### Setup: Garage (single node, fsync on) on the tainted server

```console
$ kubectl create ns spike-s1
namespace/spike-s1 created
```

```console
$ kubectl -n spike-s1 logs job/garage-bootstrap
curl: (7) Failed to connect to garage.spike-s1.svc.cluster.local:3903 after 15 ms: Could not connect to server
curl: (28) Connection timed out after 3001 milliseconds
curl: (28) Connection timed out after 3001 milliseconds
curl: (28) Connection timed out after 3000 milliseconds
curl: (28) Connection timed out after 3001 milliseconds
node id length: 64
LAYOUT_OK
KEY_OK
BUCKET_OK
```

```console
$ kubectl -n spike-s1 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase,IMAGE:.spec.containers[0].image
POD                       NODE                 PHASE       IMAGE
garage-7ff99b54c4-bhslv   k3d-pg-ha-server-0   Running     dxflrs/garage:v2.5.0@sha256:677e5b758e4425a325b811c425c026bf35a4bf42f7ddbaa773de3f4fd779a5a5
garage-bootstrap-wtvwd    k3d-pg-ha-server-0   Succeeded   curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93
```

#### pgBackRest end-to-end run in a UID 999 Job on a database node

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

        full backup: 20261123-111137F
            timestamp start/stop: 2026-11-23 11:11:37+00 / 2026-11-23 11:11:51+00
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 35.9MB, database backup size: 35.9MB
            repo1: backup set size: 8.1MB, backup size: 8.1MB

--- pgbackrest verify (the exit code alone is not trusted, the reported status must be ok)
status: ok
archiveId: 17-1, total WAL checked: 6, total valid WAL: 6
missing: 0, checksum invalid: 0, size invalid: 0, other: 0
backup: 20261123-111137F, status: valid, total files checked: 969, total valid files: 969
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

</details>
