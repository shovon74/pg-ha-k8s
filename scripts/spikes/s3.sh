#!/usr/bin/env bash
# S3: can UID 999 create a 0700 PGDATA on a local-path volume, under Pod Security "restricted"?
. "$(dirname "$0")/lib.sh"
ev_start S3 "UID 999 and PGDATA on local-path" \
  "Can UID 999 create a 0700 PGDATA on a local-path volume?" \
  "With no init container, no fsGroup and Pod Security restricted, a UID 999 pod creates PGDATA as 0700, runs initdb and starts Postgres, and the data survives a new pod on the same PVC."

job() { # name; shell script on stdin
  local body; body=$(sed 's/^/          /')
  apply_yaml >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata: {name: $1}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {pg-ha/role: db}
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: t
        image: __IMAGE__
        imagePullPolicy: IfNotPresent
        command: [sh, -ec]
        args:
        - |
$body
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
        volumeMounts: [{name: d, mountPath: /data}]
      volumes:
      - name: d
        persistentVolumeClaim: {claimName: s3-data}
YAML
}

section "Setup: namespace with Pod Security restricted, and a local-path PVC"
run "kubectl create ns $NS && kubectl label ns $NS pod-security.kubernetes.io/enforce=restricted"
run "kubectl get storageclass"
apply_yaml >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: s3-data}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources: {requests: {storage: 1Gi}}
YAML

section "First pod: create PGDATA, initdb with checksums, start Postgres, write a row"
job s3-init <<'SH'
echo "uid=$(id -u) gid=$(id -g)"
echo "volume: $(stat -c '%a %u:%g' /data)"
mkdir -m 0700 /data/pgdata
echo "pgdata: $(stat -c '%a %u:%g' /data/pgdata)"
initdb -D /data/pgdata --data-checksums --auth-local=trust --auth-host=reject >/dev/null
echo "pgdata after initdb: $(stat -c '%a %u:%g' /data/pgdata)"
pg_ctl -D /data/pgdata -o "-c listen_addresses='' -c unix_socket_directories=/tmp" -w start >/dev/null
psql -h /tmp -U postgres -q -c "create table s3(v text)" -c "insert into s3 values ('survived')"
psql -h /tmp -U postgres -Atc "show data_checksums"
pg_ctl -D /data/pgdata -m fast -w stop >/dev/null
echo INIT_OK
SH
init_ok=0; wait_job s3-init 120 && init_ok=1
TAIL=12 run "kubectl -n $NS logs job/s3-init" || true
check "First pod completed under Pod Security restricted" test $init_ok = 1
logs=$(kubectl -n "$NS" logs job/s3-init 2>/dev/null || true)
check "PGDATA created with mode 0700 by UID 999" grep -q '^pgdata: 700 999:999' <<<"$logs"
check "initdb left PGDATA at 0700" grep -q '^pgdata after initdb: 700 999:999' <<<"$logs"
check "Data checksums enabled" grep -qx 'on' <<<"$logs"

section "Second pod on the same PVC: data survives"
job s3-reattach <<'SH'
pg_ctl -D /data/pgdata -o "-c listen_addresses='' -c unix_socket_directories=/tmp" -w start >/dev/null
psql -h /tmp -U postgres -Atc "select v from s3"
pg_ctl -D /data/pgdata -m fast -w stop >/dev/null
SH
re_ok=0; wait_job s3-reattach 90 && re_ok=1
run "kubectl -n $NS logs job/s3-reattach" || true
check "Second pod read the row from the same PVC" grep -qx survived <<<"$(kubectl -n "$NS" logs job/s3-reattach 2>/dev/null || true)"
check "Second pod completed" test $re_ok = 1
run "kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase; kubectl -n $NS get pvc" || true
ev_finish
