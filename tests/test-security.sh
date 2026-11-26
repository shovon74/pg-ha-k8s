#!/usr/bin/env bash
# L6 security baseline gate (ADR-012): T:tls (R8.4), T:db-authz (R8.5), T:netpol (R8.6), T:pod-security (R8.7),
# T:rbac (R8.8), Patroni REST API auth, and a credential scan of the full git history (R8.2). Writes
# docs/evidence/L6-security.md. Expected refusals count as PASS only when they fail for the expected reason.
#
# kubectl exec (D4): psql and TCP probes run only in this script's own pods: the test client pg-test-client in
# pg-ha (tests/lib.sh) and a throwaway pod "outsider" in namespace l6-outsider, deleted on exit. Nothing is ever
# exec'd in a Postgres, Garage or monitoring pod. The REST API is reached over kubectl port-forward (as the
# switchover harness does), and Pod Security is tested with server-side dry runs, so nothing is created.
. "$(dirname "$0")/lib.sh"
OUT_NS=l6-outsider; W=$(mktemp -d); PF=
cleanup() {
  [ -z "$PF" ] || { kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null; } || true
  [ "${KEEP:-0}" = 1 ] || kubectl delete ns "$OUT_NS" --wait=false >/dev/null 2>&1 || true
  rm -rf "$W" "$BODY" "$CHECKS"
}
trap cleanup EXIT
kubectl get ns "$NS" >/dev/null 2>&1 || die "namespace $NS not found, run: make up"
patroni_healthy || die "Patroni is not healthy, see: make status"

# try CMD: runs CMD, records it with its output in the evidence, sets OUT and RC.
try() { OUT=$(eval "$1" 2>&1) && RC=0 || RC=$?
  { printf '\n```console\n$ %s\n%s\n' "$1" "$OUT"; [ "$RC" = 0 ] || printf '[exit code %s]\n' "$RC"; printf '```\n'; } | redact >> "$BODY"; }
ok_out()  { [ "$RC" = 0 ] && grep -qE -- "$1" <<<"$OUT"; }     # succeeded, and the output matches
refused() { [ "$RC" != 0 ] && grep -qE -- "$1" <<<"$OUT"; }    # failed, for the expected reason
# cx PWVAR CONNINFO SQL: psql in the client pod. The password is picked inside the pod from its own env.
cx() { kubectl -n "$NS" exec "$CLIENT" -- sh -c '
  case "$1" in app) PGPASSWORD=$APP_PW ;; monitor) PGPASSWORD=$MON_PW ;; app_ro) PGPASSWORD=$APP_RO_PW ;;
    wrong) PGPASSWORD=not-the-password ;; none) unset PGPASSWORD ;; *) exit 2 ;; esac; [ -z "${PGPASSWORD:-}" ] || export PGPASSWORD
  exec psql "$2 connect_timeout=5" -XAtq -v ON_ERROR_STOP=1 -F " " -c "$3"' sh "$1" "$2" "$3"; }
# Checks below read OUT (or a saved copy) through these functions, never by pasting output into bash -c.
count_is() { [ "$(grep -cE -- "$1" <<<"$OUT")" = "$2" ]; }                  # PATTERN N: exactly N matching lines
none_but() { ! grep -E -- "$1" <<<"$OUT" | grep -vqE -- "$2"; }             # every line matching $1 also matches $2
all_match() { ! grep -vE -- "$1" <<<"$OUT" | grep -q .; }                   # every non-empty line matches
no_warning() { [ "$RC" = 0 ] && ! grep -qi warning <<<"$OUT"; }
where() { [ "$1" = - ] && echo "the cluster" || echo "$1"; }
# tcp NS POD HOST PORT: prints open, or blocked with the reason (kube-router rejects denied connections).
tcp() { kubectl -n "$1" exec "$2" -- bash -c 'timeout 3 bash -c "exec 3<>/dev/tcp/$0/$1" 2>/dev/null && echo open ||
  { r=$?; [ $r = 124 ] && echo "blocked (timeout)" || echo "blocked (rejected, rc=$r)"; }' "$3" "$4"; }
CA=/etc/pg-ca/ca.crt

section "Setup"
# Recreate the client so it carries the L6 additions (CA certificate, app_ro password).
kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=true >/dev/null; client_up
L=$(leader); LIP=$(pod_ip "$L"); SYNC=$(sync_standby); GIP=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=garage -o jsonpath='{.items[0].status.podIP}')
REPLICAS=$(patroni_cluster | jq -r '.members[] | select(.role != "leader") | .name' | tr '\n' ' ')
run "patroni_cluster | jq -r '.members[] | \"\(.name) role=\(.role) state=\(.state) timeline=\(.timeline)\"'"
note "Leader \`$L\` ($LIP), sync standby \`$SYNC\`, Garage pod $GIP."

