#!/usr/bin/env bash
# S1: does pgBackRest complete stanza creation, backup, archive and restore against Garage?
. "$(dirname "$0")/lib.sh"
ev_start S1 "pgBackRest against Garage" \
  "Does pgBackRest complete stanza creation, backup, archive and restore against Garage?" \
  "Against Garage over plain HTTP with path-style URLs and aes-256-cbc repository encryption: stanza-create, check, full backup, WAL archiving, verify and restore all succeed. Restored rows, including rows only in archived WAL, match the source checksum, and a wrong passphrase cannot read the repository."
C="$SECRETS_DIR/credentials"
GARAGE_HOST="garage.$NS.svc.cluster.local"

section "Setup: Garage (single node, fsync on) on the tainted server"
run "kubectl create ns $NS"
kubectl -n "$NS" create secret generic garage \
  --from-file=GARAGE_RPC_SECRET="$C/garage-rpc-secret" \
  --from-file=GARAGE_ADMIN_TOKEN="$C/garage-admin-token" \
  --from-file=GARAGE_METRICS_TOKEN="$C/garage-metrics-token" >/dev/null
kubectl -n "$NS" create secret generic s3 \
  --from-file=ACCESS_KEY="$C/garage-s3-access-key-id" \
  --from-file=SECRET_KEY="$C/garage-s3-secret-key" \
  --from-file=CIPHER_PASS="$C/pgbackrest-cipher-passphrase" >/dev/null
sed "s|__GARAGE_IMAGE__|$GARAGE_IMAGE|; s|__CURL_IMAGE__|$CURL_IMAGE|; s|__GARAGE_HOST__|$GARAGE_HOST|g" <<'YAML' | apply_yaml >/dev/null
apiVersion: v1
kind: ConfigMap
metadata: {name: garage-config}
data:
  garage.toml: |
    metadata_dir = "/data/meta"
    data_dir = "/data/blocks"
    db_engine = "lmdb"
    replication_factor = 1
    metadata_fsync = true
    data_fsync = true
    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "127.0.0.1:3901"
    [s3_api]
    s3_region = "garage"
    api_bind_addr = "[::]:3900"
    [admin]
    api_bind_addr = "[::]:3903"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: garage-data}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources: {requests: {storage: 2Gi}}
---
apiVersion: v1
kind: Service
metadata: {name: garage}
spec:
  selector: {app: garage}
  ports:
  - {name: s3, port: 3900}
  - {name: admin, port: 3903}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: garage}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: garage}}
  template:
    metadata: {labels: {app: garage}}
    spec:
      nodeSelector: {pg-ha/role: infra}
      tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
      securityContext: {runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001, fsGroup: 10001, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: garage
        image: __GARAGE_IMAGE__
        imagePullPolicy: IfNotPresent
        envFrom: [{secretRef: {name: garage}}]
        securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
        readinessProbe: {tcpSocket: {port: 3903}, periodSeconds: 2}
        resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 256Mi}}
        volumeMounts:
        - {name: data, mountPath: /data}
        - {name: config, mountPath: /etc/garage.toml, subPath: garage.toml}
      volumes:
      - name: data
        persistentVolumeClaim: {claimName: garage-data}
      - name: config
        configMap: {name: garage-config}
---
apiVersion: batch/v1
kind: Job
metadata: {name: garage-bootstrap}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {pg-ha/role: infra}
      tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
      securityContext: {runAsNonRoot: true, runAsUser: 100, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: bootstrap
        image: __CURL_IMAGE__
        imagePullPolicy: IfNotPresent
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
        env:
        - {name: TOKEN, valueFrom: {secretKeyRef: {name: garage, key: GARAGE_ADMIN_TOKEN}}}
        - {name: ACCESS_KEY, valueFrom: {secretKeyRef: {name: s3, key: ACCESS_KEY}}}
        - {name: SECRET_KEY, valueFrom: {secretKeyRef: {name: s3, key: SECRET_KEY}}}
        command: [sh, -ec]
        args:
        - |
          A=http://__GARAGE_HOST__:3903/v2
          api() { curl -fsS --connect-timeout 3 --max-time 15 --retry 20 --retry-delay 1 --retry-all-errors -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }
          ID=$(api $A/GetClusterStatus | tr -d ' \n' | sed -E 's/.*"nodes":\[\{"id":"([0-9a-f]{64})".*/\1/')
          echo "node id length: ${#ID}"
          api -o /dev/null -X POST $A/UpdateClusterLayout -d "{\"roles\":[{\"id\":\"$ID\",\"zone\":\"local\",\"capacity\":2000000000,\"tags\":[]}]}"
          api -o /dev/null -X POST $A/ApplyClusterLayout -d '{"version":1}'
          echo LAYOUT_OK
          api -o /dev/null -X POST $A/ImportKey -d "{\"name\":\"pgbackrest\",\"accessKeyId\":\"$ACCESS_KEY\",\"secretAccessKey\":\"$SECRET_KEY\"}"
          echo KEY_OK
          B=$(api -X POST $A/CreateBucket -d '{"globalAlias":"pgbackrest"}' | tr -d ' \n' | sed -E 's/.*"id":"([0-9a-f]{64})".*/\1/')
          api -o /dev/null -X POST $A/AllowBucketKey -d "{\"bucketId\":\"$B\",\"accessKeyId\":\"$ACCESS_KEY\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":true}}"
          echo BUCKET_OK
