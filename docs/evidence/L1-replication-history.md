# L1 replication: history and notes

This file is maintained by hand. `make test-replication` writes only the generated results in [`L1-replication.md`](L1-replication.md) and never touches this file.

## Test fix during L1 (2026-11-24, UTC)

The first from-scratch run failed 2 of its checks. The rejoin loop accepted the **old** pod, which Patroni still reported as `streaming` while it shut down, so the rejoin checks ran before the replacement pod existed. An earlier pass that reported an 8.6 s rejoin was probably the same false positive. The test now waits for a new pod UID and confirms streaming from `pg_stat_replication` on the primary. Two consecutive runs then passed every check, with rejoin times of 9.4 s and 10.3 s.

## Diagnostic `docker exec` disclosure

At about 2026-11-24T17:00Z (UTC), while measuring resource use after the L1 run, one command ran outside the committed scripts:

```console
$ for n in 0 1 2; do docker exec k3d-pg-ha-agent-$n true 2>/dev/null; done
```

- **What it inspected:** nothing. `true` is a no-op that was left in a measurement command by mistake.
- **What it changed:** nothing.
- **Dependence:** none. No result or conclusion in L1 uses it.
- **Policy:** diagnostic-only use outside committed scripts is disclosed here. Delivery paths stay exec-free under D4.