section "T:tls and T:db-authz: pg_hba, TLS and SCRAM (R8.4, R8.5)"
note "The rendered rules come from the pg-patroni ConfigMap that the members run with. First match wins."
CM=$(kubectl -n "$NS" get sts pg -o jsonpath='{.spec.template.spec.volumes[?(@.name=="patroni-config")].configMap.name}')
try "kubectl -n $NS get cm $CM -o jsonpath='{.data.10-base\.yml}' | sed -n '/^  pg_hba:/,/^[^ ]/p' | grep -E '^ +- '"
check "pg_hba: every rule for the pod network is hostssl + scram-sha-256" none_but '10\.42\.0\.0/16' '- hostssl .* scram-sha-256'
check "pg_hba: remote superuser rejected first (hostssl all postgres 0.0.0.0/0 reject)" ok_out 'hostssl all postgres 0\.0\.0\.0/0 reject' 
check "pg_hba: non-TLS remote connections end in an explicit reject (host all all 0.0.0.0/0 reject)" ok_out 'host all all 0\.0\.0\.0/0 reject'
try "cx app 'host=$RW user=app dbname=app sslmode=verify-full sslrootcert=$CA' \"select 'ssl=' || ssl || ' ' || version || ' ' || cipher from pg_stat_ssl where pid = pg_backend_pid()\""
check "Client through pg-rw with sslmode=verify-full (CA + hostname verified): TLS in use" ok_out '^ssl=true TLSv1\.[23]'
try "cx app 'host=$RO user=app dbname=app sslmode=verify-full sslrootcert=$CA' \"select 'ssl=' || ssl || ' ' || version from pg_stat_ssl where pid = pg_backend_pid()\""
check "Client through pg-ro with sslmode=verify-full: TLS in use" ok_out '^ssl=true TLSv1\.[23]'
try "cx app 'host=$RW user=app dbname=app sslmode=disable' 'select 1'"
check "Non-TLS connection (sslmode=disable) refused by pg_hba (expected failure)" refused 'pg_hba\.conf rejects connection.*no encryption'
try "cx wrong 'host=$RW user=app dbname=app sslmode=require' 'select 1'"
check "Wrong password refused (expected failure)" refused 'password authentication failed for user "app"'
try "cx none 'host=$RW user=postgres dbname=postgres sslmode=require' 'select 1'"
check "Remote superuser login refused before any password exchange (expected failure)" refused 'pg_hba\.conf rejects connection.*user "postgres"'
try "cx app 'host=$RW user=app dbname=app sslmode=require replication=true' 'IDENTIFY_SYSTEM'"
check "App role: physical replication connection rejected by pg_hba (expected failure)" refused 'pg_hba\.conf rejects replication connection.*user "app"|no pg_hba\.conf entry for replication connection.*user "app"'
try "cx app 'host=$RW user=app dbname=app sslmode=require replication=database' 'IDENTIFY_SYSTEM'"
check "App role: logical replication connection refused, no REPLICATION attribute (expected failure)" refused 'permission denied to start WAL sender'
try "cx monitor 'host=$RW user=monitor dbname=postgres sslmode=require' \"select 'password_encryption=' || current_setting('password_encryption') || ' ssl=' || current_setting('ssl') || ' ssl_min_protocol_version=' || current_setting('ssl_min_protocol_version')\""
check "password_encryption is scram-sha-256, ssl on" ok_out 'password_encryption=scram-sha-256 ssl=on'
note "Replication streams, as seen on the primary (pg_stat_replication joined with pg_stat_ssl):"
try "cx monitor 'host=$RW user=monitor dbname=postgres sslmode=require' \"select r.application_name, r.state, r.sync_state, 'ssl=' || s.ssl, s.version from pg_stat_replication r join pg_stat_ssl s using (pid) order by 1\""
check "Both replication streams use TLS" count_is ' streaming .*ssl=true TLSv1\.[23]' 2
for m in $REPLICAS; do
  try "cx monitor 'host=$(member "$m") user=monitor dbname=postgres sslmode=require' \"select status, regexp_replace(conninfo, 'password=[^ ]*', 'password=********') from pg_stat_wal_receiver\""
  check "Replica $m streams with sslmode=verify-full and the L0 CA (pg_stat_wal_receiver.conninfo)" \
    ok_out '^streaming .*sslmode=verify-full.*sslrootcert=/etc/pg-tls/ca\.crt|^streaming .*sslrootcert=/etc/pg-tls/ca\.crt.*sslmode=verify-full'
