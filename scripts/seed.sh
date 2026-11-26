#!/usr/bin/env bash
# Loads a synthetic pgbench dataset through pg-rw from an in-cluster Job (no kubectl exec, D4).
# SEED_SCALE=10 gives about 150 MB. Re-running drops and reloads the pgbench tables.
. "$(dirname "$0")/lib.sh"
SCALE=${SEED_SCALE:-10}
[[ "$SCALE" =~ ^[1-9][0-9]*$ ]] || die "SEED_SCALE must be a positive integer"
kubectl -n "$PG_NS" delete job pg-seed --ignore-not-found --wait=true >/dev/null
sed "s|__PG_IMAGE__|$PG_IMAGE|; s|__SCALE__|$SCALE|" <<'YAML' | kubectl -n "$PG_NS" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata: {name: pg-seed}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata: {labels: {app.kubernetes.io/name: pg-seed, pg-ha/db-client: "true"}}   # L6: NetworkPolicy client label
    spec:
      restartPolicy: Never
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: seed
        image: __PG_IMAGE__
        imagePullPolicy: IfNotPresent
        securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
        env:
        - {name: HOME, value: /tmp}
        - {name: PGHOST, value: pg-rw.pg-ha.svc.cluster.local}
        - {name: PGUSER, value: app}
        - {name: PGDATABASE, value: app}
        - {name: PGCONNECT_TIMEOUT, value: "5"}
        - name: PGPASSWORD
          valueFrom: {secretKeyRef: {name: pg-credentials, key: pg-app-password}}
        command: [sh, -ec]
        args:
        - |
          echo "seed: pgbench -i -s __SCALE__ through $PGHOST"
          pgbench -i -s __SCALE__ -q --no-vacuum
          psql -XAtqc "vacuum analyze pgbench_accounts, pgbench_branches, pgbench_tellers, pgbench_history"
          psql -XAtc "select 'server=' || inet_server_addr() || ' in_recovery=' || pg_is_in_recovery() || ' ssl=' || (select ssl from pg_stat_ssl where pid = pg_backend_pid())"
          psql -XAtc "select 'database_size=' || pg_size_pretty(pg_database_size('app')) || ' accounts=' || (select count(*) from pgbench_accounts)"
        volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {}}]
YAML
kubectl -n "$PG_NS" wait --for=condition=complete job/pg-seed --timeout="${SEED_TIMEOUT:-600}s" >/dev/null || {
  kubectl -n "$PG_NS" logs job/pg-seed --tail=20 || true; die "seed Job did not complete"; }
kubectl -n "$PG_NS" logs job/pg-seed | grep -vE '^[0-9]+ of [0-9]+ tuples'
