# L3: Retention enforcement

**Result: PASS**

- **What:** Three full backups from the CronJob template with a temporary `PGBACKREST_REPO1_RETENTION_FULL=2` on those Jobs only, proving the oldest fulls and their WAL are expired, then a normal run with repo.conf's `repo1-retention-full=7` keeping every full.
- **Run:** 2026-11-26T15:40:48Z (UTC), 464 s
- **Reproduce:** `make test-retention`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Backup 1 (20261126-154057F) completed with verify status ok | PASS |
| Backup 2 (20261126-154350F) completed with verify status ok | PASS |
| Backup 3 (20261126-154644F) completed with verify status ok | PASS |
| Exactly the 2 newest fulls remain | PASS |
| The oldest backup from before the test (20261126-153747F) and backup 1 (20261126-154057F) were expired | PASS |
| WAL older than the oldest kept backup was expired with it (archive min = its start WAL) | PASS |
| Archive min moved past the expired backup's start WAL (00000016000000000000004C) | PASS |
| repo.conf still says repo1-retention-full=7 and the CronJob sets no retention override | PASS |
| A normal run (retention 7) keeps all 3 fulls | PASS |

## Before

```console
$ jq -r '.[0].backup[] | .label + "  wal " + .archive.start + ".." + .archive.stop' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"00000016000000000000004A","min":"000000010000000000000001"}],"backup":[{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"000000160000000000000046","stop":"000000160000000000000046"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932496,"size":10932496},"size":188826677},"label":"20261126-153747F","lsn":{"start":"0/46000028","stop":"0/46000158"},"prior":null,"reference":null,"timestamp":{"start":1795707467,"stop":1795707481},"type":"full"},{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"000000160000000000000049","stop":"000000160000000000000049"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932480,"size":10932480},"size":188826677},"label":"20261126-154002F","lsn":{"start":"0/49000028","stop":"0/49000158"},"prior":null,"reference":null,"timestamp":{"start":1795707602,"stop":1795707617},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7712491660157001760,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'; echo "archive min: 000000010000000000000001"
20261126-153747F  wal 000000160000000000000046..000000160000000000000046
20261126-154002F  wal 000000160000000000000049..000000160000000000000049
archive min: 000000010000000000000001
```

## Three backups with a temporary retention of 2 fulls

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.I205Znkd0a.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261126-154057F
2026-11-26T15:41:41Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-26T15:41:43Z VERIFY_OK
```

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.I205Znkd0a.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261126-154350F
2026-11-26T15:44:33Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-26T15:44:36Z VERIFY_OK
```

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.I205Znkd0a.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261126-154644F
2026-11-26T15:47:27Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-26T15:47:33Z VERIFY_OK
```

## After

```console
$ jq -r '.[0].backup[] | .label + "  wal " + .archive.start + ".." + .archive.stop' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"000000160000000000000050","min":"00000016000000000000004E"}],"backup":[{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"00000016000000000000004E","stop":"00000016000000000000004E"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932480,"size":10932480},"size":188826677},"label":"20261126-154350F","lsn":{"start":"0/4E000028","stop":"0/4E000158"},"prior":null,"reference":null,"timestamp":{"start":1795707830,"stop":1795707847},"type":"full"},{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"000000160000000000000050","stop":"000000160000000000000050"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932480,"size":10932480},"size":188826677},"label":"20261126-154644F","lsn":{"start":"0/50000028","stop":"0/50000158"},"prior":null,"reference":null,"timestamp":{"start":1795708004,"stop":1795708020},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7712491660157001760,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'; echo "archive min: 00000016000000000000004E"
20261126-154350F  wal 00000016000000000000004E..00000016000000000000004E
20261126-154644F  wal 000000160000000000000050..000000160000000000000050
archive min: 00000016000000000000004E
```

Labels before: `20261126-153747F 20261126-154002F `. New: `20261126-154057F 20261126-154350F 20261126-154644F`. Left after expire: `20261126-154350F 20261126-154644F `. Archive min before `000000010000000000000001`, after `00000016000000000000004E`. Start WAL of the expired backup 20261126-154057F: `00000016000000000000004C`, of the oldest kept 20261126-154350F: `00000016000000000000004E`.

## Real setting in force again

```console
$ grep -h retention deploy/pg/pgbackrest/*.conf; kubectl -n pg-ha get cronjob pg-backup -o json | jq -c '[.spec.jobTemplate.spec.template.spec.containers[0].env[] | .name]'
repo1-retention-full=7
["HOME","APP_RO_PW"]
```

```console
$ jq -r '.[0].backup[] | .label' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"000000160000000000000052","min":"00000016000000000000004E"}],"backup":[{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"00000016000000000000004E","stop":"00000016000000000000004E"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932480,"size":10932480},"size":188826677},"label":"20261126-154350F","lsn":{"start":"0/4E000028","stop":"0/4E000158"},"prior":null,"reference":null,"timestamp":{"start":1795707830,"stop":1795707847},"type":"full"},{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"000000160000000000000050","stop":"000000160000000000000050"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826677,"repository":{"delta":10932480,"size":10932480},"size":188826677},"label":"20261126-154644F","lsn":{"start":"0/50000028","stop":"0/50000158"},"prior":null,"reference":null,"timestamp":{"start":1795708004,"stop":1795708020},"type":"full"},{"annotation":{"rows.pgbench_accounts":"1000000","rows.pgbench_branches":"10","rows.pgbench_tellers":"100","seeded":"yes","sum.pgbench_accounts":"1637876347759","sum.pgbench_branches":"3530232442","sum.pgbench_tellers":"9319411032"},"archive":{"start":"000000160000000000000052","stop":"000000160000000000000052"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188826676,"repository":{"delta":10932480,"size":10932480},"size":188826676},"label":"20261126-154755F","lsn":{"start":"0/52000028","stop":"0/52000158"},"prior":null,"reference":null,"timestamp":{"start":1795708075,"stop":1795708094},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7712491660157001760,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'
20261126-154350F
20261126-154644F
20261126-154755F
```
