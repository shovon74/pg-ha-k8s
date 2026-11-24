#!/usr/bin/env bash
# Shared helpers for tests. Sources the spike evidence helpers (redact, run, check, note, section).
#
# kubectl exec (D4): tests run psql only inside their own client pod, pg-test-client, never in a
# Postgres pod. Fault scripts may use docker exec on a k3d node, and each use is documented where it runs.
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/spikes/lib.sh"
NS=$PG_NS; CLIENT=pg-test-client
BODY=$(mktemp); CHECKS=$(mktemp); FAILS=0; T0=$SECONDS; STARTED=$(date -u +%FT%TZ)
RW=pg-rw.$NS.svc.cluster.local; RO=pg-ro.$NS.svc.cluster.local
member() { echo "$1.pg-headless.$NS.svc.cluster.local"; }
now() { date +%s.%N; }
iso() { date -u -d "@$1" +%H:%M:%S.%3N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN{ if (a == "" || b == "") print "n/a"; else printf "%.2f", b - a }'; }

# q HOST USER SQL: one psql call from the client pod. The password is chosen inside the pod from its env.
q() {
  kubectl -n "$NS" exec "$CLIENT" -- sh -c '
    case "$2" in app) PGPASSWORD=$APP_PW ;; monitor) PGPASSWORD=$MON_PW ;; *) exit 2 ;; esac; export PGPASSWORD
    exec psql "host=$1 user=$2 dbname=app connect_timeout=3" -XAtq -v ON_ERROR_STOP=1 -F " " -c "$3"' sh "$1" "$2" "$3"
}
export -f q; export NS CLIENT

client_up() {
  kubectl -n "$NS" get pod "$CLIENT" >/dev/null 2>&1 && kubectl -n "$NS" wait --for=condition=Ready "pod/$CLIENT" --timeout=5s >/dev/null 2>&1 && return 0
  kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=true >/dev/null
  sed "s|__PG_IMAGE__|$PG_IMAGE|" <<'YAML' | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: pg-test-client, labels: {app.kubernetes.io/name: pg-test-client}}
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  nodeSelector: {pg-ha/role: infra}     # on the server node, so agent faults never take the observer down
  tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
  securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: client
    image: __PG_IMAGE__
    imagePullPolicy: IfNotPresent
    command: [sleep, "7200"]
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
  kubectl -n "$NS" wait --for=condition=Ready "pod/$CLIENT" --timeout=90s >/dev/null || die "client pod not ready"
}

# Lock holder and renew time, read from the pg-rw Endpoints object that Patroni uses as its leader lock.
lock() { kubectl -n "$NS" get endpoints pg-rw -o jsonpath='{.metadata.annotations.leader} {.metadata.annotations.renewTime} {.metadata.annotations.acquireTime}' 2>/dev/null; }
leader() { lock | awk '{print $1}'; }
pod_ip() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.status.podIP}' 2>/dev/null; }
pod_node() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.spec.nodeName}' 2>/dev/null; }
sync_standby() { q "$RW" monitor "select application_name from pg_stat_replication where sync_state = 'sync'" 2>/dev/null; }

# Healthy as seen from the primary itself: 2 streaming standbys, exactly 1 sync, and Patroni agrees.
primary_confirms() { # [member that must be streaming]
  local r; r=$(q "$RW" monitor "select application_name, state, sync_state from pg_stat_replication" 2>/dev/null) || return 1
  [ "$(grep -c ' streaming ' <<<"$r")" = 2 ] && [ "$(grep -c ' sync$' <<<"$r")" = 1 ] || return 1
  [ -z "${1:-}" ] || grep -q "^$1 streaming " <<<"$r" || return 1
  patroni_healthy
}