done

section "T:db-authz: separate roles with least privilege (R8.5)"
try "cx monitor 'host=$RW user=monitor dbname=postgres sslmode=require' \"select r.rolname, 'super=' || r.rolsuper, 'repl=' || r.rolreplication, 'createrole=' || r.rolcreaterole, 'createdb=' || r.rolcreatedb, 'bypassrls=' || r.rolbypassrls, 'member_of=' || coalesce((select string_agg(b.rolname, ',' order by b.rolname) from pg_auth_members m join pg_roles b on b.oid = m.roleid where m.member = r.oid), '-') from pg_roles r where r.rolcanlogin order by 1\""
ROLES=$OUT
role_is() { grep -qE "^$1 $2\$" <<<"$ROLES"; }
check "Only postgres is a superuser among login roles" bash -c '[ "$(grep -c "super=true" <<<"$1")" = 1 ] && grep -q "^postgres super=true" <<<"$1"' _ "$ROLES"
check "replicator: replication only, no superuser, no other grants" role_is replicator 'super=false repl=true createrole=false createdb=false bypassrls=false member_of=-'
check "app: no superuser, replication, createrole, createdb or bypassrls, no role memberships" role_is app 'super=false repl=false createrole=false createdb=false bypassrls=false member_of=-'
check "app_ro: only pg_read_all_data" role_is app_ro 'super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_read_all_data'
check "monitor: only pg_monitor" role_is monitor 'super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_monitor'
check "backup: only pg_checkpoint and pg_read_all_settings" role_is backup 'super=false repl=false createrole=false createdb=false bypassrls=false member_of=pg_checkpoint,pg_read_all_settings'
check "rewind: no superuser, replication, createrole, createdb or bypassrls" bash -c 'grep -qE "^rewind super=false repl=false createrole=false createdb=false bypassrls=false " <<<"$1"' _ "$ROLES"
try "cx app_ro 'host=$RW user=app_ro dbname=app sslmode=require' 'create table l6_should_not_exist (i int)'"
check "app_ro cannot create a table (expected failure)" refused 'permission denied for schema public'
try "cx app_ro 'host=$RW user=app_ro dbname=app sslmode=require' 'select count(*) from pgbench_accounts'"
check "app_ro can read application data" ok_out '^[0-9]+$'
try "cx monitor 'host=$RW user=monitor dbname=app sslmode=require' 'create table l6_should_not_exist (i int)'"
check "monitor cannot create a table (expected failure)" refused 'permission denied for schema public'
try "cx app 'host=$RW user=app dbname=app sslmode=require' 'create role l6_should_not_exist'"
check "app cannot create roles (expected failure)" refused 'permission denied to create role'

