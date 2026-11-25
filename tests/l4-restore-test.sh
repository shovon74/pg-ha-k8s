#!/usr/bin/env bash
# L4 R4.5, R5.4 (ADR-010): the restore test Job, on demand. Takes a backup first, so the newest backup
# carries the data fingerprint as annotations. Then runs a Job from the pg-restore-test CronJob template,
# exactly as the schedule does: restore into emptyDir, Postgres with no TCP listener, fingerprint compared,
# pg_amcheck. A second Job with RESTORE_TEST_INJECT_MISMATCH=1 must fail, to show that bad data fails the
# Job and not only a log line.
. "$(dirname "$0")/l4-lib.sh"
section "Backup with fingerprint annotations"
TAIL=8 run "scripts/pgbr-job.sh pg-backup-l4 | grep -E 'fingerprint recorded|new backup label|VERIFY_OK|BACKUP_JOB_OK|FAILED'" && b=1 || b=0
check "Backup with verify ok, fingerprint recorded as annotations" bash -c "test $b = 1 && kubectl -n $NS logs job/pg-backup-l4 | grep -q 'fingerprint recorded as annotations: seeded=yes'"
kubectl -n "$NS" delete job pg-backup-l4 --wait=false >/dev/null 2>&1 || true

section "Restore test Job (pg-restore-test template)"
J=pg-restore-test-manual-$(date -u +%H%M%S)
T_J=$(now); TAIL=30 run "CRONJOB=pg-restore-test scripts/pgbr-job.sh $J" && ok=1 || ok=0; T_E=$(now)
kubectl -n "$NS" logs "job/$J" > "$BODY.job" 2>/dev/null || true
check "The restore test Job succeeded (RESTORE_TEST_OK)" bash -c "test $ok = 1 && grep -q RESTORE_TEST_OK '$BODY.job'"
check "Every fingerprint value matched the one recorded at backup time" bash -c "grep -qE ' PASS$' '$BODY.job' && ! grep -qE ' FAIL$' '$BODY.job'"
check "pg_amcheck ran on the scratch copy and reported no corruption" bash -c "grep -q 'pg_amcheck --install-missing' '$BODY.job' && ! grep -q 'pg_amcheck found corruption' '$BODY.job'"
check "The Job template mounts no PVC and no Service selects it; Postgres has listen_addresses = ''" bash -c "kubectl -n $NS get cronjob pg-restore-test -o json | jq -e '[.spec.jobTemplate.spec.template.spec.volumes[] | select(.persistentVolumeClaim)] | length == 0' >/dev/null && ! kubectl -n $NS get svc -o json | jq -e '.items[] | select(.spec.selector[\"app.kubernetes.io/name\"] == \"pg-restore-test\")' >/dev/null && grep -q \"listen_addresses = ''\" deploy/pg/scripts/restore-test.sh"
note "Job wall time $(secs "$T_J" "$T_E") s, including scheduling."
kubectl -n "$NS" delete job "$J" --wait=false >/dev/null 2>&1 || true

section "Negative run: a wrong expected value must fail the Job"
J2=pg-restore-test-negative
TAIL=12 run "CRONJOB=pg-restore-test scripts/pgbr-job.sh $J2 '' RESTORE_TEST_INJECT_MISMATCH=1" && neg=0 || neg=1
check "The Job failed (non-zero exit) with RESTORE_TEST_FAILED: fingerprint mismatch" bash -c "test $neg = 1 && kubectl -n $NS logs job/$J2 | grep -q 'RESTORE_TEST_FAILED: fingerprint mismatch' && [ \"\$(kubectl -n $NS get job $J2 -o jsonpath='{.status.failed}')\" = 1 ]"
kubectl -n "$NS" delete job "$J2" --wait=false >/dev/null 2>&1 || true
rm -f "$BODY.job"
l4_finish restore-test "Restore test Job, on demand (R4.5, R5.4)" "\`make test-restore\`: a backup with the fingerprint recorded as annotations, then a Job from the \`pg-restore-test\` CronJob template restores it into emptyDir, starts Postgres with no TCP listener, compares the fingerprint, runs \`pg_amcheck --install-missing\` on the scratch copy and exits non-zero on any failure. A negative run with one wrong expected value must fail." test-restore
