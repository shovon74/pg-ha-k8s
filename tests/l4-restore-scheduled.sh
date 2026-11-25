#!/usr/bin/env bash
# L4 R4.5: a restore test Job created by the pg-restore-test CronJob itself, on a short schedule
# (RESTORE_TEST_SCHEDULE='*/5 * * * *'), then the default schedule restored. Same approach as L3 R4.1.
. "$(dirname "$0")/l4-lib.sh"
SHORT=${SHORT:-*/5 * * * *}
section "Short schedule"
T_S=$(date +%s)
RESTORE_TEST_SCHEDULE="$SHORT" "$ROOT_DIR/scripts/deploy.sh" > "$BODY.d" 2>&1 && d=1 || d=0
grep -E 'restore test:' "$BODY.d" || true
check "Deployed with RESTORE_TEST_SCHEDULE='$SHORT'" bash -c "test $d = 1 && [ \"\$(kubectl -n $NS get cronjob pg-restore-test -o jsonpath='{.spec.schedule}')\" = '$SHORT' ]"
J=""; end=$((SECONDS + 420))
while [ $SECONDS -lt $end ] && [ -z "$J" ]; do
  J=$(kubectl -n "$NS" get jobs -o json | jq -r --argjson t "$T_S" '.items[] | select(.metadata.ownerReferences[0].kind == "CronJob" and .metadata.ownerReferences[0].name == "pg-restore-test" and (.metadata.annotations["cronjob.kubernetes.io/instantiate"] // "") != "manual" and (.metadata.creationTimestamp | fromdateiso8601) >= $t) | .metadata.name' | head -1)
  [ -n "$J" ] || sleep 5
done
check "The CronJob created a Job on its own schedule" test -n "$J"
if [ -n "$J" ]; then
  kubectl -n "$NS" wait --for=condition=complete "job/$J" --timeout=900s >/dev/null 2>&1 || true
  run "kubectl -n $NS get job $J -o json | jq -r '\"job \\(.metadata.name) created \\(.metadata.creationTimestamp) by \\(.metadata.ownerReferences[0].kind)/\\(.metadata.ownerReferences[0].name), annotations \\(.metadata.annotations // {} | keys)\"'" || true
  TAIL=14 run "kubectl -n $NS logs job/$J | grep -vE '^ +[0-9]+/[0-9]+ '" || true
  check "The scheduled restore test succeeded (RESTORE_TEST_OK)" bash -c "kubectl -n $NS logs job/$J | grep -q RESTORE_TEST_OK && [ \"\$(kubectl -n $NS get job $J -o jsonpath='{.status.succeeded}')\" = 1 ]"
fi
section "Default schedule restored"
"$ROOT_DIR/scripts/deploy.sh" > "$BODY.d" 2>&1 && d2=1 || d2=0
check "Default schedule restored (0 21 * * *)" bash -c "test $d2 = 1 && [ \"\$(kubectl -n $NS get cronjob pg-restore-test -o jsonpath='{.spec.schedule}')\" = '0 21 * * *' ]"
rm -f "$BODY.d"
l4_finish restore-scheduled "Restore test Job, scheduled (R4.5)" "The \`pg-restore-test\` CronJob deployed with a short schedule (\`$SHORT\`), a Job created by the CronJob itself (not \`make\`) checked for RESTORE_TEST_OK, then the default daily 21:00 UTC schedule restored." test-restore-schedule