section "T:netpol: NetworkPolicy, default deny with explicit allows (R8.6)"
run "kubectl get networkpolicy -A"
note "A throwaway namespace \`$OUT_NS\` with one pod, \`outsider\`, made to look like an insider: it carries both \`app.kubernetes.io/name=pg\` and \`pg-ha/db-client=true\`. Labels in another namespace grant nothing, because every allow names pg-ha pods or a labelled namespace. Probes go to pod IPs and to Service names. kube-router (the k3s policy controller) rejects a denied connection at once, so a block shows as *rejected*. That each port really listens is shown by the allowed paths: the test client reaches the same leader IP on 5432, the API proxy and Prometheus reach 8008 and 9187, the backup Job reaches 8432, the members reach Garage 3900 (archiving) and the bootstrap Job reaches 3903."
kubectl delete ns "$OUT_NS" --ignore-not-found --wait=true >/dev/null
kubectl create ns "$OUT_NS" >/dev/null
sed "s|__PG_IMAGE__|$PG_IMAGE|" <<'YAML' | kubectl -n "$OUT_NS" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: outsider, labels: {app.kubernetes.io/name: pg, pg-ha/db-client: "true"}}
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: c
    image: __PG_IMAGE__
    imagePullPolicy: IfNotPresent
    command: [sleep, "1800"]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
YAML
kubectl -n "$OUT_NS" wait --for=condition=Ready pod/outsider --timeout=90s >/dev/null || die "outsider pod not ready"
DNS_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
MATRIX=$(mktemp -p "$W")
probe() { # src-ns src-pod label host port expect(open|blocked)
  local got; got=$(tcp "$1" "$2" "$4" "$5" 2>&1 | tail -1)
  printf '| %s | %s:%s | %s | %s |\n' "$3" "$4" "$5" "$6" "$got" >> "$MATRIX"
  case "$6:$got" in open:open|blocked:blocked*) return 0 ;; *) return 1 ;; esac
}
check "Control: outsider has a working network (kube-dns $DNS_IP:53 open)" probe "$OUT_NS" outsider "outsider" "$DNS_IP" 53 open
check "outsider -> Postgres 5432 on the leader pod blocked" probe "$OUT_NS" outsider "outsider" "$LIP" 5432 blocked
check "outsider -> Postgres via pg-rw Service blocked" probe "$OUT_NS" outsider "outsider" "$RW" 5432 blocked
check "outsider -> Patroni REST API 8008 blocked" probe "$OUT_NS" outsider "outsider" "$LIP" 8008 blocked
check "outsider -> pgBackRest TLS 8432 blocked" probe "$OUT_NS" outsider "outsider" "$LIP" 8432 blocked
check "outsider -> postgres_exporter 9187 blocked" probe "$OUT_NS" outsider "outsider" "$LIP" 9187 blocked
check "outsider -> Garage S3 3900 blocked" probe "$OUT_NS" outsider "outsider" "garage.$NS.svc.cluster.local" 3900 blocked
check "outsider -> Garage admin 3903 blocked" probe "$OUT_NS" outsider "outsider" "$GIP" 3903 blocked
check "outsider -> Prometheus 9090 blocked" probe "$OUT_NS" outsider "outsider" "prometheus.monitoring.svc.cluster.local" 9090 blocked
check "test client (db client) -> Postgres via pg-rw open" probe "$NS" "$CLIENT" "test client (pg-ha, db-client)" "$RW" 5432 open
check "test client -> Patroni 8008 blocked (clients get 5432 only)" probe "$NS" "$CLIENT" "test client (pg-ha, db-client)" "$LIP" 8008 blocked
check "test client -> pgBackRest TLS 8432 blocked" probe "$NS" "$CLIENT" "test client (pg-ha, db-client)" "$LIP" 8432 blocked
check "test client -> Garage S3 3900 blocked" probe "$NS" "$CLIENT" "test client (pg-ha, db-client)" "$GIP" 3900 blocked
check "test client -> API server blocked (no API egress for clients)" probe "$NS" "$CLIENT" "test client (pg-ha, db-client)" "kubernetes.default.svc.cluster.local" 443 blocked
{ printf '\n| Source | Destination | Expected | Got |\n|---|---|---|---|\n'; cat "$MATRIX"; } >> "$BODY"

