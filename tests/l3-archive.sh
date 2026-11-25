#!/usr/bin/env bash
# L3: Garage, pgBackRest configuration, WAL archiving, stanza and an on-demand backup with verify.
. "$(dirname "$0")/l3-lib.sh"
client_up

section "Garage (ADR-014)"
run "kubectl -n $NS get deploy,pvc,svc -l app.kubernetes.io/name=garage -o wide; kubectl -n $NS get pvc garage-data; kubectl -n $NS get pod -l app.kubernetes.io/name=garage -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image" || true
check "Garage is Ready on the infra node with its PVC bound" bash -c "kubectl -n $NS rollout status deploy/garage --timeout=60s && test \"\$(kubectl -n $NS get pvc garage-data -o jsonpath='{.status.phase}')\" = Bound"
check "Garage runs single node with metadata and data fsync on" bash -c "kubectl -n $NS get cm garage-config -o jsonpath='{.data.garage\.toml}' | grep -qx 'metadata_fsync = true' && kubectl -n $NS get cm garage-config -o jsonpath='{.data.garage\.toml}' | grep -qx 'data_fsync = true' && kubectl -n $NS get cm garage-config -o jsonpath='{.data.garage\.toml}' | grep -qx 'replication_factor = 1'"
BOOT=$("$ROOT_DIR/scripts/garage.sh" 2>&1 | tail -6) || true
run "printf '%s\n' \"\$BOOT\"" || true
check "Bootstrap Job is idempotent: a rerun keeps layout, key and bucket" bash -c "grep -q 'layout: version 1 exists, kept' <<<\"\$0\" && grep -q 'key: exists, kept' <<<\"\$0\" && grep -q 'bucket: exists, kept' <<<\"\$0\" && grep -q BOOTSTRAP_OK <<<\"\$0\"" "$BOOT"

section "pgBackRest configuration (ADR-009)"
run "cat deploy/pg/pgbackrest/repo.conf | grep -v '^#'" || true
run "grep -rnE '^[[:space:]]*repo1-|--repo1-' deploy scripts tests --exclude=repo.conf --exclude=l3-archive.sh --exclude-dir=spikes || echo 'no repo1-* setting outside repo.conf'" || true
check "No repo1-* setting outside repo.conf (config lines or CLI options)" bash -c "! grep -rqE '^[[:space:]]*repo1-|--repo1-' deploy scripts tests --exclude=repo.conf --exclude=l3-archive.sh --exclude-dir=spikes"
check "No credential value in any live ConfigMap, CronJob or rendered manifest" bash -c "{ kubectl -n $NS get cm,cronjob -o yaml; kubectl kustomize deploy/pg; cat deploy/garage/garage.yaml; } | python3 -I -c '
import glob, sys; d = sys.stdin.read()
sys.exit(any((v := open(p).read().strip()) and v in d for p in glob.glob(\"secrets/credentials/*\")))'"
check "Repository encryption is aes-256-cbc, with the passphrase only in a Secret" bash -c "grep -qx 'repo1-cipher-type=aes-256-cbc' deploy/pg/pgbackrest/repo.conf && kubectl -n $NS get secret pgbackrest-repo -o jsonpath='{.data.PGBACKREST_REPO1_CIPHER_PASS}' | grep -q ."
check "Jobs list pg1..pg3 by headless-service DNS over TLS" bash -c "test \$(grep -cE '^pg[123]-host=pg-[012]\.pg-headless\.pg-ha\.svc\.cluster\.local$' deploy/pg/pgbackrest/job.conf) = 3 && test \$(grep -c '^pg[123]-host-type=tls$' deploy/pg/pgbackrest/job.conf) = 3"
check "Archiving is asynchronous with a 2 GiB queue cap (ADR-005)" bash -c "grep -qx 'archive-async=y' deploy/pg/pgbackrest/db.conf && grep -qx 'archive-push-queue-max=2GiB' deploy/pg/pgbackrest/db.conf"

section "WAL archiving (Patroni conf.d/20-archive.yml)"
run "q $RW monitor \"select name, setting from pg_settings where name in ('archive_mode','archive_command','archive_timeout','restore_command','ssl') order by 1\"" || true
S=$(q "$RW" monitor "select string_agg(name || '=' || setting, ' ') from pg_settings where name in ('archive_mode','archive_command','restore_command','ssl')")
check "archive_mode on with archive-push, restore_command via archive-get, and 10-base.yml settings kept (ssl on)" bash -c "grep -q 'archive_mode=on' <<<\"\$0\" && grep -q 'archive-push' <<<\"\$0\" && grep -q 'archive-get' <<<\"\$0\" && grep -q 'ssl=on' <<<\"\$0\"" "$S"
A0=$(archiver); T_A=$(date +%s)
# archive_timeout switches segments only after WAL activity, so write something first.
q "$RW" app "create table if not exists l3_ping (t timestamptz); insert into l3_ping values (now())" >/dev/null
run "q $RW monitor 'select archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'" || true
note "Failures counted before the stanza existed are expected: Postgres starts archiving before the stanza Job runs and retries each segment until it succeeds. The checks below therefore require no failure during this test, and that the last failure (if any) is older than the last successful archive. The pre-stanza failures are recorded in the history file."
AT=$(archived_after "$T_A" 120) || AT=""
A1=$(archiver)
run "q $RW monitor 'select archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'" || true
check "A new WAL segment was archived within 120 s (archive_timeout 60 s)" test -n "$AT"
check "pg_stat_archiver: no new failures during the test" test "$(awk '{print $2}' <<<"$A0")" = "$(awk '{print $2}' <<<"$A1")"
check "pg_stat_archiver: last failure (if any) is older than the last successful archive" awk -v f="$(awk '{print $5}' <<<"$A1")" -v s="$(awk '{print $4}' <<<"$A1")" 'BEGIN{exit !(f < s)}'

section "Stanza (idempotent) and pgbackrest check, from Jobs over TLS"
TAIL=8 run "JOB_WAIT=300 scripts/pgbr-job.sh pg-stanza-create 'pgbackrest --stanza=main --log-level-console=info stanza-create && pgbackrest --stanza=main --log-level-console=info check && echo STANZA_OK' | grep -vE 'command begin'" && st=1 || st=0
check "stanza-create reruns cleanly on the existing stanza, and pgbackrest check passes" test $st = 1

section "On-demand backup: make backup (full, expire, verify)"
B=pg-backup-manual-$(date -u +%Y%m%d%H%M%S)
TAIL=30 run "scripts/pgbr-job.sh $B | grep -vE 'command begin'" && bk=1 || bk=0
check "make backup completed: full backup, expire, verify status ok" bash -c "test $bk = 1 && kubectl -n $NS logs job/$B | grep -q VERIFY_OK"
check "The backup job script fails unless verify reports status ok (not only exit 0)" grep -q "grep -q 'status: ok'" deploy/pg/scripts/backup-job.sh
kubectl -n "$NS" delete job "$B" pg-stanza-create --ignore-not-found --wait=false >/dev/null 2>&1 || true
l3_finish archive "Garage, pgBackRest, archiving and on-demand backup" "Garage from our manifests with an idempotent Admin API bootstrap, pgBackRest with every repo1-* setting in repo.conf and an encrypted repository, async WAL archiving added as Patroni conf.d/20-archive.yml, stanza and check as a Job over the TLS server, and \`make backup\` (full, expire, verify)." test-archive
