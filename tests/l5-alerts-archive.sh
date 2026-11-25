#!/usr/bin/env bash
# L5 R10.3 and R9.6, scenario b: object-storage outage for the primary. The primary pod's traffic to Garage is
# dropped for up to HOLD s while a writer fills WAL. Expected: writes continue, ArchiveFailing and ArchiveStale
# fire in Alertmanager; after the block is removed, archiving catches up with no .ready segment left behind and
# both alerts resolve.
#
# Fault injection (D4): docker exec <primary's k3d agent> iptables. One FORWARD rule on the primary's node drops
# TCP from the primary pod's IP to the Garage pod's IP on port 3900 (the S3 API). The Service address is
# translated to the pod address before FORWARD, so the rule sees the real backend (the S2 finding). Removed on exit.
. "$(dirname "$0")/l5-lib.sh"
HOLD=${HOLD:-420}; NODE=; RULE=
cleanup() { [ -z "$RULE" ] || docker exec "$NODE" iptables -D FORWARD $RULE -j DROP 2>/dev/null || true
            [ -z "${WRITER:-}" ] || kill "$WRITER" 2>/dev/null || true; rm -f "$BODY" "$CHECKS" "${WLOG:-}"; }
trap cleanup EXIT
client_up
patroni_healthy || die "Patroni not healthy before the test"
EXPECT="ArchiveFailing ArchiveStale"

section "Before"
PRIMARY=$(leader); NODE=$(pod_node "$PRIMARY"); P_IP=$(pod_ip "$PRIMARY")
G_IP=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=garage -o jsonpath='{.items[0].status.podIP}')
[ -n "$G_IP" ] || die "Garage pod IP not found"
S0=$(archive_stat "$RW"); F0=$(awk '{print $1}' <<<"$S0")
run "echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; archive_stat $RW"
TAIL=10 run "am_lines"
check "No warning or critical alert firing before the fault" test "$(am_json | jq '[.[] | select(.labels.severity != "info")] | length')" = 0
note "Primary \`$PRIMARY\` ($P_IP) on \`$NODE\`. Garage pod $G_IP:3900."

section "Fault"
RULE="-s $P_IP -d $G_IP -p tcp --dport 3900"
T_FAULT=$(date +%s); docker exec "$NODE" iptables -I FORWARD 1 $RULE -j DROP
note "Rule on \`$NODE\`: \`iptables -I FORWARD 1 $RULE -j DROP\` at $(ts "$T_FAULT") UTC. A writer fills one 16 MB+ WAL segment through pg-rw every 15 s."
WLOG=$(mktemp)
( while :; do if wal_fill >/dev/null 2>&1; then echo ok; else echo fail; fi; sleep 15; done >> "$WLOG" ) & WRITER=$!
wait_alerts firing "$HOLD" $EXPECT && FIRED=1 || FIRED=0
section "Alertmanager during the outage (make alerts)"
TAIL=20 run "scripts/alerts.sh"
FIRING=$(am_json)
SP=$(archive_stat "$RW" || echo "? 0 - ? -")
run "echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '$SP'"
kill "$WRITER" 2>/dev/null || true; wait "$WRITER" 2>/dev/null || true; WRITER=
OKW=$(grep -c ok "$WLOG" || true); FAILW=$(grep -c fail "$WLOG" || true)
check "ArchiveFailing fired" test -n "${SEEN_ArchiveFailing:-}"
check "ArchiveStale fired" test -n "${SEEN_ArchiveStale:-}"
check "Writes continued during the outage ($OKW WAL fills succeeded, $FAILW failed)" test "$OKW" -ge 3 -a "$FAILW" = 0
check "Primary did not change during the outage ($(leader))" test "$(leader)" = "$PRIMARY"
READY_PEAK=$(awk '{print $4}' <<<"$SP"); LAST_READY=$(awk '{print $5}' <<<"$SP" | tr ',' '\n' | sort | tail -1)
check "WAL waited in .ready during the outage ($READY_PEAK segments)" test "${READY_PEAK:-0}" -ge 1 2>/dev/null