note "Allowed paths still work under the policies:"
try "patroni_cluster | jq -r '.members[] | \"\(.name) \(.role) \(.state)\"'"
check "API server pod proxy -> Patroni GET /cluster (make status, patroni_cluster) works" ok_out 'leader running'
try "lock; echo; date -u +%FT%TZ"
renewed() { local r; r=$(lock | awk '{print $2}'); [ -n "$r" ] && [ $(( $(date +%s) - $(date -d "$r" +%s) )) -le 10 ]; }
check "Patroni -> API server (DCS): leader lock renewed within the last 10 s" renewed
TG=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/targets?state=active")
try "jq -r '.data.activeTargets[] | \"\(.labels.job) \(.labels.instance) \(.health) lastScrape=\(.lastScrape)\"' <<<'$TG' | sort"
check "Prometheus (via the API proxy) -> every target up: members 8008 and 9187, node_exporter, kube-state-metrics, Alertmanager" \
  jq -e '([.data.activeTargets[] | select(.health != "up")] | length) == 0 and (.data.activeTargets | length) >= 13' <<<"$TG"
check "Prometheus -> API server: pod discovery found all 3 members" jq -e '[.data.activeTargets[] | select(.labels.job == "patroni")] | length == 3' <<<"$TG"
try "kubectl get --raw '/api/v1/namespaces/monitoring/services/alertmanager:9093/proxy/api/v2/status' | jq -r '.cluster.status, .versionInfo.version'"
check "API server service proxy -> Alertmanager works (make alerts)" ok_out 'disabled|ready'
try "JOB_WAIT=300 $ROOT_DIR/scripts/pgbr-job.sh pg-check-l6 'pgbackrest --stanza=main --log-level-console=info check && echo CHECK_OK' | grep -E 'check command end|CHECK_OK'"
check "Backup-template Job -> pgBackRest TLS 8432 on the members and Garage S3; primary -> Garage archive-push (pgbackrest check)" ok_out 'CHECK_OK'
try "cx app 'host=$RW user=app dbname=app sslmode=require' \"select 'dns+5432 ok from ' || host(inet_server_addr())\""
check "Client DNS and pg-rw 5432 work" ok_out "dns\\+5432 ok from $LIP"

section "Patroni REST API authentication"
note "Reached over \`kubectl port-forward\` to the leader, as the switchover harness does. The credential is read from \`./secrets\` and handed to curl on stdin, never on a command line. Every unauthenticated request is chosen to be harmless even if auth were missing: a switchover and a restart scheduled a day ahead, an empty config patch, and a reinitialize sent to the leader (which Patroni refuses anyway)."
PFPORT=$((19000 + RANDOM % 1000)); kubectl -n "$NS" port-forward "pod/$L" "$PFPORT:8008" >/dev/null 2>&1 & PF=$!
for _ in $(seq 1 20); do curl -s -o /dev/null "http://127.0.0.1:$PFPORT/liveness" && break; sleep 0.5; done
U="http://127.0.0.1:$PFPORT"; LATER=$(date -u -d '+1 day' +%FT%T+00:00)
rest() { # METHOD PATH AUTH(none|bad|good) [BODY] -> prints "HTTP <code> <body>"
  local m=$1 p=$2 a=$3 b=${4:-} code; local args=(-s -m 15 -o "$W/rb" -w '%{http_code}' -X "$m")   # separate local: set -u
  [ -z "$b" ] || args+=(-H 'Content-Type: application/json' --data-binary "$b")
  case "$a" in
    none) code=$(curl "${args[@]}" "$U$p") ;;
    bad)  code=$(printf 'user = "patroni:not-the-password"\n' | curl -K - "${args[@]}" "$U$p") ;;
    good) code=$(printf 'user = "patroni:%s"\n' "$(cat "$SECRETS_DIR/credentials/pg-restapi-password")" | curl -K - "${args[@]}" "$U$p") ;;
  esac; echo "HTTP $code $(head -c 200 "$W/rb" | tr '\n' ' ')"; }
