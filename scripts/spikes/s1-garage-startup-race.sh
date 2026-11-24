#!/usr/bin/env bash
# Diagnostic for the S1 136 s hang: times connections to Garage's admin port during first startup.
# Not part of `make spikes`, and writes no evidence file. See docs/evidence/L0-spike-S1-history.md.
#
# Usage: [MODE=unbounded|bounded] [TRIALS=3] [ATTEMPTS=60] [INTERVAL=0.5] [OUT=dir] scripts/spikes/s1-garage-startup-race.sh
#   unbounded  ATTEMPTS curls, one every INTERVAL seconds, with no connect timeout (about 3 min per trial)
#   bounded    one curl with the bootstrap Job's timeout and retry options (under 1 min per trial)
#
# Each trial uses its own namespace, which is always deleted. Tokens are random, used once and never
# printed. Saved output is masked. Uses no kubectl exec and no project credentials.
. "$(dirname "$0")/lib.sh"

MODE=${MODE:-unbounded}; TRIALS=${TRIALS:-3}; ATTEMPTS=${ATTEMPTS:-60}; INTERVAL=${INTERVAL:-0.5}
OUT=${OUT:-$RUN_DIR/s1-garage-startup-race}
case "$MODE" in unbounded|bounded) ;; *) die "MODE must be unbounded or bounded" ;; esac
[[ "$TRIALS" =~ ^[1-9][0-9]*$ ]] || die "TRIALS must be a positive integer"
[[ "$ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || die "ATTEMPTS must be a positive integer"
[[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "INTERVAL must be a number of seconds"

PREFIX="s1-race-$$"; CURRENT_NS=""; TOKENS=""
cleanup() {
  [ -z "$CURRENT_NS" ] || kubectl delete ns "$CURRENT_NS" --wait=true --timeout=120s >/dev/null 2>&1 || true
  [ -z "$TOKENS" ] || rm -rf "$TOKENS"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mask() { redact | sed -E 's/GK[0-9a-f]{24}/[MASKED:garage-key-id]/g; s/[0-9a-f]{32,}/[MASKED:hex]/g'; }

umask 077; mkdir -p "$OUT" "$RUN_DIR"; TOKENS=$(mktemp -d "$RUN_DIR/s1-race-tokens.XXXXXX")
for t in GARAGE_RPC_SECRET GARAGE_ADMIN_TOKEN GARAGE_METRICS_TOKEN; do openssl rand -hex 32 | tr -d '\n' > "$TOKENS/$t"; done

manifest() { sed "s|__GARAGE__|$GARAGE_IMAGE|; s|__CURL__|$CURL_IMAGE|; s|__NS__|$1|g; s|__MODE__|$MODE|; s|__ATTEMPTS__|$ATTEMPTS|; s|__INTERVAL__|$INTERVAL|" <<'YAML'
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
  resources: {requests: {storage: 1Gi}}
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
        image: __GARAGE__
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
metadata: {name: probe}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {pg-ha/role: infra}
      tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
      securityContext: {runAsNonRoot: true, runAsUser: 100, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: probe
        image: __CURL__
        imagePullPolicy: IfNotPresent
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
        env:
        - {name: MODE, value: "__MODE__"}
        - {name: ATTEMPTS, value: "__ATTEMPTS__"}
        - {name: INTERVAL, value: "__INTERVAL__"}
        # Unauthenticated, so Garage answers at once with a non-retryable 4xx once it is reachable.
        - {name: URL, value: "http://garage.__NS__.svc.cluster.local:3903/v2/GetClusterStatus"}
        command: [sh, -c]
        args:
        - |
          if [ "$MODE" = bounded ]; then
            t0=$(date +%s)
            r=$(curl -sS -o /dev/null --connect-timeout 3 --max-time 15 --retry 20 --retry-delay 1 --retry-all-errors -w 'http=%{http_code} retries=%{num_retries}' "$URL" 2>/dev/null); c=$?
            echo "BOUNDED exit=$c $r elapsed_s=$(( $(date +%s) - t0 ))"
          else
            i=0
            while [ "$i" -lt "$ATTEMPTS" ]; do
              ( s=$(date -u +%H:%M:%S)
                r=$(curl -sS -o /dev/null --max-time 200 -w '%{http_code} %{time_total}' "$URL" 2>/dev/null); c=$?
                echo "ATTEMPT start=$s exit=$c result=$r" ) &
              i=$((i+1)); sleep "$INTERVAL"
            done
            wait
          fi
          echo PROBE_DONE
YAML
}

if [ "$MODE" = bounded ]; then JOB_WAIT=120; else JOB_WAIT=$(awk -v a="$ATTEMPTS" -v i="$INTERVAL" 'BEGIN{printf "%d", a*i+230}'); fi
rc=0
for T in $(seq 1 "$TRIALS"); do
  NS="$PREFIX-$T"; f="$OUT/$MODE-trial-$T.txt"
  kubectl get ns "$NS" >/dev/null 2>&1 && die "namespace $NS already exists"
  kubectl create ns "$NS" >/dev/null; CURRENT_NS=$NS
  kubectl -n "$NS" create secret generic garage --from-file="$TOKENS" >/dev/null
  manifest "$NS" | kubectl -n "$NS" apply -f - >/dev/null
  kubectl -n "$NS" rollout status deploy/garage --timeout=120s >/dev/null 2>&1 || rc=1
  kubectl -n "$NS" wait --for=condition=complete job/probe --timeout="${JOB_WAIT}s" >/dev/null 2>&1 || rc=1
  {
    echo "trial=$T mode=$MODE"
    kubectl -n "$NS" get pod -l job-name=probe -o jsonpath='probe_start={.items[0].status.startTime} probe_node={.items[0].spec.nodeName}{"\n"}'
    kubectl -n "$NS" get pod -l app=garage -o jsonpath='garage_start={.items[0].status.containerStatuses[0].state.running.startedAt}{"\n"}garage_ready={.items[0].status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}'
    kubectl -n "$NS" logs job/probe | sort
  } 2>&1 | mask > "$f"
  if [ "$MODE" = bounded ]; then
    b=$(grep '^BOUNDED' "$f" || true); log "trial $T: ${b:-no result}"
    case "$b" in "BOUNDED exit=0 http=4"*) ;; *) rc=1 ;; esac
  else
    awk -v t="$T" '/^ATTEMPT/{split($3,e,"="); n[e[2]]++; if(e[2]==28){d=$NF+0; if(!mn||d<mn)mn=d; if(d>mx)mx=d}}
      END{for(k in n) if(k!=0&&k!=7&&k!=28) o+=n[k]; printf "trial %s: ok=%d refused=%d hung=%d hung_seconds=%.1f-%.1f other=%d\n", t, n[0], n[7], n[28], mn, mx, o}' "$f"
    grep -q PROBE_DONE "$f" || rc=1
  fi
  kubectl delete ns "$NS" --wait=true --timeout=120s >/dev/null; CURRENT_NS=""
done
log "Masked output: ${OUT#"$ROOT_DIR"/}"
exit $rc
