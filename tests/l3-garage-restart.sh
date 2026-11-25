#!/usr/bin/env bash
# L3 watch item (docs/01-design-options.md, "Phase notes from L0"): restart Garage while clients write, and
# prove WAL archiving recovers on its own within a bounded time. The L2 probe Job writes through pg-rw every
# 500 ms, and a WAL generator in the test client closes a segment every few seconds, so archiving is busy
# when Garage goes away. Fault: kubectl rollout restart of the Garage Deployment (Recreate: the old pod
# stops before the new one starts). Observation: pg_stat_archiver and the .ready backlog on the primary,
# sampled every second as the monitor role (pg_ls_archive_statusdir is granted to pg_monitor).
. "$(dirname "$0")/l3-lib.sh"
BOUND=${BOUND:-120}   # seconds after Garage is Ready again within which archiving must succeed
W=$(mktemp -d); GEN=""
cleanup() { [ -z "$GEN" ] || kill "$GEN" 2>/dev/null || true; kubectl -n "$NS" delete job pg-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT
client_up
until primary_confirms; do sleep 2; done
q "$RW" app "create table if not exists l3_walgen (id int, pad text)" >/dev/null

section "Setup"
RUN_ID="garage-restart-$(date +%s)"; DURATION=600   # read and deleted before it ends
kubectl -n "$NS" delete job pg-probe --ignore-not-found --wait=true >/dev/null
sed "s|__PG_IMAGE__|$PG_IMAGE|; s|__RUN_ID__|$RUN_ID|; s|__DURATION__|$DURATION|" "$ROOT_DIR/tests/probe-job.yaml" | kubectl -n "$NS" apply -f - >/dev/null
until [ "$(kubectl -n "$NS" logs job/pg-probe 2>/dev/null | grep -c '^ACK')" -ge 6 ]; do sleep 1; done
( while :; do q "$RW" app "insert into l3_walgen select g, repeat(md5(g::text), 6) from generate_series(1, 20000) g" >/dev/null 2>&1 || true; sleep 2; done ) & GEN=$!
sample() { q "$RW" monitor "select extract(epoch from clock_timestamp()), a.archived_count, a.failed_count, coalesce(a.last_archived_wal, '-'), coalesce(extract(epoch from a.last_archived_time), 0), coalesce(extract(epoch from a.last_failed_time), 0), (select count(*) from pg_ls_archive_statusdir() where name like '%.ready') from pg_stat_archiver a" 2>/dev/null || true; }
( while :; do sample; sleep 1; done ) > "$W/arch.txt" & SAMPLER=$!
sleep 20
A0=$(tail -1 "$W/arch.txt")
note "Probe run \`$RUN_ID\` writing through pg-rw every 500 ms. WAL generator: about 5 MB every 2 s into \`l3_walgen\`. Leader \`$(leader)\`. Before the restart: archived=$(awk '{print $2}' <<<"$A0") failed=$(awk '{print $3}' <<<"$A0") ready backlog=$(awk '{print $7}' <<<"$A0")."

section "Garage restart"
OLD_POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=garage -o jsonpath='{.items[0].metadata.name}')
T_R=$(now); kubectl -n "$NS" rollout restart deploy/garage >/dev/null
kubectl -n "$NS" rollout status deploy/garage --timeout=180s >/dev/null; T_READY=$(now)
NEW_POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=garage -o jsonpath='{.items[0].metadata.name}')
# Recovery: the first segment archived after Garage is Ready, and the backlog drained (at most 1 .ready file).
end=$((SECONDS + 300)); T_OK=""; T_DRAIN=""
while [ $SECONDS -lt $end ]; do
  l=$(tail -1 "$W/arch.txt")
  [ -n "$T_OK" ] || T_OK=$(awk -v t="$T_READY" '$5 > t {print $5; exit}' "$W/arch.txt")
  [ -z "$T_OK" ] || T_DRAIN=$(awk -v t="$T_OK" '$1 >= t && $7 <= 1 {print $1; exit}' "$W/arch.txt")
  [ -z "$T_DRAIN" ] || break; sleep 2
