#!/usr/bin/env bash
# Deploys the Patroni cluster (L1) and waits until it is healthy. Idempotent, and never prints a secret.
. "$(dirname "$0")/lib.sh"
cluster_exists || die "cluster $CLUSTER_NAME not found, run: make cluster"
C="$SECRETS_DIR/credentials"; T="$SECRETS_DIR/tls"
for f in "$C"/pg-{postgres,replicator,rewind,monitor,backup,app,app_ro}-password "$T"/{ca.crt,postgres-server.crt,postgres-server.key}; do
  [ -s "$f" ] || die "missing $f, run: make certs secrets"
done

kubectl apply -f "$ROOT_DIR/deploy/pg/namespace.yaml" >/dev/null
# Server-side apply keeps secret values out of the last-applied annotation.
secret() { kubectl -n "$PG_NS" create secret generic "$@" --dry-run=client -o yaml |
  kubectl apply --server-side --field-manager=pg-ha-deploy --force-conflicts -f - >/dev/null; }
secret pg-credentials $(for r in postgres replicator rewind monitor backup app app_ro; do printf -- '--from-file=%s ' "$C/pg-$r-password"; done)
secret pg-tls --from-file=tls.crt="$T/postgres-server.crt" --from-file=tls.key="$T/postgres-server.key" --from-file=ca.crt="$T/ca.crt"
kubectl kustomize "$ROOT_DIR/deploy/pg" | sed "s|__PG_IMAGE__|$PG_IMAGE|" | kubectl apply -f -

kubectl -n "$PG_NS" rollout status "statefulset/$PG_STS" --timeout=300s
end=$((SECONDS + ${PG_WAIT:-180}))
until patroni_healthy; do
  [ $SECONDS -lt $end ] || { patroni_cluster | jq -r '.members[] | "\(.name) \(.role) \(.state)"' || true; die "Patroni not healthy after ${PG_WAIT:-180} s"; }
  sleep 2
done
log "Patroni healthy: 1 leader, 2 streaming replicas, 1 sync standby"
