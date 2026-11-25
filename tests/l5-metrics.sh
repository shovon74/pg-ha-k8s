#!/usr/bin/env bash
# L5 T:metrics (R10.1), lag measurement (R1.7) and the lag alert on a real fault (R10.3). Then RAM and disk use.
#   1. every scrape target is up, the key series exist, all rules are loaded and healthy;
#   2. no warning or critical alert is firing on the healthy cluster; nothing from pg-restore is scraped;
#   3. induced lag: the async standby's replication stream is throttled while the probe writes. Lag in bytes and
#      seconds must rise above the alert thresholds, ReplicationLagHigh must fire in Alertmanager, and after the
#      throttle is removed lag must return to near zero and the alert resolve.
#
# Fault injection (D4): docker exec <primary's k3d agent> iptables. Two FORWARD rules on the primary's node let
# through at most LIMIT packets/s from the primary pod's port 5432 to the async standby pod and drop the rest, so
# the stream slows down but the connection stays up (a full block would end it after wal_sender_timeout, 60 s,
# and remove the pg_stat_replication row). Both rules are removed on exit.
. "$(dirname "$0")/l5-lib.sh"
LIMIT=${LIMIT:-40}; HOLD=${HOLD:-300}   # LIMIT packets/s; HOLD = longest wait for the alert, in s
NODE=; RULES=
cleanup() {
  [ -z "$RULES" ] || { docker exec "$NODE" iptables -D FORWARD $RULES -j DROP 2>/dev/null || true
                       docker exec "$NODE" iptables -D FORWARD $RULES -m limit --limit "$LIMIT/sec" --limit-burst "$LIMIT" -j ACCEPT 2>/dev/null || true; }
  [ -z "${WRITER:-}" ] || kill "$WRITER" 2>/dev/null || true
  rm -f "$BODY" "$CHECKS" "${TGT_F:-}" "${RULES_F:-}"
}
trap cleanup EXIT
client_up

section "Scrape targets (R10.1)"
TGT_F=$(mktemp); RULES_F=$(mktemp)
kubectl get --raw "$SVC/prometheus:9090/proxy/api/v1/targets?state=active" > "$TGT_F"; TGT=$(cat "$TGT_F")
run "jq -r '.data.activeTargets[] | \"\(.labels.job) \(.labels.instance) \(.health)\"' $TGT_F | sort"
NODES=$(kubectl get nodes --no-headers | wc -l)
for j in patroni:3 postgres:3 node:$NODES kube-state-metrics:1 kube-state-metrics-self:1 alertmanager:1 prometheus:1; do
  n=$(jq --arg j "${j%:*}" '[.data.activeTargets[] | select(.labels.job == $j and .health == "up")] | length' <<<"$TGT")
  check "Job ${j%:*}: ${j#*:} target(s) up (found $n)" test "$n" = "${j#*:}"
done
check "No target is down" test "$(jq '[.data.activeTargets[] | select(.health != "up")] | length' <<<"$TGT")" = 0

section "Key series (R10.1)"
note "One query per signal that an alert or the lag measurement depends on. Values at the time of the run."
key() { # description query expected-min-series
  local out n; out=$(promq "$2" 2>/dev/null) || out=; n=$(grep -c . <<<"$out" || true)
  printf '\n`%s`\n\n```\n%s\n```\n' "$2" "${out:-(no series)}" >> "$BODY"
  check "$1: $n series (need $3)" test "$n" -ge "$3"
}
key "Patroni role per member" 'patroni_primary{namespace="pg-ha"}' 3
key "Exactly one primary" 'sum(patroni_primary{namespace="pg-ha"}) == 1' 1
key "Sync standby flag" 'sum(patroni_sync_standby{namespace="pg-ha"}) == 1' 1
key "Postgres reachable by each exporter" 'pg_up{namespace="pg-ha"} == 1' 3
key "Timeline" 'patroni_postgres_timeline{namespace="pg-ha"}' 3
key "Replication lag in bytes per standby (primary's view)" 'pg_ha_replication_lag_bytes{namespace="pg-ha"}' 2
key "Replication lag in seconds per standby (primary's view)" 'pg_ha_replication_replay_lag_seconds{namespace="pg-ha"}' 2
key "Slot WAL retention" 'pg_ha_slot_retained_bytes{namespace="pg-ha"}' 2
key "Archiver failure counter" 'pg_stat_archiver_failed_count{namespace="pg-ha"}' 3
key "Archive backlog (.ready)" 'pg_ha_archive_oldest_ready_seconds{namespace="pg-ha"}' 3
key "Backup and restore-test CronJobs" 'kube_cronjob_created{namespace="pg-ha"}' 2
key "Backup or restore-test Job status" 'kube_job_status_succeeded{namespace="pg-ha", job_name=~"pg-backup-.+|pg-restore-test.*"}' 1
key "Expected member count" 'kube_statefulset_replicas{namespace="pg-ha", statefulset="pg"}' 1
key "CoreDNS availability" 'kube_deployment_status_replicas_available{namespace="kube-system", deployment="coredns"}' 1
key "Root filesystem free space per node" 'node_filesystem_avail_bytes{mountpoint="/"}' "$NODES"
RESTORE=$(promq 'count({namespace="pg-restore"})')
check "No series from namespace pg-restore is scraped" test -z "$RESTORE"

