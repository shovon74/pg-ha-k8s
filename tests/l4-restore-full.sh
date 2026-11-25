#!/usr/bin/env bash
# L4 R5.1 (ADR-010): make restore with no target restores the whole cluster from the repository into the empty
# pg-restore namespace, to the end of the archive on the latest timeline. Requires 1 primary and 2 streaming
# replicas, the source's row counts and checksums, history files present, archive_mode off, and no WAL from
# the restored cluster in the source archive. Cleans up with make restore-clean, which is timed too.
. "$(dirname "$0")/l4-lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
client_up
section "Before: source and repository"
TL=$(patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline')
q "$RW" app "$FP_SQL" | sort > "$W/src"
HIST=$(repo_history); NH=$(grep -c . <<<"$HIST" || true); DIRS0=$(repo_wal_dirs)
note "Source leader \`$(leader)\` on timeline $TL. Source fingerprint (rows and hashtext sums of the seeded tables): $(paste -sd' ' "$W/src")."
note "History files in the repository archive: $NH ($(head -1 <<<"$HIST") to $(tail -1 <<<"$HIST")). WAL directories: $(paste -sd' ' <<<"$DIRS0")."
check "Timeline history files are present for every timeline switch up to $TL (found $NH, need $((TL - 1)))" test "$NH" -ge $((TL - 1))
q "$RW" app "create table if not exists l4_marker (id text primary key, t timestamptz default clock_timestamp())" >/dev/null
q "$RW" app "insert into l4_marker (id) values ('full-$(date +%s)') returning id" > "$W/marker"
wal_fill; archived_after "$(now)" 120 >/dev/null || true
note "Marker row \`$(cat "$W/marker")\` written and archived before the restore."

section "make restore (latest)"
NS=$RNS "$ROOT_DIR/scripts/restore-clean.sh" >/dev/null 2>&1 || true
T_R=$(now); TAIL=12 run "NS=$RNS scripts/restore.sh" && ok=1 || ok=0; T_D=$(now)
check "make restore completed: 1 leader, 2 streaming replicas, 1 sync standby in $RNS" test $ok = 1
RL=$(rleader); RTL=$(rpatroni | jq -r '.members[] | select(.role == "leader") | .timeline')
note "Restore wall time $(secs "$T_R" "$T_D") s. Restored leader \`$RL\` on timeline $RTL."
run "kubectl -n $RNS logs $RL -c postgres | grep -E 'Running custom bootstrap|restore-bootstrap|restore command end|recovery stopping|redo done|selected new timeline|archive recovery complete|post-bootstrap|bootstrap from leader|replica has been created' | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -14" || true

section "Restored data and isolation"
q "$RRW" app "$FP_SQL" | sort > "$W/dst"
run "join -t= $W/src $W/dst | awk -F= '{printf \"%-24s source %-22s restored %-22s %s\\n\", \$1, \$2, \$3, (\$2 == \$3 ? \"match\" : \"MISMATCH\")}'" || true
check "Row counts and checksums of the seeded tables match the source" cmp -s "$W/src" "$W/dst"
check "The marker row written just before the restore is present" test "$(q "$RRW" app "select count(*) from l4_marker where id = '$(cat "$W/marker")'")" = 1
check "Restored cluster is on a new timeline above the source's ($RTL > $TL)" test "$RTL" -gt "$TL"
run "q $RRW monitor \"select name, setting from pg_settings where name in ('archive_mode', 'archive_command') order by 1\"" || true
check "archive_mode is off on the restored primary" test "$(q "$RRW" monitor "select setting from pg_settings where name = 'archive_mode'")" = off
check "The restored primary archived nothing" test "$(q "$RRW" monitor "select archived_count + failed_count from pg_stat_archiver")" = 0
DIRS1=$(repo_wal_dirs); RTLX=$(printf '%08X' "$RTL")
check "The source archive has no WAL on the restored timeline ($RTLX)" bash -c "! grep -q '^$RTLX' <<<'$DIRS1'"
check "Passwords from this namespace's Secret work on the restored cluster (post_bootstrap reset)" bash -c "q $RRW app 'select 1' >/dev/null && q $RRW monitor 'select 1' >/dev/null"

section "make restore-clean"
T_C=$(now); TAIL=4 run "NS=$RNS scripts/restore-clean.sh" && cl=1 || cl=0
check "make restore-clean deleted only the pg-restore namespace and its PVCs ($(secs "$T_C" "$(now)") s)" bash -c "test $cl = 1 && ! kubectl get ns $RNS >/dev/null 2>&1 && kubectl get ns $PG_NS >/dev/null"
q "$RW" app "drop table if exists l4_marker" >/dev/null || true
printf '| Restore wall time (s) | Restored timeline | Source timeline | History files |\n|---:|---:|---:|---:|\n| %s | %s | %s | %s |\n' "$(secs "$T_R" "$T_D")" "$RTL" "$TL" "$NH" > "$W/sum"; note "$(cat "$W/sum")"
l4_finish restore-full "Full restore into an empty namespace (R5.1)" "\`make restore\` with no target: the whole cluster restored from Garage into the empty \`pg-restore\` namespace through Patroni's custom bootstrap, to the end of the archive on the latest timeline. Compared with the source, then removed with \`make restore-clean\`." test-restore-full
