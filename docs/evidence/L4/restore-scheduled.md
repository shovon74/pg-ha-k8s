# L4: Restore test Job, scheduled (R4.5)

**Result: PASS**

- **What:** The `pg-restore-test` CronJob deployed with a short schedule (`*/5 * * * *`), a Job created by the CronJob itself (not `make`) checked for RESTORE_TEST_OK, then the default daily 21:00 UTC schedule restored.
- **Run:** 2026-11-25T15:44:22Z (UTC), 65 s
- **Reproduce:** `make test-restore-schedule`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Deployed with RESTORE_TEST_SCHEDULE='*/5 * * * *' | PASS |
| The CronJob created a Job on its own schedule | PASS |
| The scheduled restore test succeeded (RESTORE_TEST_OK) | PASS |
| Default schedule restored (0 21 * * *) | PASS |

## Short schedule

```console
$ kubectl -n pg-ha get job pg-restore-test-29927025 -o json | jq -r '"job \(.metadata.name) created \(.metadata.creationTimestamp) by \(.metadata.ownerReferences[0].kind)/\(.metadata.ownerReferences[0].name), annotations \(.metadata.annotations // {} | keys)"'
job pg-restore-test-29927025 created 2026-11-25T15:45:00Z by CronJob/pg-restore-test, annotations ["batch.kubernetes.io/cronjob-scheduled-timestamp"]
```

```console
$ kubectl -n pg-ha logs job/pg-restore-test-29927025 | grep -vE '^ +[0-9]+/[0-9]+ '
2026-11-25T15:45:01Z restoring backup 20261125-154309F to its consistent end point (--type=immediate)
2026-11-25T15:45:07Z recovered and promoted in 7 s; consistent recovery state reached at 0/6B000088
2026-11-25T15:45:09Z expected (recorded at backup time) vs restored:
rows.pgbench_accounts      1000000                1000000                PASS
rows.pgbench_branches      10                     10                     PASS
rows.pgbench_tellers       100                    100                    PASS
seeded                     yes                    yes                    PASS
sum.pgbench_accounts       1637876347759          1637876347759          PASS
sum.pgbench_branches       3530232442             3530232442             PASS
sum.pgbench_tellers        9319411032             9319411032             PASS
2026-11-25T15:45:09Z pg_amcheck --install-missing (scratch instance only)
831/831 relations (100%), 21684/21684 pages (100%)
2026-11-25T15:45:10Z RESTORE_TEST_OK backup=20261125-154309F total=10s
```

## Default schedule restored