try "rest GET /cluster none | cut -c1-60"; check "GET /cluster without credentials: 200 (status and helpers stay usable)" ok_out '^HTTP 200'
try "rest GET /readiness none | cut -c1-60"; check "GET /readiness without credentials: 200 (kubelet probe)" ok_out '^HTTP 200'
try "rest GET /metrics none | cut -c1-60"; check "GET /metrics without credentials: 200 (Prometheus)" ok_out '^HTTP 200'
try "rest POST /switchover none '{\"leader\": \"$L\", \"candidate\": \"$SYNC\", \"scheduled_at\": \"$LATER\"}'"
check "POST /switchover without credentials refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest POST /switchover bad '{\"leader\": \"$L\", \"candidate\": \"$SYNC\", \"scheduled_at\": \"$LATER\"}'"
check "POST /switchover with a wrong password refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest POST /restart none '{\"schedule\": \"$LATER\"}'"; check "POST /restart without credentials refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest POST /reinitialize none '{}'"; check "POST /reinitialize without credentials refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest PATCH /config none '{}'"; check "PATCH /config without credentials refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest DELETE /switchover none"; check "DELETE /switchover without credentials refused: 401 (expected failure)" ok_out '^HTTP 401'
try "rest POST /switchover good '{\"leader\": \"$L\", \"candidate\": \"$SYNC\", \"scheduled_at\": \"$LATER\"}'"
check "Authenticated POST /switchover accepted: 202, switchover scheduled for $LATER" ok_out '^HTTP 202 .*[Ss]cheduled'
try "rest DELETE /switchover good"
check "Authenticated DELETE /switchover accepted: the scheduled switchover is cancelled (200)" ok_out '^HTTP 200'
kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null || true; PF=
check "Leader unchanged after the REST API checks ($L)" test "$(leader)" = "$L"
note "A real authenticated switchover (with RTO) is run by \`make switchover\` (tests/failover.sh), evidence in \`L2/switchover.md\`."

