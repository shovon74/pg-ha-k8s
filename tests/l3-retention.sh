#!/usr/bin/env bash
# L3 R4.3: retention enforcement. Three backups run from the CronJob template with a temporary retention of
# 2 fulls, given only to those test Jobs as PGBACKREST_REPO1_RETENTION_FULL (repo.conf is never edited).
# Proves the older backups are expired with their WAL, then that a normal run uses repo.conf's 7 again.
. "$(dirname "$0")/l3-lib.sh"
client_up
labels() { jq -r '.[0].backup[].label' <<<"$1"; }
amin() { jq -r '[.[0].archive[] | .min] | min' <<<"$1"; }
start_of() { jq -r --arg l "$2" '.[0].backup[] | select(.label == $l) | .archive.start' <<<"$1"; }

section "Before"
I0=$(pgbr_info); run "jq -r '.[0].backup[] | .label + \"  wal \" + .archive.start + \"..\" + .archive.stop' <<<'$I0'; echo \"archive min: $(amin "$I0")\"" || true
OLDEST_BEFORE=$(labels "$I0" | head -1)

section "Three backups with a temporary retention of 2 fulls"
NEW=(); STARTS=()
for n in 1 2 3; do
  J=pg-backup-ret-$n
  pgbr "$J" "" PGBACKREST_REPO1_RETENTION_FULL=2 > "$BODY.job" 2>&1 && ok=1 || ok=0
  L=$(sed -nE 's/.*new backup label = ([0-9F-]+).*/\1/p' "$BODY.job"); NEW+=("$L")
  STARTS+=("$(sed -nE 's/.*backup start archive = ([0-9A-F]{24}).*/\1/p' "$BODY.job")")
  run "grep -E 'new backup label|expire|remove|VERIFY_OK|VERIFY_FAILED' $BODY.job | grep -vE 'command (begin|end)' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +//'" || true
  check "Backup $n ($L) completed with verify status ok" bash -c "test $ok = 1 && grep -q VERIFY_OK $BODY.job"
  kubectl -n "$NS" delete job "$J" --wait=false >/dev/null 2>&1 || true
  # Some WAL between backups, so expiring a backup has archive to remove with it.
  [ $n = 3 ] || archived_after "$(date +%s)" 120 >/dev/null || true
done
rm -f "$BODY.job"

section "After"
I1=$(pgbr_info); run "jq -r '.[0].backup[] | .label + \"  wal \" + .archive.start + \"..\" + .archive.stop' <<<'$I1'; echo \"archive min: $(amin "$I1")\"" || true
LEFT=$(labels "$I1" | tr '\n' ' '); WANT="${NEW[1]} ${NEW[2]} "
note "Labels before: \`$(labels "$I0" | tr '\n' ' ')\`. New: \`${NEW[*]}\`. Left after expire: \`$LEFT\`. Archive min before \`$(amin "$I0")\`, after \`$(amin "$I1")\`. Start WAL of the expired backup ${NEW[0]}: \`${STARTS[0]}\`, of the oldest kept ${NEW[1]}: \`$(start_of "$I1" "${NEW[1]}")\`."
check "Exactly the 2 newest fulls remain" test "$LEFT" = "$WANT"
check "The oldest backup from before the test ($OLDEST_BEFORE) and backup 1 (${NEW[0]}) were expired" bash -c "! grep -qw '$OLDEST_BEFORE' <<<'$LEFT' && ! grep -qw '${NEW[0]}' <<<'$LEFT'"
check "WAL older than the oldest kept backup was expired with it (archive min = its start WAL)" test "$(amin "$I1")" = "$(start_of "$I1" "${NEW[1]}")"
check "Archive min moved past the expired backup's start WAL (${STARTS[0]})" bash -c "[[ '$(amin "$I1")' > '${STARTS[0]}' && '$(amin "$I1")' > '$(amin "$I0")' ]]"

section "Real setting in force again"
run "grep -h retention deploy/pg/pgbackrest/*.conf; kubectl -n $NS get cronjob pg-backup -o json | jq -c '[.spec.jobTemplate.spec.template.spec.containers[0].env[] | .name]'" || true
check "repo.conf still says repo1-retention-full=7 and the CronJob sets no retention override" bash -c "grep -qx 'repo1-retention-full=7' deploy/pg/pgbackrest/repo.conf && ! kubectl -n $NS get cronjob pg-backup -o json | grep -q RETENTION"
pgbr pg-backup-ret-normal > "$BODY.job" 2>&1 && ok=1 || ok=0
kubectl -n "$NS" delete job pg-backup-ret-normal --wait=false >/dev/null 2>&1 || true
I2=$(pgbr_info); rm -f "$BODY.job"
run "jq -r '.[0].backup[] | .label' <<<'$I2'" || true
check "A normal run (retention 7) keeps all 3 fulls" test "$(labels "$I2" | wc -l)" = 3 -a $ok = 1
l3_finish retention "Retention enforcement" "Three full backups from the CronJob template with a temporary \`PGBACKREST_REPO1_RETENTION_FULL=2\` on those Jobs only, proving the oldest fulls and their WAL are expired, then a normal run with repo.conf's \`repo1-retention-full=7\` keeping every full." test-retention
