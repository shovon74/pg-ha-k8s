# L3: Retention enforcement

**Result: PASS**

- **What:** Three full backups from the CronJob template with a temporary `PGBACKREST_REPO1_RETENTION_FULL=2` on those Jobs only, proving the oldest fulls and their WAL are expired, then a normal run with repo.conf's `repo1-retention-full=7` keeping every full.
- **Run:** 2026-11-25T07:26:48Z (UTC), 493 s
- **Reproduce:** `make test-retention`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`, Garage `dxflrs/garage:v2.5.0`
- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)

## Checks

| Check | Result |
|---|---|
| Backup 1 (20261125-072655F) completed with verify status ok | PASS |
| Backup 2 (20261125-073042F) completed with verify status ok | PASS |
| Backup 3 (20261125-073333F) completed with verify status ok | PASS |
| Exactly the 2 newest fulls remain | PASS |
| The oldest backup from before the test (20261125-071559F) and backup 1 (20261125-072655F) were expired | PASS |
| WAL older than the oldest kept backup was expired with it (archive min = its start WAL) | PASS |
| Archive min moved past the expired backup's start WAL (0000001C000000000000001D) | PASS |
| repo.conf still says repo1-retention-full=7 and the CronJob sets no retention override | PASS |
| A normal run (retention 7) keeps all 3 fulls | PASS |

## Before

```console
$ jq -r '.[0].backup[] | .label + "  wal " + .archive.start + ".." + .archive.stop' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"0000001C000000000000001B","min":"000000010000000000000004"}],"backup":[{"archive":{"start":"0000001C000000000000000F","stop":"0000001C000000000000000F"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188965530,"repository":{"delta":10943536,"size":10943536},"size":188965530},"label":"20261125-071559F","lsn":{"start":"0/F000028","stop":"0/F000158"},"prior":null,"reference":null,"timestamp":{"start":1795590959,"stop":1795590974},"type":"full"},{"archive":{"start":"0000001C0000000000000012","stop":"0000001C0000000000000012"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188965532,"repository":{"delta":10943536,"size":10943536},"size":188965532},"label":"20261125-072002F","lsn":{"start":"0/12000028","stop":"0/12000158"},"prior":null,"reference":null,"timestamp":{"start":1795591202,"stop":1795591231},"type":"full"},{"archive":{"start":"0000001C0000000000000016","stop":"0000001C0000000000000016"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188965532,"repository":{"delta":10943536,"size":10943536},"size":188965532},"label":"20261125-072328F","lsn":{"start":"0/16000028","stop":"0/16000120"},"prior":null,"reference":null,"timestamp":{"start":1795591408,"stop":1795591424},"type":"full"},{"archive":{"start":"0000001C000000000000001B","stop":"0000001C000000000000001B"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-072600F","lsn":{"start":"0/1B000028","stop":"0/1B000158"},"prior":null,"reference":null,"timestamp":{"start":1795591560,"stop":1795591583},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7711783809198247968,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'; echo "archive min: 000000010000000000000004"
20261125-071559F  wal 0000001C000000000000000F..0000001C000000000000000F
20261125-072002F  wal 0000001C0000000000000012..0000001C0000000000000012
20261125-072328F  wal 0000001C0000000000000016..0000001C0000000000000016
20261125-072600F  wal 0000001C000000000000001B..0000001C000000000000001B
archive min: 000000010000000000000004
```

## Three backups with a temporary retention of 2 fulls

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.jwgTAoCVWS.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261125-072655F
2026-11-25T07:28:32Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-25T07:28:35Z VERIFY_OK
```

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.jwgTAoCVWS.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261125-073042F
2026-11-25T07:31:26Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-25T07:31:29Z VERIFY_OK
```

```console
$ grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' /tmp/tmp.jwgTAoCVWS.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'
INFO: new backup label = 20261125-073333F
2026-11-25T07:34:18Z expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)
INFO: repo1: 17-1 no archive to remove
2026-11-25T07:34:20Z VERIFY_OK
```

## After

```console
$ jq -r '.[0].backup[] | .label + "  wal " + .archive.start + ".." + .archive.stop' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"0000001C0000000000000021","min":"0000001C000000000000001F"}],"backup":[{"archive":{"start":"0000001C000000000000001F","stop":"0000001C000000000000001F"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-073042F","lsn":{"start":"0/1F000028","stop":"0/1F000158"},"prior":null,"reference":null,"timestamp":{"start":1795591842,"stop":1795591858},"type":"full"},{"archive":{"start":"0000001C0000000000000021","stop":"0000001C0000000000000021"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-073333F","lsn":{"start":"0/21000028","stop":"0/21000158"},"prior":null,"reference":null,"timestamp":{"start":1795592013,"stop":1795592030},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7711783809198247968,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'; echo "archive min: 0000001C000000000000001F"
20261125-073042F  wal 0000001C000000000000001F..0000001C000000000000001F
20261125-073333F  wal 0000001C0000000000000021..0000001C0000000000000021
archive min: 0000001C000000000000001F
```

Labels before: `20261125-071559F 20261125-072002F 20261125-072328F 20261125-072600F `. New: `20261125-072655F 20261125-073042F 20261125-073333F`. Left after expire: `20261125-073042F 20261125-073333F `. Archive min before `000000010000000000000004`, after `0000001C000000000000001F`. Start WAL of the expired backup 20261125-072655F: `0000001C000000000000001D`, of the oldest kept 20261125-073042F: `0000001C000000000000001F`.

## Real setting in force again

```console
$ grep -h retention deploy/pg/pgbackrest/*.conf; kubectl -n pg-ha get cronjob pg-backup -o json | jq -c '[.spec.jobTemplate.spec.template.spec.containers[0].env[] | .name]'
repo1-retention-full=7
["HOME"]
```

```console
$ jq -r '.[0].backup[] | .label' <<<'[{"archive":[{"database":{"id":1,"repo-key":1},"id":"17-1","max":"0000001C0000000000000023","min":"0000001C000000000000001F"}],"backup":[{"archive":{"start":"0000001C000000000000001F","stop":"0000001C000000000000001F"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-073042F","lsn":{"start":"0/1F000028","stop":"0/1F000158"},"prior":null,"reference":null,"timestamp":{"start":1795591842,"stop":1795591858},"type":"full"},{"archive":{"start":"0000001C0000000000000021","stop":"0000001C0000000000000021"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-073333F","lsn":{"start":"0/21000028","stop":"0/21000158"},"prior":null,"reference":null,"timestamp":{"start":1795592013,"stop":1795592030},"type":"full"},{"archive":{"start":"0000001C0000000000000023","stop":"0000001C0000000000000023"},"backrest":{"format":5,"version":"2.60.1"},"database":{"id":1,"repo-key":1},"error":false,"info":{"delta":188973724,"repository":{"delta":10944048,"size":10944048},"size":188973724},"label":"20261125-073430F","lsn":{"start":"0/23000028","stop":"0/23000158"},"prior":null,"reference":null,"timestamp":{"start":1795592070,"stop":1795592088},"type":"full"}],"cipher":"aes-256-cbc","db":[{"id":1,"repo-key":1,"system-id":7711783809198247968,"version":"17"}],"name":"main","repo":[{"cipher":"aes-256-cbc","key":1,"status":{"code":0,"message":"ok"}}],"status":{"code":0,"lock":{"backup":{"held":false},"restore":{"held":false}},"message":"ok"}}]'
20261125-073042F
20261125-073333F
20261125-073430F
```