section "T:pod-security: Pod Security restricted (R8.7)"
run "kubectl get ns $NS monitoring monitoring-host -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit"
try "kubectl label --dry-run=server --overwrite ns $NS pod-security.kubernetes.io/enforce=restricted 2>&1"
check "Every running pod in $NS passes restricted (server re-check gives no warning)" no_warning
try "kubectl label --dry-run=server --overwrite ns monitoring pod-security.kubernetes.io/enforce=restricted 2>&1"
check "Every running pod in monitoring passes restricted" no_warning
try "kubectl -n $NS run l6-privileged --image=$PG_IMAGE --restart=Never --dry-run=server --overrides='{\"spec\": {\"containers\": [{\"name\": \"l6-privileged\", \"image\": \"$PG_IMAGE\", \"securityContext\": {\"privileged\": true}}]}}'"
check "A privileged pod is rejected in $NS (expected failure)" refused 'violates PodSecurity "restricted:v1\.35".*privileged'
try "kubectl -n $NS run l6-root --image=$PG_IMAGE --restart=Never --dry-run=server"
check "A pod without a restricted securityContext (root, escalation allowed) is rejected (expected failure)" refused 'violates PodSecurity "restricted:v1\.35"'
try "kubectl -n $NS run l6-compliant --image=$PG_IMAGE --restart=Never --dry-run=server --overrides='{\"spec\": {\"securityContext\": {\"runAsNonRoot\": true, \"runAsUser\": 999, \"seccompProfile\": {\"type\": \"RuntimeDefault\"}}, \"containers\": [{\"name\": \"l6-compliant\", \"image\": \"$PG_IMAGE\", \"securityContext\": {\"allowPrivilegeEscalation\": false, \"capabilities\": {\"drop\": [\"ALL\"]}}}]}}'"
check "Control: a restricted-compliant pod is admitted (server dry run)" ok_out 'created \(server dry run\)'
note "Security context of every container running in $NS and monitoring:"
try "kubectl get pods -n $NS -o json | jq -r '.items[] | .metadata.name as \$p | .spec.securityContext as \$s | .spec.containers[] | \"\(\$p)/\(.name) nonRoot=\(\$s.runAsNonRoot) uid=\(\$s.runAsUser) seccomp=\(\$s.seccompProfile.type) escalation=\(.securityContext.allowPrivilegeEscalation) drop=\(.securityContext.capabilities.drop | join(\",\")) roRootFS=\(.securityContext.readOnlyRootFilesystem) privileged=\(.securityContext.privileged // false)\"'"
check "Every container in $NS: non-root, no escalation, ALL capabilities dropped, read-only root, RuntimeDefault seccomp" \
  all_match 'nonRoot=true uid=[1-9][0-9]* seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true privileged=false'
try "kubectl get pods -n monitoring -o json | jq -r '.items[] | .metadata.name as \$p | .spec.securityContext as \$s | .spec.containers[] | \"\(\$p)/\(.name) nonRoot=\(\$s.runAsNonRoot) seccomp=\(\$s.seccompProfile.type) escalation=\(.securityContext.allowPrivilegeEscalation) drop=\(.securityContext.capabilities.drop | join(\",\")) roRootFS=\(.securityContext.readOnlyRootFilesystem)\"'"
check "Every container in monitoring: non-root, no escalation, ALL dropped, read-only root, RuntimeDefault seccomp" \
  all_match 'nonRoot=true seccomp=RuntimeDefault escalation=false drop=ALL roRootFS=true'

section "T:rbac: ServiceAccounts and kubectl auth can-i (R8.8)"
run "kubectl get sa -n $NS; kubectl get sa -n monitoring; kubectl get sa -n monitoring-host"
run "kubectl get roles,rolebindings -n $NS -o wide; kubectl get roles,rolebindings -n monitoring-host -o wide; kubectl get roles,rolebindings -n kube-system -o wide | grep -E '^NAME|kube-state-metrics'"
try "kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; (.namespace // \"\") as \$n | \$n == \"$NS\" or \$n == \"monitoring\" or \$n == \"monitoring-host\")) | .metadata.name' | sed 's/^/clusterrolebinding: /'; echo end"
check "No ClusterRoleBinding names a ServiceAccount from $NS, monitoring or monitoring-host" count_is '^clusterrolebinding:' 0
for sa in pg-ha:pg monitoring:prometheus monitoring:kube-state-metrics; do
  run "kubectl auth can-i --list -n ${sa%%:*} --as=system:serviceaccount:$sa | grep -vE 'selfsubject|/api|/openapi|/version|/healthz|/livez|/readyz|\\[\\]\\s+\\[\\]\\s+\\[get\\]'" || true
