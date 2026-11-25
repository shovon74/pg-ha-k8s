#!/usr/bin/env bash
# L3 R4.1: evidence of a truly scheduled backup. Redeploys with BACKUP_SCHEDULE set to every 10 minutes,
# waits for a Job that the CronJob controller created itself (not one made from it by hand), requires it
# to complete with verify status ok, then redeploys with the default schedule and confirms it.
. "$(dirname "$0")/l3-lib.sh"
SHORT=${SHORT_SCHEDULE:-*/10 * * * *}; DEFAULT="0 20 * * *"
section "Short schedule for the evidence run"
BACKUP_SCHEDULE="$SHORT" "$ROOT_DIR/scripts/deploy.sh" >/dev/null
run "kubectl -n $NS get cronjob pg-backup -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone,LAST:.status.lastScheduleTime" || true
T_SET=$(date +%s); note "Schedule set to \`$SHORT\` (UTC) at $(date -u -d "@$T_SET" +%H:%M:%S) UTC."

# A scheduled Job has the CronJob as its owner and lacks the cronjob.kubernetes.io/instantiate=manual annotation.
scheduled_job() {
  kubectl -n "$NS" get jobs -o json | jq -r --argjson t "$T_SET" '.items[]
    | select(any(.metadata.ownerReferences[]?; .kind == "CronJob" and .name == "pg-backup"))
    | select((.metadata.annotations["cronjob.kubernetes.io/instantiate"] // "") != "manual")
    | select((.metadata.creationTimestamp | fromdateiso8601) >= $t) | .metadata.name' | head -1; }
J=""; end=$((SECONDS + 900))
until J=$(scheduled_job) && [ -n "$J" ]; do [ $SECONDS -lt $end ] || break; sleep 5; done
ok=0
if [ -n "$J" ]; then
  until s=$(kubectl -n "$NS" get job "$J" -o jsonpath='{.status.succeeded}/{.status.failed}'); [ "${s%/*}" = 1 ] || [ "${s#*/}" = 1 ] || [ $SECONDS -ge $end ]; do sleep 3; done
  [ "${s%/*}" = 1 ] && ok=1
  section "The scheduled Job"
  run "kubectl -n $NS get job $J -o json | jq -r '{name: .metadata.name, created: .metadata.creationTimestamp, owner: [.metadata.ownerReferences[] | .kind + \"/\" + .name][0], manual: (.metadata.annotations[\"cronjob.kubernetes.io/instantiate\"] // \"no\"), scheduled_at: (.metadata.annotations[\"batch.kubernetes.io/cronjob-scheduled-timestamp\"] // \"-\"), completed: .status.completionTime, succeeded: .status.succeeded}'" || true
  TAIL=40 run "kubectl -n $NS logs job/$J | grep -vE 'command begin'" || true
fi
check "The CronJob controller created a Job on the short schedule (not a manual Job)" test -n "$J"
check "The scheduled Job completed" test $ok = 1
check "Its verify reported status ok" bash -c "kubectl -n $NS logs job/$J | grep -q VERIFY_OK"

section "Default schedule restored"
"$ROOT_DIR/scripts/deploy.sh" >/dev/null
run "kubectl -n $NS get cronjob pg-backup -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone,LAST:.status.lastScheduleTime" || true
check "Schedule restored to the default ($DEFAULT UTC)" test "$(kubectl -n "$NS" get cronjob pg-backup -o jsonpath='{.spec.schedule}')" = "$DEFAULT"
l3_finish scheduled "Scheduled backup (R4.1)" "BACKUP_SCHEDULE set to \`$SHORT\` through \`make deploy\`, one Job created by the CronJob controller itself runs full backup, expire and verify, then the default \`$DEFAULT\` (UTC) is restored." test-backup-schedule
