# L3: Garage restart while writing

**Result: PASS**

- **What:** `kubectl rollout restart deploy/garage` while the probe writes every 500 ms and about 5 MB of WAL is generated every 2 s. Measures when archiving succeeds again and when the .ready backlog drains, with no manual action. The bound is 120 s after Garage is Ready.
- **Run:** 2026-11-26T15:52:13Z (UTC), 48 s
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

Probe run `garage-restart-1795708335` writing through pg-rw every 500 ms. WAL generator: about 5 MB every 2 s into `l3_walgen`. Leader `pg-2`. Before the restart: archived=31 failed=0 ready backlog=0.

## Garage restart

Garage pod `garage-78b588844b-769mb` replaced by `garage-c8cd6c48d-lcdbs`. Restart issued at 15:52:40.724 UTC, new pod Ready at +4.03 s. Last successful archive before the restart at -4.53 s. First archive after Garage Ready at +6.18 s (2.14 s after Ready). Backlog drained at +7.05 s. Archive failures counted: 0. Largest .ready backlog: 1 segments. Probe: largest gap between acknowledged writes in the window 0.90 s, 0 failed attempts.

```console
$ awk -v t=1795708360.724289080 '$1 >= t - 6' /tmp/tmp.zTrobxxPWL/arch.txt | awk '{printf "%s archived=%s failed=%s last=%s ready=%s\n", strftime("%H:%M:%S", $1, 1), $2, $3, $4, $7}' | awk 'NR % 3 == 1' | head -50
15:52:35 archived=30 failed=0 last=000000170000000000000059 ready=0
15:52:39 archived=31 failed=0 last=00000017000000000000005A ready=0
15:52:43 archived=31 failed=0 last=00000017000000000000005A ready=0
15:52:47 archived=32 failed=0 last=00000017000000000000005B ready=0
15:52:51 archived=32 failed=0 last=00000017000000000000005B ready=1
```

| Garage Ready after restart (s) | First archive after Ready (s) | Backlog drained after restart (s) | Archive failures | Max .ready backlog | Max write gap (s) | Probe errors |
|---:|---:|---:|---:|---:|---:|---:|
| 4.03 | 2.14 | 7.05 | 0 | 1 | 0.90 | 0 |

```console
$ JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-garage 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'
2026-11-26 15:52:56.578 P00   INFO: check repo1 (standby)
2026-11-26 15:52:56.588 P00   INFO: switch wal not performed because this is a standby
2026-11-26 15:52:56.588 P00   INFO: check repo1 configuration (primary)
2026-11-26 15:52:56.638 P00   INFO: check repo1 archive for WAL (primary)
2026-11-26 15:52:57.080 P00   INFO: WAL segment 00000017000000000000005D successfully archived to '/pg-ha/archive/main/17-1/0000001700000000/00000017000000000000005D-fd001f82d931c3d7b9da684a3812dcfd665ca08c.zst' on repo1
2026-11-26 15:52:57.082 P00   INFO: check command end: completed successfully (1721ms)
CHECK_OK
```
