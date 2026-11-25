#!/usr/bin/env bash
# Deploys Garage (L3), the Patroni cluster (L1) with WAL archiving (L3), and creates the pgBackRest stanza.
# Waits until healthy. Idempotent, and never prints a secret.
. "$(dirname "$0")/lib.sh"
cluster_exists || die "cluster $CLUSTER_NAME not found, run: make cluster"
C="$SECRETS_DIR/credentials"; T="$SECRETS_DIR/tls"
for f in "$C"/pg-{postgres,replicator,rewind,monitor,backup,app,app_ro}-password \
         "$T"/{ca.crt,postgres-server.crt,postgres-server.key,pgbackrest-server.crt,pgbackrest-server.key,pgbackrest-client.crt,pgbackrest-client.key}; do
  [ -s "$f" ] || die "missing $f, run: make certs secrets"
done
BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-0 20 * * *}   # ADR-009: daily at 20:00 UTC unless overridden
[[ "$BACKUP_SCHEDULE" =~ ^[0-9*/,-]+( [0-9*/,-]+){4}$ ]] || die "BACKUP_SCHEDULE must be a 5-field cron expression"
RESTORE_TEST_SCHEDULE=${RESTORE_TEST_SCHEDULE:-0 21 * * *}   # ADR-010: daily, after the backup
[[ "$RESTORE_TEST_SCHEDULE" =~ ^[0-9*/,-]+( [0-9*/,-]+){4}$ ]] || die "RESTORE_TEST_SCHEDULE must be a 5-field cron expression"

# ADR-001: cluster DNS is infrastructure, so it runs on the server node with Garage, never on a database
# node. k3s schedules its single CoreDNS replica anywhere. When that was the primary's node, a node failure
# took DNS down with it, and the promoted standby sat in restore_command (archive-get resolving Garage) until
# DNS returned (L3, docs/evidence/L3-backup-history.md). k3s re-applies its addon manifest with a three-way
# merge, which keeps this added nodeSelector key.
kubectl -n kube-system patch deployment coredns --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"pg-ha/role":"infra"}}}}}' >/dev/null
kubectl -n kube-system rollout status deployment/coredns --timeout=120s >/dev/null

# L3: Garage first, so WAL archiving has somewhere to go as soon as Postgres starts (ADR-014).
"$ROOT_DIR/scripts/garage.sh"

kubectl apply -f "$ROOT_DIR/deploy/pg/namespace.yaml" >/dev/null
# Server-side apply keeps secret values out of the last-applied annotation.
secret() { kubectl -n "$PG_NS" create secret generic "$@" --dry-run=client -o yaml |
  kubectl apply --server-side --field-manager=pg-ha-deploy --force-conflicts -f - >/dev/null; }
secret pg-credentials $(for r in postgres replicator rewind monitor backup app app_ro; do printf -- '--from-file=%s ' "$C/pg-$r-password"; done)
secret pg-tls --from-file=tls.crt="$T/postgres-server.crt" --from-file=tls.key="$T/postgres-server.key" --from-file=ca.crt="$T/ca.crt"
secret pgbackrest-tls --from-file=server.crt="$T/pgbackrest-server.crt" --from-file=server.key="$T/pgbackrest-server.key" \
  --from-file=client.crt="$T/pgbackrest-client.crt" --from-file=client.key="$T/pgbackrest-client.key" --from-file=ca.crt="$T/ca.crt"
kubectl kustomize "$ROOT_DIR/deploy/pg" | sed "s|__PG_IMAGE__|$PG_IMAGE|; s|__BACKUP_SCHEDULE__|'$BACKUP_SCHEDULE'|; s|__RESTORE_TEST_SCHEDULE__|'$RESTORE_TEST_SCHEDULE'|" | kubectl apply -f -

kubectl -n "$PG_NS" rollout status "statefulset/$PG_STS" --timeout=600s
end=$((SECONDS + ${PG_WAIT:-180}))
until patroni_healthy; do
  [ $SECONDS -lt $end ] || { patroni_cluster | jq -r '.members[] | "\(.name) \(.role) \(.state)"' || true; die "Patroni not healthy after ${PG_WAIT:-180} s"; }
  sleep 2
done
log "Patroni healthy: 1 leader, 2 streaming replicas, 1 sync standby"

# L3: create the stanza (idempotent), then prove that archiving reaches the repository.
out=$(JOB_WAIT=300 "$ROOT_DIR/scripts/pgbr-job.sh" pg-stanza-create \
  'pgbackrest --stanza=main --log-level-console=info stanza-create && pgbackrest --stanza=main --log-level-console=info check && echo STANZA_OK') ||
  { printf '%s\n' "$out" | tail -20; die "stanza-create or check failed"; }
printf '%s\n' "$out" | grep -E 'stanza-create command end|check command end|already exists|STANZA_OK' || true
log "Backup schedule: $BACKUP_SCHEDULE (UTC), restore test: $RESTORE_TEST_SCHEDULE (UTC)"