done
RB=$(mktemp -p "$W")
cani() { # expect(yes|no) sa verb resource namespace(-A for cluster)
  local nsarg="-n $5" got; [ "$5" = - ] && nsarg=
  got=$(kubectl auth can-i "$3" "$4" $nsarg --as="system:serviceaccount:$2" 2>/dev/null || true)
  printf '| %s | %s %s | %s | %s | %s |\n' "$2" "$3" "$4" "$(where "$5")" "$1" "${got:-no}" >> "$RB"
  [ "${got:-no}" = "$1" ]
}
P=pg-ha:pg
for c in "yes get endpoints $NS" "yes patch endpoints $NS" "yes patch pods $NS" "yes create services $NS" \
         "no get secrets $NS" "no list secrets $NS" "no create pods $NS" "no delete pods $NS" "no create pods/exec $NS" \
         "no create pods/portforward $NS" "no update services $NS" "no delete statefulsets $NS" "no get configmaps $NS" \
         "no create rolebindings $NS" "no list pods kube-system" "no get endpoints default" "no get nodes -" "no list namespaces -"; do
  set -- $c; check "can-i $P: $2 $3 in $(where "$4") -> $1" cani "$1" "$P" "$2" "$3" "$4"
done
for c in "yes list pods $NS" "yes watch pods monitoring-host" "no get secrets $NS" "no list pods default" "no list pods kube-system" "no create pods monitoring" "no get nodes -"; do
  set -- $c; check "can-i monitoring:prometheus: $2 $3 in $(where "$4") -> $1" cani "$1" monitoring:prometheus "$2" "$3" "$4"
done
for c in "yes list jobs $NS" "yes watch cronjobs kube-system" "no get secrets $NS" "no list pods $NS" "no list jobs default" "no get nodes -"; do
  set -- $c; check "can-i monitoring:kube-state-metrics: $2 $3 in $(where "$4") -> $1" cani "$1" monitoring:kube-state-metrics "$2" "$3" "$4"
done
for c in "no list pods $NS" "no get secrets $NS"; do
  set -- $c; check "can-i $NS:default: $2 $3 in $(where "$4") -> $1" cani "$1" "$NS:default" "$2" "$3" "$4"
done
{ printf '\n| ServiceAccount | Verb and resource | Namespace | Expected | Got |\n|---|---|---|---|---|\n'; cat "$RB"; } >> "$BODY"

section "Credentials stay out of git (R8.2)"
note "Every current credential value in \`./secrets/credentials\` is searched for in the full history of every branch (\`git log -p --all\`) and in the tracked working tree. Values are compared inside this script and never printed."
HIST=$(mktemp -p "$W"); git -C "$ROOT_DIR" log -p --all > "$HIST"
hits=0; n=0; for f in "$SECRETS_DIR"/credentials/*; do v=$(cat "$f"); [ -n "$v" ] || continue; n=$((n+1))
  if grep -qF -- "$v" "$HIST" || git -C "$ROOT_DIR" grep -qF -- "$v"; then hits=$((hits+1)); log "credential found in git: ${f##*/}"; fi; done
try "echo 'credential values checked: $n, found in git history or tracked files: $hits'; git -C '$ROOT_DIR' check-ignore -v secrets/credentials/pg-app-password secrets/tls/ca.key"
check "No credential value appears in the git history or the tracked tree ($n checked)" test "$hits" = 0
check "./secrets is ignored by git" ok_out 'secrets'
try "grep -cE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' '$HIST' || true"
check "No private key block appears anywhere in the git history" ok_out '^0$'

verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
{ printf '# L6: security baseline\n\n**Result: %s**\n\n' "$verdict"
  printf -- '- **What:** T:tls (R8.4), T:db-authz (R8.5), T:netpol (R8.6), T:pod-security (R8.7), T:rbac (R8.8), Patroni REST API authentication, and a credential scan of the full git history (R8.2). Expected refusals pass only when they fail for the expected reason.\n'
  printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make test-security`\n' "$STARTED" "$((SECONDS-T0))"
  printf -- '- **Versions:** k3s `%s`, image `%s`\n' "${K3S_IMAGE%@*}" "$PG_IMAGE"
  printf -- '- **Design:** [`../security.md`](../security.md). **History:** [`L6-security-history.md`](L6-security-history.md) (maintained by hand)\n'
  printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L6-security.md"
log "RESULT L6 security: $verdict ($FAILS failed) -> docs/evidence/L6-security.md"
[ "$FAILS" -eq 0 ]