done
sleep 5; kill "$SAMPLER" 2>/dev/null || true; kill "$GEN" 2>/dev/null || true; GEN=""
A1=$(tail -1 "$W/arch.txt")
FAILED=$(( $(awk '{print $3}' <<<"$A1") - $(awk '{print $3}' <<<"$A0") ))
MAXQ=$(awk -v t="$T_R" '$1 >= t {if ($7 > m) m = $7} END {print m + 0}' "$W/arch.txt")
LAST_OK_BEFORE=$(awk -v t="$T_R" '$5 <= t && $5 > 0 {v = $5} END {print v}' "$W/arch.txt")

# Probe: write availability through the restart (archiving is asynchronous, so writes should not stall).
kubectl -n "$NS" logs job/pg-probe > "$W/probe.txt" 2>/dev/null || true
GAP=$(awk -v a="$T_R" '$1 == "ACK" {print $4}' "$W/probe.txt" | sort -n | awk -v a="$T_R" -v b="${T_DRAIN:-$T_READY}" '$1 >= a - 5 && $1 <= b + 5 { if (p != "" && $1 - p > g) g = $1 - p; p = $1 } END {printf "%.2f", g}')
ERRS=$(awk -v a="$T_R" -v b="${T_DRAIN:-$T_READY}" '$1 == "ERR" && $3 >= a && $3 <= b' "$W/probe.txt" | wc -l)

note "Garage pod \`$OLD_POD\` replaced by \`$NEW_POD\`. Restart issued at $(iso "$T_R") UTC, new pod Ready at +$(secs "$T_R" "$T_READY") s. Last successful archive before the restart at $( [ -n "$LAST_OK_BEFORE" ] && echo "-$(secs "$LAST_OK_BEFORE" "$T_R") s" || echo n/a ). First archive after Garage Ready at +$(secs "$T_R" "$T_OK") s ($(secs "$T_READY" "$T_OK") s after Ready). Backlog drained at +$(secs "$T_R" "$T_DRAIN") s. Archive failures counted: $FAILED. Largest .ready backlog: $MAXQ segments. Probe: largest gap between acknowledged writes in the window $GAP s, $ERRS failed attempts."
run "awk -v t=$T_R '\$1 >= t - 6' $W/arch.txt | awk '{printf \"%s archived=%s failed=%s last=%s ready=%s\\n\", strftime(\"%H:%M:%S\", \$1, 1), \$2, \$3, \$4, \$7}' | awk 'NR % 3 == 1' | head -50" || true

printf '| Garage Ready after restart (s) | First archive after Ready (s) | Backlog drained after restart (s) | Archive failures | Max .ready backlog | Max write gap (s) | Probe errors |\n|---:|---:|---:|---:|---:|---:|---:|\n| %s | %s | %s | %s | %s | %s | %s |\n' \
  "$(secs "$T_R" "$T_READY")" "$(secs "$T_READY" "$T_OK")" "$(secs "$T_R" "$T_DRAIN")" "$FAILED" "$MAXQ" "$GAP" "$ERRS" > "$W/summary"
note "$(cat "$W/summary")"
check "Archiving succeeded again on its own within $BOUND s of Garage being Ready" awk -v d="$(secs "$T_READY" "$T_OK")" -v b="$BOUND" 'BEGIN{exit !(d != "n/a" && d <= b)}'
check "The .ready backlog drained (no permanent stall)" test -n "$T_DRAIN"
check "Writes through pg-rw were not blocked by the outage (max gap under 3 s)" awk -v g="$GAP" 'BEGIN{exit !(g < 3)}'
TAIL=6 run "JOB_WAIT=300 scripts/pgbr-job.sh pg-check-after-garage 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -vE 'command begin'" && ck=1 || ck=0
check "pgbackrest check passes after the restart" test $ck = 1
kubectl -n "$NS" delete job pg-check-after-garage --ignore-not-found --wait=false >/dev/null 2>&1 || true
q "$RW" app "drop table if exists l3_walgen" >/dev/null || true
l3_finish garage-restart "Garage restart while writing" "\`kubectl rollout restart deploy/garage\` while the probe writes every 500 ms and about 5 MB of WAL is generated every 2 s. Measures when archiving succeeds again and when the .ready backlog drains, with no manual action. The bound is $BOUND s after Garage is Ready." test-garage-restart