section "Rules"
kubectl get --raw "$SVC/prometheus:9090/proxy/api/v1/rules" > "$RULES_F"; RULES_JSON=$(cat "$RULES_F")
run "jq -r '.data.groups[] | .name as \$g | .rules[] | \"\(\$g) \(.name) \(.health) \(.state)\"' $RULES_F"
check "19 alerting rules loaded" test "$(jq '[.data.groups[].rules[] | select(.type == "alerting")] | length' <<<"$RULES_JSON")" = 19
check "Every rule evaluates without error" test "$(jq '[.data.groups[].rules[] | select(.health != "ok")] | length' <<<"$RULES_JSON")" = 0
section "Alerts on the healthy cluster"
TAIL=20 run "am_lines"
check "No warning or critical alert firing before the fault" test "$(am_json | jq '[.[] | select(.labels.severity != "info")] | length')" = 0

section "Induced lag (R1.7, R10.3)"
PRIMARY=$(leader); NODE=$(pod_node "$PRIMARY"); P_IP=$(pod_ip "$PRIMARY")
ASYNC=$(q "$RW" monitor "select application_name from pg_stat_replication where sync_state = 'async' limit 1")
[ -n "$ASYNC" ] || die "no async standby"
A_IP=$(pod_ip "$ASYNC")
note "Primary \`$PRIMARY\` on \`$NODE\`, async standby \`$ASYNC\`. Its stream is limited to $LIMIT packets/s until ReplicationLagHigh fires (at most $HOLD s) while a writer fills WAL through pg-rw (one 16 MB+ fill every 10 s). Lag is read from Prometheus, which is what the alerts use."
LAG_Q="pg_ha_replication_lag_bytes{namespace=\"pg-ha\",application_name=\"$ASYNC\"}"
SEC_Q="pg_ha_replication_replay_lag_seconds{namespace=\"pg-ha\",application_name=\"$ASYNC\"}"
B0=$(promv "$LAG_Q"); S0=$(promv "$SEC_Q")
RULES="-s $P_IP -d $A_IP -p tcp --sport 5432"
T_FAULT=$(date +%s)
docker exec "$NODE" iptables -I FORWARD 1 $RULES -j DROP
docker exec "$NODE" iptables -I FORWARD 1 $RULES -m limit --limit "$LIMIT/sec" --limit-burst "$LIMIT" -j ACCEPT
( while :; do wal_fill >/dev/null 2>&1 || true; sleep 10; done ) & WRITER=$!
wait_alerts firing "$HOLD" ReplicationLagHigh && FIRED=1 || FIRED=0
LAG_FIRING=$(am_lines | grep ReplicationLagHigh || true)
BMAX=$(promv "max_over_time(${LAG_Q}[10m])"); SMAX=$(promv "max_over_time(${SEC_Q}[10m])")
STREAMING=$(q "$RW" monitor "select state from pg_stat_replication where application_name = '$ASYNC'")
kill "$WRITER" 2>/dev/null || true; wait "$WRITER" 2>/dev/null || true; WRITER=
docker exec "$NODE" iptables -D FORWARD $RULES -j DROP
docker exec "$NODE" iptables -D FORWARD $RULES -m limit --limit "$LIMIT/sec" --limit-burst "$LIMIT" -j ACCEPT
RULES=; T_CLEAR=$(date +%s)
# Back to near zero: under 1 MiB and under 1 s, as scraped.
end=$((SECONDS + 180)); T_ZERO=
while [ $SECONDS -lt $end ]; do
  b=$(promv "$LAG_Q"); s=$(promv "$SEC_Q")
  awk -v b="${b:-1e18}" -v s="${s:-1e9}" 'BEGIN{exit !(b < 1048576 && s < 1)}' && { T_ZERO=$(date +%s); break; }
  sleep 5
done
B1=$(promv "$LAG_Q"); S1=$(promv "$SEC_Q")
wait_alerts resolved 300 ReplicationLagHigh && RESOLVED=1 || RESOLVED=0
cat >> "$BODY" <<EOF