YAML
g_ok=0; kubectl -n "$NS" rollout status deploy/garage --timeout=120s >/dev/null 2>&1 && g_ok=1
check "Garage is Ready on the tainted server" test $g_ok = 1
b_ok=0; wait_job garage-bootstrap 120 && b_ok=1
run "kubectl -n $NS logs job/garage-bootstrap" || true
check "Garage bootstrapped via Admin API from a Job (no kubectl exec)" test $b_ok = 1
run "kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase,IMAGE:.spec.containers[0].image" || true

section "pgBackRest end-to-end run in a UID 999 Job on a database node"
kubectl -n "$NS" create configmap s1-code --from-file=run.sh="$SPIKE_DIR/s1-inner.sh" >/dev/null
sed "s|__GARAGE_HOST__|$GARAGE_HOST|g" <<'YAML' | apply_yaml >/dev/null
apiVersion: v1
kind: ConfigMap
metadata: {name: pgbackrest-config}
data:
  pgbackrest.conf: |
    [global]
    log-path=/work/log
    lock-path=/work/lock
    spool-path=/work/spool
    archive-async=y
    process-max=2
    [s1]
    pg1-path=/work/pgdata
    pg1-socket-path=/tmp
  repo.conf: |
    [global]
    repo1-type=s3
    repo1-s3-endpoint=http://__GARAGE_HOST__:3900
    repo1-s3-bucket=pgbackrest
    repo1-s3-region=garage
    repo1-s3-uri-style=path
    repo1-path=/spike
    repo1-cipher-type=aes-256-cbc
    repo1-retention-full=7
---
apiVersion: batch/v1
kind: Job
metadata: {name: s1-run}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {pg-ha/role: db}
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, fsGroup: 999, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: run
        image: __IMAGE__
        imagePullPolicy: IfNotPresent
        command: [bash, /code/run.sh]
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
        env:
        - {name: PGBACKREST_REPO1_S3_KEY, valueFrom: {secretKeyRef: {name: s3, key: ACCESS_KEY}}}
        - {name: PGBACKREST_REPO1_S3_KEY_SECRET, valueFrom: {secretKeyRef: {name: s3, key: SECRET_KEY}}}
        - {name: PGBACKREST_REPO1_CIPHER_PASS, valueFrom: {secretKeyRef: {name: s3, key: CIPHER_PASS}}}
        volumeMounts:
        - {name: work, mountPath: /work}
        - {name: code, mountPath: /code}
        - {name: pgbr, mountPath: /etc/pgbackrest/pgbackrest.conf, subPath: pgbackrest.conf}
        - {name: pgbr, mountPath: /etc/pgbackrest/conf.d/repo.conf, subPath: repo.conf}
      volumes:
      - {name: work, emptyDir: {}}
      - {name: code, configMap: {name: s1-code}}
      - {name: pgbr, configMap: {name: pgbackrest-config}}
YAML
r_ok=0; wait_job s1-run 300 && r_ok=1
TAIL=70 run "kubectl -n $NS logs job/s1-run" || true
L=$(kubectl -n "$NS" logs job/s1-run 2>/dev/null || true)
for m in "STANZA_OK:stanza-create succeeded" "CHECK_OK:pgbackrest check succeeded" "BACKUP_OK:Full backup succeeded" \
         "ARCHIVE_OK:WAL segment archived to Garage" "VERIFY_OK:pgbackrest verify reports status ok" \
         "CIPHER_OK:Repository file is ciphertext, the right passphrase reads it and a wrong one cannot" "RESTORE_OK:Restore command succeeded" \
         "DATA_MATCH_OK:Restored rows and checksum match the source, including WAL-only rows" "AMCHECK_OK:pg_amcheck passed on restored data"; do
  check "${m#*:}" grep -qx "${m%%:*}" <<<"$L"
done
check "Spike Job completed" test $r_ok = 1
ev_finish
