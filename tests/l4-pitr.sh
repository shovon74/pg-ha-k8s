#!/usr/bin/env bash
# L4 R5.3 (ADR-010): point-in-time recovery to a timestamp between two marked writes. Marker A is committed,
# then T is recorded with a timezone offset (Asia/Dhaka, +06, as the lead would type it). After waiting past
# archive_timeout, marker B is committed and the segment is closed by a WAL fill (the test has no superuser
# for pg_switch_wal()), so B is in the archive too. make restore TARGET_TIME=T must then contain A and not
# B. The restore is timed end to end, from the command to a healthy 1+2 cluster. pgBackRest picks the
# newest backup before T; when that backup is on an older timeline, recovery also crosses every timeline
# switch in between (R5.5), which is reported.
. "$(dirname "$0")/l4-lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
client_up
section "Markers around T"
TL=$(patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline')
q "$RW" app "create table if not exists pitr_marker (id text primary key, t timestamptz not null default clock_timestamp())" >/dev/null
RUN=$(date +%s)
A=$(q "$RW" app "insert into pitr_marker (id) values ('A-$RUN') returning id || ' ' || to_char(t at time zone 'UTC', 'HH24:MI:SS.US')")
sleep 1
T=$(q "$RW" app "select to_char(clock_timestamp() at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI:SS') || '+06'")
T_EPOCH=$(date -d "$T" +%s.%N)
sleep 1
note "Marker A \`${A% *}\` committed at ${A#* } UTC. Target T = \`$T\` ($(date -u -d "$T" +'%F %T') UTC). Source leader \`$(leader)\`, timeline $TL."
archived_after "$T_EPOCH" 150 >/dev/null && a1=1 || a1=0
check "The segment holding A was archived after T (within archive_timeout + margin)" test $a1 = 1
# B comes only after archive_timeout (60 s) has passed since T, as the L4 brief specifies.
while [ $(( $(date +%s) - ${T_EPOCH%.*} )) -lt 65 ]; do sleep 1; done
B=$(q "$RW" app "insert into pitr_marker (id) values ('B-$RUN') returning id || ' ' || to_char(t at time zone 'UTC', 'HH24:MI:SS.US')")
TB=$(now); wal_fill; archived_after "$TB" 120 >/dev/null && b1=1 || b1=0
note "Marker B \`${B% *}\` committed at ${B#* } UTC, $(awk -v a="$T_EPOCH" -v b="$(date -d "${B#* } UTC" +%s.%N)" 'BEGIN{printf "%.1f", b-a}') s after T, then the segment was closed by a WAL fill."
check "The segment holding B was archived too, so recovery must stop at T rather than run out of WAL" test $b1 = 1
run "q $RW app \"select id, t from pitr_marker where id like '%-$RUN' order by t\"" || true

section "make restore TARGET_TIME=T"
NS=$RNS "$ROOT_DIR/scripts/restore-clean.sh" >/dev/null 2>&1 || true
T_R=$(now); TAIL=12 run "NS=$RNS TARGET_TIME='$T' scripts/restore.sh" && ok=1 || ok=0; T_D=$(now)
check "make restore TARGET_TIME='$T' completed: 1 leader, 2 streaming replicas, 1 sync standby" test $ok = 1
RL=$(rleader)
run "kubectl -n $RNS logs $RL -c postgres | grep -E 'starting point-in-time recovery|recovery stopping|last completed transaction|selected new timeline|archive recovery complete|restore backup set|post-bootstrap' | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -10" || true

BSET=$(kubectl -n "$RNS" logs "$RL" -c postgres 2>/dev/null | sed -nE 's/.*restore backup set ([0-9F-]+),.*/\1/p' | head -1)
note "Backup set used: \`${BSET:-unknown}\`. Recovery target timeline \`latest\`; the source was on timeline $TL at T."

section "Result"
run "q $RRW app \"select id, t from pitr_marker where id like '%-$RUN' order by t\"" || true
check "Marker A (before T) is present" test "$(q "$RRW" app "select count(*) from pitr_marker where id = 'A-$RUN'")" = 1
check "Marker B (after T) is absent" test "$(q "$RRW" app "select count(*) from pitr_marker where id = 'B-$RUN'")" = 0
check "archive_mode is off on the restored primary" test "$(q "$RRW" monitor "select setting from pg_settings where name = 'archive_mode'")" = off
note "End to end: $(secs "$T_R" "$T_D") s from \`make restore\` to a healthy restored cluster."
T_C=$(now); NS=$RNS "$ROOT_DIR/scripts/restore-clean.sh" >/dev/null && cl=1 || cl=0
check "make restore-clean removed pg-restore ($(secs "$T_C" "$(now)") s)" bash -c "test $cl = 1 && ! kubectl get ns $RNS >/dev/null 2>&1"
printf '| PITR restore end to end (s) | Target T | Source timeline |\n|---:|---|---:|\n| %s | %s | %s |\n' "$(secs "$T_R" "$T_D")" "$T" "$TL" > "$W/sum"; note "$(cat "$W/sum")"
l4_finish pitr "Point-in-time recovery (R5.3)" "Marker A committed, T recorded in UTC+6, marker B committed after archive_timeout and archived, then \`make restore TARGET_TIME=T\` into the empty \`pg-restore\` namespace. A must be present and B absent." test-pitr