<!-- summary -->
| Measure | Before | Peak during throttle | After |
|---|---:|---:|---:|
| Lag bytes ($ASYNC) | ${B0:-n/a} | ${BMAX:-n/a} | ${B1:-n/a} |
| Lag seconds ($ASYNC) | ${S0:-n/a} | ${SMAX:-n/a} | ${S1:-n/a} |

| Event | Time (UTC) | Seconds after throttle start |
|---|---|---:|
| Throttle on | $(ts "$T_FAULT") | 0 |
| ReplicationLagHigh first seen firing | $(ts "${SEEN_ReplicationLagHigh:-}") | $(dt "$T_FAULT" "${SEEN_ReplicationLagHigh:-}") |
| Throttle off | $(ts "$T_CLEAR") | $(dt "$T_FAULT" "$T_CLEAR") |
| Lag back under 1 MiB and 1 s | $(ts "$T_ZERO") | $(dt "$T_FAULT" "$T_ZERO") |
| ReplicationLagHigh gone from Alertmanager | $(ts "${GONE_ReplicationLagHigh:-}") | $(dt "$T_FAULT" "${GONE_ReplicationLagHigh:-}") |
<!-- /summary -->

Alertmanager while firing:

\`\`\`
${LAG_FIRING:-(none)}
\`\`\`
EOF
check "Lag in bytes rose above the 16 MiB threshold (peak ${BMAX:-n/a})" awk -v v="${BMAX:-0}" 'BEGIN{exit !(v > 16777216)}'
check "Lag in seconds rose above the 30 s threshold (peak ${SMAX:-n/a})" awk -v v="${SMAX:-0}" 'BEGIN{exit !(v > 30)}'
check "The standby stayed connected during the throttle (state ${STREAMING:-none})" test -n "$STREAMING"
check "ReplicationLagHigh fired in Alertmanager" test "$FIRED" = 1
check "Lag returned to near zero (< 1 MiB, < 1 s) within 180 s of removing the throttle" test -n "$T_ZERO"
check "ReplicationLagHigh resolved in Alertmanager" test "$RESOLVED" = 1

section "Resources with monitoring running"
note "Measured after the lag test. Memory per component is the resident set of its main process, as each one reports it (process_resident_memory_bytes). The host has no metrics-server (k3s's is disabled, ADR-001), so pod memory comes from these metrics and from docker stats on the k3d node containers."
run "promq 'sum by (job) (process_resident_memory_bytes)'"
run "promq 'prometheus_tsdb_head_series'"
run "promq 'sum(prometheus_tsdb_storage_blocks_bytes) + sum(prometheus_tsdb_wal_storage_size_bytes) + sum(prometheus_tsdb_head_chunks_storage_size_bytes)'"
run "docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' \$(docker ps -q --filter name=k3d-$CLUSTER_NAME)"
run "free -m"
run "df -h /"
RSS=$(promq 'sum by (job) (process_resident_memory_bytes) / 1048576' | sort | while read -r l v; do
  printf '| %s | %s | %.0f MiB |\n' "${l#job=}" "$(promv "count(process_resident_memory_bytes{${l/=/=\"}\"})")" "$v"; done)
TSDB=$(promv 'sum(prometheus_tsdb_storage_blocks_bytes) + sum(prometheus_tsdb_wal_storage_size_bytes) + sum(prometheus_tsdb_head_chunks_storage_size_bytes)')
cat >> "$BODY" <<EOF

<!-- summary -->
| Component (scrape job) | Processes | Resident memory, total |
|---|---:|---:|
$RSS
| Prometheus TSDB on disk | | $(awk -v v="${TSDB:-0}" 'BEGIN{printf "%.0f MiB", v/1048576}') |
| Host memory used / total | | $(free -m | awk '/^Mem:/{print $3 " / " $2 " MiB"}') |
| Host disk used / size (/) | | $(df -h / | awk 'NR==2{print $3 " / " $2 " (" $5 ")"}') |
<!-- /summary -->
EOF
l5_finish metrics "Scrape targets, key series, lag measurement and resources (R10.1, R1.7)" \
  "Every scrape target up, the key series for each alert present, all rules loaded and healthy, nothing firing on the healthy cluster, nothing scraped from pg-restore. Then induced lag (R1.7): the async standby's stream is throttled with iptables on the primary's node while a writer fills WAL. Lag in bytes and seconds must rise past the alert thresholds, ReplicationLagHigh must fire in Alertmanager (R10.3), and after the throttle lag must return to near zero and the alert resolve. Then RAM and disk use with monitoring running." test-metrics
