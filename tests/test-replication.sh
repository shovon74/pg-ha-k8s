#!/usr/bin/env bash
# L1 gate (T:topology, T:replication, T:endpoints): writes docs/evidence/L1-replication.md with PASS/FAIL per check.
#
# kubectl exec (D4): this committed test runs psql inside its own short-lived client pod, pg-test-client,
# to reach pg-rw, pg-ro and each member's DNS name from inside the cluster. It never execs into a
# Postgres pod. Patroni state is read through the API server's pod proxy. The only fault injected is
# deleting one replica pod. Passwords come from the pg-credentials Secret and are never printed.
. "$(dirname "$0")/../scripts/spikes/lib.sh"
NS=$PG_NS; CLIENT=pg-test-client
EV_FILE="$EV_DIR/L1-replication.md"
BODY=$(mktemp); CHECKS=$(mktemp); FAILS=0; T0=$SECONDS; STARTED=$(date -u +%FT%TZ)
cleanup() { kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=false >/dev/null 2>&1 || true; rm -f "$BODY" "$CHECKS"; }
trap cleanup EXIT

finish() {
  local verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
  { printf '# L1: replication, endpoints and rejoin\n\n**Result: %s**\n\n' "$verdict"
    printf -- '- **Covers:** R1.1, R1.2, R1.3, R1.7 (bytes and seconds), R2.1, R2.2, R7.4 (placement), ADR-004 sync standby, ADR-005 slot cap\n'
    printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make test-replication`\n' "$STARTED" "$((SECONDS-T0))"
    printf -- '- **Versions:** k3s `%s`, image `%s`\n' "${K3S_IMAGE%@*}" "$PG_IMAGE"
    [ ! -f "$EV_DIR/L1-replication-history.md" ] || printf -- '- **History:** [`L1-replication-history.md`](L1-replication-history.md) (maintained by hand, never written by this test)\n'
    printf -- '- **kubectl exec:** psql runs only in the test'"'"'s own client pod `%s`, never in a Postgres pod (D4)\n' "$CLIENT"
    printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_FILE"
  log "RESULT L1: $verdict -> docs/evidence/L1-replication.md"
  [ "$FAILS" -eq 0 ]
}

# q HOST USER SQL: one psql call from the client pod. The password is chosen inside the pod from its env.
q() {
  kubectl -n "$NS" exec "$CLIENT" -- sh -c '
    case "$2" in app) PGPASSWORD=$APP_PW ;; monitor) PGPASSWORD=$MON_PW ;; *) exit 2 ;; esac; export PGPASSWORD
    exec psql "host=$1 user=$2 dbname=app connect_timeout=5" -XAtq -v ON_ERROR_STOP=1 -F " " -c "$3"' sh "$1" "$2" "$3"
}
export -f q; export NS CLIENT   # some checks run in a bash -c subshell
RW=pg-rw.$NS.svc.cluster.local; RO=pg-ro.$NS.svc.cluster.local
member() { echo "$1.pg-headless.$NS.svc.cluster.local"; }
cluster_json() { patroni_cluster; }
leader() { cluster_json | jq -r '.members[] | select(.role == "leader") | .name'; }
pod_ip() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.status.podIP}'; }

kubectl get ns "$NS" >/dev/null 2>&1 || die "namespace $NS not found, run: make up"
patroni_healthy || die "Patroni is not healthy, see: make status"

section "Setup: test client pod (our image, Pod Security restricted)"
kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=true >/dev/null
sed "s|__PG_IMAGE__|$PG_IMAGE|" <<'YAML' | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: pg-test-client, labels: {app.kubernetes.io/name: pg-test-client}}
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: client
    image: __PG_IMAGE__
    imagePullPolicy: IfNotPresent
    command: [sleep, "1800"]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    env:
    - {name: HOME, value: /tmp}
    - name: APP_PW
      valueFrom: {secretKeyRef: {name: pg-credentials, key: pg-app-password}}
    - name: MON_PW
      valueFrom: {secretKeyRef: {name: pg-credentials, key: pg-monitor-password}}
    volumeMounts: [{name: tmp, mountPath: /tmp}]
  volumes: [{name: tmp, emptyDir: {}}]
YAML
kubectl -n "$NS" wait --for=condition=Ready "pod/$CLIENT" --timeout=60s >/dev/null || die "client pod not ready"

section "Topology (T:topology)"
run "patroni_cluster | jq -r '.members[] | \"\(.name) role=\(.role) state=\(.state) timeline=\(.timeline) lag=\(.lag // \"-\")\"'"
run "kubectl -n $NS get pods -l app.kubernetes.io/name=pg -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,ROLE:.metadata.labels.role,READY:.status.containerStatuses[0].ready"
J=$(cluster_json); L=$(leader); LIP=$(pod_ip "$L")
REPLICAS=$(jq -r '.members[] | select(.role != "leader") | .name' <<<"$J" | tr '\n' ' ')
check "Patroni: exactly 1 leader" test "$(jq '[.members[] | select(.role == "leader" and .state == "running")] | length' <<<"$J")" = 1
check "Patroni: exactly 2 streaming replicas" test "$(jq '[.members[] | select(.role != "leader" and .state == "streaming")] | length' <<<"$J")" = 2
check "Patroni: exactly 1 synchronous standby" test "$(jq '[.members[] | select(.role == "sync_standby")] | length' <<<"$J")" = 1
nodes=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=pg -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')
check "Placement: 3 members on 3 distinct agent nodes (R7.4)" bash -c "[ \$(sort -u <<<'$nodes' | grep -c agent) = 3 ]"
for m in $L $REPLICAS; do
  echo "$m: $(q "$(member "$m")" monitor "select 'version_num=' || current_setting('server_version_num') || ' in_recovery=' || pg_is_in_recovery() || ' checksums=' || current_setting('data_checksums') || ' ssl=' || current_setting('ssl')")"
done > /tmp/l1-members.$$ 2>&1
run "cat /tmp/l1-members.$$"
check "Every member runs Postgres >= 15 (R1.1)" bash -c "[ \$(grep -cE 'version_num=(1[5-9]|[2-9][0-9])[0-9]{4}' /tmp/l1-members.$$) = 3 ]"
check "Exactly 1 member not in recovery, 2 in recovery (R1.2)" bash -c "[ \$(grep -c 'in_recovery=false' /tmp/l1-members.$$) = 1 ] && [ \$(grep -c 'in_recovery=true' /tmp/l1-members.$$) = 2 ]"
check "Data checksums and server TLS on every member" bash -c "[ \$(grep -c 'checksums=on ssl=on' /tmp/l1-members.$$) = 3 ]"
rm -f /tmp/l1-members.$$

section "Streaming and the synchronous standby (T:replication)"
REPL_SQL="select application_name, state, sync_state from pg_stat_replication order by application_name"
run "q $RW monitor \"$REPL_SQL\""
R=$(q "$RW" monitor "$REPL_SQL")
check "pg_stat_replication on the primary: 2 rows streaming (R1.3)" test "$(grep -c ' streaming ' <<<"$R")" = 2
check "pg_stat_replication: exactly 1 sync and 1 async standby" bash -c "[ \$(grep -c ' sync\$' <<<'$R') = 1 ] && [ \$(grep -c ' async\$' <<<'$R') = 1 ]"
SYNC=$(jq -r '.members[] | select(.role == "sync_standby") | .name' <<<"$J")
check "Postgres and Patroni agree on the sync standby ($SYNC)" grep -q "^$SYNC streaming sync\$" <<<"$R"
run "q $RW monitor \"select name, setting from pg_settings where name in ('synchronous_commit','synchronous_standby_names') order by name\""

section "Write through pg-rw, read through pg-ro and on each replica"
TOKEN="l1-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
q "$RW" app "create table if not exists l1_marker (token text primary key, written_at timestamptz default now())" >/dev/null
run "q $RW app \"insert into l1_marker(token) values ('$TOKEN') returning token, written_at\""
seen_ro=0; for _ in $(seq 1 20); do [ "$(q "$RO" app "select count(*) from l1_marker where token = '$TOKEN'")" = 1 ] && { seen_ro=1; break; }; sleep 0.5; done
check "Row written through pg-rw is readable through pg-ro" test $seen_ro = 1
for m in $REPLICAS; do
  seen=0; for _ in $(seq 1 20); do [ "$(q "$(member "$m")" app "select count(*) from l1_marker where token = '$TOKEN'")" = 1 ] && { seen=1; break; }; sleep 0.5; done
  check "Row is readable on replica $m (R1.3)" test $seen = 1
done

section "Replication lag in bytes and seconds (R1.7)"
note "Measured on the primary right after a write. \`replay_lag\` is Postgres's own time measurement and becomes NULL once a standby has been idle and caught up, so it is sampled straight after the write."
q "$RW" app "insert into l1_marker(token) values ('$TOKEN-lag')" >/dev/null
LAG_SQL="select application_name, sync_state, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) as lag_bytes, coalesce(round(extract(epoch from replay_lag)::numeric, 6)::text, 'null') as lag_seconds from pg_stat_replication order by application_name"
run "q $RW monitor \"$LAG_SQL\""
LAG=$(q "$RW" monitor "$LAG_SQL")
check "Lag reported in bytes for both standbys" test "$(awk '$3 ~ /^[0-9]+$/' <<<"$LAG" | wc -l)" = 2
check "Lag reported in seconds for both standbys" test "$(awk '$4 ~ /^[0-9.]+$/' <<<"$LAG" | wc -l)" = 2

section "Replication slots and the WAL cap (ADR-005)"
SLOT_SQL="select slot_name, slot_type, active, wal_status, pg_size_pretty(safe_wal_size) as safe_wal_size from pg_replication_slots order by slot_name"
run "q $RW monitor \"$SLOT_SQL\""
run "q $RW monitor \"select name, setting, unit from pg_settings where name in ('max_slot_wal_keep_size','max_wal_size','wal_log_hints') order by name\""
S=$(q "$RW" monitor "select slot_name, slot_type, active, safe_wal_size is not null from pg_replication_slots")
EXPECT_SLOTS=$(for m in $REPLICAS; do echo "${m//-/_}"; done | sort | tr '\n' ' ')
check "One active physical slot per replica ($EXPECT_SLOTS)" bash -c "[ \"\$(awk '\$2==\"physical\" && \$3==\"t\" {print \$1}' <<<'$S' | sort | tr '\n' ' ')\" = '$EXPECT_SLOTS' ]"
check "max_slot_wal_keep_size is 1GB and limits every slot (safe_wal_size set)" bash -c "[ \"\$(q $RW monitor \"select current_setting('max_slot_wal_keep_size')\")\" = 1GB ] && ! awk '\$4!=\"t\"' <<<'$S' | grep -q ."
check "max_wal_size is 512MB" test "$(q "$RW" monitor "select current_setting('max_wal_size')")" = 512MB

section "Client endpoints (T:endpoints)"
RW_EP=$(kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=pg-rw -o jsonpath='{.items[*].endpoints[*].addresses[*]}')
RO_EP=$(kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=pg-ro -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{" "}{end}')
note "Leader \`$L\` has pod IP \`$LIP\`. The pg-rw EndpointSlice (mirrored from Patroni's Endpoints) lists \`$RW_EP\`. pg-ro lists \`$RO_EP\`."
run "q $RW app \"select 'pg-rw: server=' || host(inet_server_addr()) || ' in_recovery=' || pg_is_in_recovery()\""
run "q $RO app \"select 'pg-ro: server=' || host(inet_server_addr()) || ' in_recovery=' || pg_is_in_recovery()\""
check "pg-rw EndpointSlice points only at the leader ($L)" test "$RW_EP" = "$LIP"
check "pg-rw connects to the leader, not in recovery (R2.1)" test "$(q "$RW" app "select host(inet_server_addr()) || ' ' || pg_is_in_recovery()")" = "$LIP false"
check "pg-ro lists exactly the 2 replicas" test "$(tr ' ' '\n' <<<"$RO_EP" | grep -c .)" = 2
check "pg-ro connects to a replica in recovery (R2.2)" test "$(q "$RO" app "select pg_is_in_recovery()")" = t
run "q $RO app \"insert into l1_marker(token) values ('must-fail')\"" || true
check "pg-ro rejects a write (R2.2)" bash -c "! q $RO app \"insert into l1_marker(token) values ('must-fail')\""

section "Replica pod deleted: it rejoins and streams again"
VICTIM=$SYNC
note "Fault: \`kubectl delete pod $VICTIM\` (the synchronous standby). Leader before: \`$L\`, timeline $(jq -r '.members[] | select(.role == "leader") | .timeline' <<<"$J")."
OLD_UID=$(kubectl -n "$NS" get pod "$VICTIM" -o jsonpath='{.metadata.uid}')
t0=$(date +%s.%N)
run "kubectl -n $NS delete pod $VICTIM --wait=false"
# Wait for the replacement pod (new UID) first: the old pod keeps reporting "streaming" while it shuts down.
rejoined=0; new_pod=0
for _ in $(seq 1 240); do
  if [ $new_pod = 0 ]; then
    uid=$(kubectl -n "$NS" get pod "$VICTIM" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
    [ -n "$uid" ] && [ "$uid" != "$OLD_UID" ] && new_pod=1
  fi
  if [ $new_pod = 1 ]; then
    J2=$(cluster_json || true)
    if jq -e --arg v "$VICTIM" '.members[] | select(.name == $v and .state == "streaming")' <<<"$J2" >/dev/null 2>&1 &&
       [ "$(q "$RW" monitor "select count(*) from pg_stat_replication where application_name = '$VICTIM' and state = 'streaming'" 2>/dev/null)" = 1 ] &&
       patroni_healthy; then rejoined=1; break; fi
  fi
  sleep 0.5
done
t1=$(date +%s.%N); RJ=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')
note "Time from delete until the replacement pod (new UID) streams again, seen by both Patroni and pg_stat_replication on the primary: **${RJ} s**."
run "patroni_cluster | jq -r '.members[] | \"\(.name) role=\(.role) state=\(.state) timeline=\(.timeline) lag=\(.lag // \"-\")\"'"
J2=$(cluster_json)
check "Deleted replica $VICTIM came back as a new pod" test $new_pod = 1
check "Deleted replica $VICTIM rejoined and is streaming" test $rejoined = 1
check "Leader unchanged ($L) and timeline unchanged" test "$(jq -r '.members[] | select(.role == "leader") | "\(.name) \(.timeline)"' <<<"$J2")" = "$L $(jq -r '.members[] | select(.role == "leader") | .timeline' <<<"$J")"
check "After rejoin: exactly 1 sync standby" test "$(jq '[.members[] | select(.role == "sync_standby")] | length' <<<"$J2")" = 1
R2=$(q "$RW" monitor "$REPL_SQL")
run "q $RW monitor \"$REPL_SQL\""
check "After rejoin: pg_stat_replication shows 2 streaming rows including $VICTIM" bash -c "[ \$(grep -c ' streaming ' <<<'$R2') = 2 ] && grep -q '^$VICTIM streaming' <<<'$R2'"
check "After rejoin: $VICTIM has the marker row and its slot is active" bash -c "[ \"\$(q $(member "$VICTIM") app \"select count(*) from l1_marker where token = '$TOKEN'\")\" = 1 ] && [ \"\$(q $RW monitor \"select active from pg_replication_slots where slot_name = '${VICTIM//-/_}'\")\" = t ]"

finish
