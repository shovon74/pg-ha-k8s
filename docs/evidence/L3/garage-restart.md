# L3: Garage restart while writing

**Result: PASS**

- **What:** `kubectl rollout restart deploy/garage` while the probe writes every 500 ms and about 5 MB of WAL is generated every 2 s. Measures when archiving succeeds again and when the .ready backlog drains, with no manual action. The bound is 120 s after Garage is Ready.
- **Run:** 2026-11-25T07:49:59Z (UTC), 107 s
- **Reproduce:** `make test-garage-restart`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Archiving succeeded again on its own within 120 s of Garage being Ready | PASS |
| The .ready backlog drained (no permanent stall) | PASS |
| Writes through pg-rw were not blocked by the outage (max gap under 3 s) | PASS |
| pgbackrest check passes after the restart | PASS |

## Setup

Probe run `garage-restart-1795593000` writing through pg-rw every 500 ms. WAL generator: about 5 MB every 2 s into `l3_walgen`. Leader `pg-1`. Before the restart: archived=27 failed=0 ready backlog=0.

## Garage restart

Garage pod `garage-78b588844b-bkn9x` replaced by `garage-6687844f64-ld7gj`. Restart issued at 07:50:24.770 UTC, new pod Ready at +4.19 s. Last successful archive before the restart at -4.25 s. First archive after Garage Ready at +64.06 s (59.87 s after Ready). Backlog drained at +67.13 s. Archive failures counted: 1. Largest .ready backlog: 8 segments. Probe: largest gap between acknowledged writes in the window 1.14 s, 0 failed attempts.

```console
$ awk -v t=1795593024.770784355 '$1 >= t - 6' /tmp/tmp.9Hq0wlQo5c/arch.txt | awk '{printf "%s archived=%s failed=%s last=%s ready=%s\n", strftime("%H:%M:%S", $1, 1), $2, $3, $4, $7}' | awk 'NR % 3 == 1' | head -50
07:50:19 archived=26 failed=0 last=000000230000000000000039 ready=0
07:50:23 archived=27 failed=0 last=00000023000000000000003A ready=0
07:50:27 archived=27 failed=0 last=00000023000000000000003A ready=0
07:50:31 archived=27 failed=0 last=00000023000000000000003A ready=1
07:50:35 archived=27 failed=0 last=00000023000000000000003A ready=1
07:50:39 archived=27 failed=0 last=00000023000000000000003A ready=2
07:50:43 archived=27 failed=0 last=00000023000000000000003A ready=2
07:50:47 archived=27 failed=0 last=00000023000000000000003A ready=3
07:50:51 archived=27 failed=0 last=00000023000000000000003A ready=3
07:50:55 archived=27 failed=0 last=00000023000000000000003A ready=4
07:50:59 archived=27 failed=0 last=00000023000000000000003A ready=4
07:51:03 archived=27 failed=0 last=00000023000000000000003A ready=5
07:51:07 archived=27 failed=0 last=00000023000000000000003A ready=5
07:51:11 archived=27 failed=0 last=00000023000000000000003A ready=6
07:51:15 archived=27 failed=0 last=00000023000000000000003A ready=6
07:51:19 archived=27 failed=0 last=00000023000000000000003A ready=7
07:51:23 archived=27 failed=0 last=00000023000000000000003A ready=7
07:51:27 archived=27 failed=0 last=00000023000000000000003A ready=8
07:51:31 archived=35 failed=1 last=000000230000000000000042 ready=0
07:51:35 archived=36 failed=1 last=000000230000000000000043 ready=0
```

| Garage Ready after restart (s) | First archive after Ready (s) | Backlog drained after restart (s) | Archive failures | Max .ready backlog | Max write gap (s) | Probe errors |
|---:|---:|---:|---:|---:|---:|---:|
| 4.19 | 59.87 | 67.13 | 1 | 8 | 1.14 | 0 |

```console
$ JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-garage 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'
2026-11-25 07:51:40.311 P00   INFO: check repo1 (standby)
2026-11-25 07:51:40.323 P00   INFO: switch wal not performed because this is a standby
2026-11-25 07:51:40.324 P00   INFO: check repo1 configuration (primary)
2026-11-25 07:51:40.357 P00   INFO: check repo1 archive for WAL (primary)
2026-11-25 07:51:41.187 P00   INFO: WAL segment 000000230000000000000044 successfully archived to '/pg-ha/archive/main/17-1/0000002300000000/000000230000000000000044-78c1c98a71f12efc9ec408335a80e9084c081530.zst' on repo1
2026-11-25 07:51:41.189 P00   INFO: check command end: completed successfully (1078ms)
CHECK_OK
```
