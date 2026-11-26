# L5: alert rule unit tests (R10.2)

**Result: PASS**

- **What:** `promtool check rules` and `promtool test rules` from the pinned Prometheus image, plus checks that every rule has a severity, a summary and a reason for its threshold, and that every alert has a test where it fires and one where it stays silent. The tests run against a copy of the rules without annotations, so they check labels and timing. No cluster is needed.
- **Run:** 2026-11-26T14:11:46Z (UTC), 4 s
- **Reproduce:** `make test-alerts`
- **Versions:** promtool from `prom/prometheus:v3.16.0@sha256:e04987641b57704f408e31f6373ba4138ecf27cb4a165d24aabb6c38fddd0f06`

## Checks

| Check | Result |
|---|---|
| promtool check rules passes on deploy/monitoring/rules/pg-ha.rules.yml | PASS |
| Every rule has severity, summary and why; every alert has a firing and a silent test | PASS |
| Every Postgres, backup and restore rule selects namespace="pg-ha" (unscoped: none) | PASS |
| promtool test rules passes (tests/alerts/pg-ha.test.yml) | PASS |

## promtool check rules

```console
$ promtool '/tmp/tmp.o6Qve95cHZ' check rules orig.rules.yml
Checking orig.rules.yml
  SUCCESS: 19 rules found
```

## Rule metadata and test coverage

| Alert | Severity | Summary | Why | Fires test | Silent test |
|---|---|---|---|---|---|
| NoPrimary | critical | yes | yes | yes | yes |
| MultiplePrimaries | critical | yes | yes | yes | yes |
| MemberDown | warning | yes | yes | yes | yes |
| ReplicaNotStreaming | warning | yes | yes | yes | yes |
| ReplicationLagHigh | warning | yes | yes | yes | yes |
| ReplicationLagHigh | warning | yes | yes | yes | yes |
| SyncStandbyMissing | critical | yes | yes | yes | yes |
| SlotWALRetentionHigh | warning | yes | yes | yes | yes |
| SlotLost | warning | yes | yes | yes | yes |
| FailoverOccurred | info | yes | yes | yes | yes |
| ArchiveFailing | warning | yes | yes | yes | yes |
| ArchiveStale | critical | yes | yes | yes | yes |
| BackupFailed | warning | yes | yes | yes | yes |
| BackupStale | critical | yes | yes | yes | yes |
| RestoreTestFailed | warning | yes | yes | yes | yes |
| RestoreTestStale | warning | yes | yes | yes | yes |
| DiskLow | warning | yes | yes | yes | yes |
| CoreDNSNotReady | critical | yes | yes | yes | yes |
| MonitoringTargetDown | warning | yes | yes | yes | yes |

19 rules, 18 distinct alert names, 33 test groups.

## promtool test rules

```console
$ promtool '/tmp/tmp.o6Qve95cHZ' test rules pg-ha.test.yml
Processing test file: pg-ha.test.yml
  SUCCESS
```
