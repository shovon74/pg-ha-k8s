#!/usr/bin/env bash
# L3 R4.6: backup after failover. Runs one L2 node failover (stop the primary's k3d agent, restart it), with
# its evidence written under L3/ so the L2 results stay as they are. Then requires that archiving continues
# on the new timeline with no failures on the new primary, that pgbackrest check passes, and that a backup
# with verify succeeds from the new primary with no config change.
. "$(dirname "$0")/l3-lib.sh"
client_up
tl() { patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline'; }
OLD=$(leader); TL0=$(tl)
section "Failover: one node-stop run of the L2 harness"
note "Before: leader \`$OLD\`, timeline $TL0. The full failover evidence is in [\`failover-node-run.md\`](failover-node-run.md)."
RUNS=1 EV_OUT="$EV_DIR/L3/failover-node-run.md" "$ROOT_DIR/tests/failover.sh" node > "$BODY.fo" 2>&1 && fo=1 || fo=0
run "grep -E '^run 1:|RESULT' $BODY.fo" || true; rm -f "$BODY.fo"
check "Node failover run passed (RTO, RPO 0, one primary, old primary rejoined)" test $fo = 1
client_up
NEW=$(leader); TL1=$(tl); TLX=$(printf '%08X' "$TL1"); T_AFTER=$(date +%s)
note "After: leader \`$NEW\`, timeline $TL1 (WAL prefix \`$TLX\`)."
check "Leadership moved to another member on a higher timeline" test "$NEW" != "$OLD" -a "$TL1" -gt "$TL0"

section "Archiving on the new timeline"
A0=$(archiver); AT=$(archived_after "$T_AFTER" 150) || AT=""; A1=$(archiver)
run "q $RW monitor 'select inet_server_addr(), archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal, last_failed_time from pg_stat_archiver'" || true
check "The new primary archived a segment within 150 s" test -n "$AT"
check "The latest archived segment is on the new timeline ($TLX)" bash -c "[[ '$(awk '{print $3}' <<<"$A1")' == $TLX* ]]"
check "No archive failures on the new primary during the check" test "$(awk '{print $2}' <<<"$A0")" = "$(awk '{print $2}' <<<"$A1")"
TAIL=6 run "JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-failover 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'" && ck=1 || ck=0
check "pgbackrest check passes against the new primary" test $ck = 1

section "Backup and verify after failover (no config change)"
B=pg-backup-after-failover
TAIL=30 run "scripts/pgbr-job.sh $B | grep -vE 'command begin'" && bk=1 || bk=0
START=$(kubectl -n "$NS" logs "job/$B" 2>/dev/null | sed -nE 's/.*backup start archive = ([0-9A-F]{24}).*/\1/p')
check "Backup completed with verify status ok" bash -c "test $bk = 1 && kubectl -n $NS logs job/$B | grep -q VERIFY_OK"
check "The backup started on the new timeline ($TLX), so it was taken from the new primary" bash -c "[[ '$START' == $TLX* ]]"
kubectl -n "$NS" delete job "$B" pg-check-after-failover --ignore-not-found --wait=false >/dev/null 2>&1 || true
l3_finish failover "Backup after failover (R4.6)" "One node failover (\`docker stop\` of the primary's k3d agent, then \`docker start\`, from the L2 harness), then archiving on the new timeline, \`pgbackrest check\`, and a full backup with verify, with no configuration change." test-backup-failover