section "Recovery"
docker exec "$NODE" iptables -D FORWARD $RULE -j DROP; RULE=; T_CLEAR=$(date +%s)
end=$((SECONDS + 300)); T_CAUGHT=
while [ $SECONDS -lt $end ]; do
  s=$(archive_stat "$RW" 2>/dev/null) || { sleep 3; continue; }
  [ "$(awk '{print $4}' <<<"$s")" = 0 ] && { T_CAUGHT=$(date +%s); break; }; sleep 3
done
S1=$(archive_stat "$RW"); LAST1=$(awk '{print $3}' <<<"$S1")
run "echo 'failed_count last_archived_epoch last_archived_wal ready_count ready_names'; echo '$S1'"
check "Archive caught up: no .ready segment left ($(dt "$T_CLEAR" "$T_CAUGHT") s after unblocking)" test -n "$T_CAUGHT"
check "Last archived segment $LAST1 is at or past the newest segment that waited (${LAST_READY:-none})" \
  test -n "$LAST_READY" -a "$(printf '%s\n%s\n' "${LAST_READY:0:24}" "${LAST1:0:24}" | sort | tail -1)" = "${LAST1:0:24}"
archive_check "$RW" "$(awk '{print $1}' <<<"$S1")" "$ARCHIVE_BOUND"
check "A new segment is archived within $ARCHIVE_BOUND s after recovery (${ARCH_T} s, no new failures: $ARCH_FAILED)" test "$ARCH_T" != n/a -a "$ARCH_FAILED" = 0
wait_alerts resolved 600 $EXPECT && RES=1 || RES=0
check "ArchiveFailing and ArchiveStale resolved" test "$RES" = 1
TAIL=10 run "am_lines"
check "No warning or critical alert firing at the end" test "$(am_json | jq '[.[] | select(.labels.severity != "info")] | length')" = 0

row() { printf '| %s | %s | %s | %s | %s |\n' "$1" "$(ts "$(eval echo "\${SEEN_$1:-}")")" "$(dt "$T_FAULT" "$(eval echo "\${SEEN_$1:-}")")" "$(ts "$(eval echo "\${GONE_$1:-}")")" "$(dt "$T_FAULT" "$(eval echo "\${GONE_$1:-}")")"; }
cat >> "$BODY" <<EOF

## Timeline

Times are UTC. Alertmanager was polled every 5 s through the API server's service proxy, so each time is accurate to about 5 s. ArchiveFailing waits for pgBackRest's first failed archive-push. With dropped packets that is its io-timeout (60 s). ArchiveFailing then clears 5 min after the last failure, because its window is 5 min.

<!-- summary -->
| Event | Time | Seconds after fault |
|---|---|---:|
| Primary $PRIMARY blocked from Garage | $(ts "$T_FAULT") | 0 |
| Block removed | $(ts "$T_CLEAR") | $(dt "$T_FAULT" "$T_CLEAR") |
| No .ready segment left (caught up) | $(ts "$T_CAUGHT") | $(dt "$T_FAULT" "$T_CAUGHT") |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
$(row ArchiveFailing)
$(row ArchiveStale)

Archiver failures during the test: $(( $(awk '{print $1}' <<<"$S1") - F0 )). Segments waiting at the end of the outage: ${READY_PEAK:-n/a}.
<!-- /summary -->

Alertmanager's alert objects during the outage:

\`\`\`json
$(jq '[.[] | {alertname: .labels.alertname, severity: .labels.severity, pod: .labels.pod, startsAt, summary: .annotations.summary}]' <<<"$FIRING")
\`\`\`
EOF
l5_finish alerts-archive "Alerts on an object-storage outage (R10.3, R9.6)" \
  "The primary pod's traffic to Garage is dropped with iptables on its node while a writer fills WAL. Writes must continue, ArchiveFailing and ArchiveStale must fire in Alertmanager, and after the block is removed archiving must catch up with no segment left waiting and both alerts resolve." alerts-archive
