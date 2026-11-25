#!/usr/bin/env bash
# Deploys Garage (ADR-014) into pg-ha and bootstraps it through the Admin API from a Job. Idempotent,
# and never prints a secret. Creates the Secrets garage and pgbackrest-repo from ./secrets.
. "$(dirname "$0")/lib.sh"
cluster_exists || die "cluster $CLUSTER_NAME not found, run: make cluster"
C="$SECRETS_DIR/credentials"
for f in garage-rpc-secret garage-admin-token garage-metrics-token garage-s3-access-key-id garage-s3-secret-key pgbackrest-cipher-passphrase; do
  [ -s "$C/$f" ] || die "missing $C/$f, run: make secrets"
done
kubectl apply -f "$ROOT_DIR/deploy/pg/namespace.yaml" >/dev/null
secret() { kubectl -n "$PG_NS" create secret generic "$@" --dry-run=client -o yaml |
  kubectl apply --server-side --field-manager=pg-ha-deploy --force-conflicts -f - >/dev/null; }
secret garage --from-file=GARAGE_RPC_SECRET="$C/garage-rpc-secret" \
  --from-file=GARAGE_ADMIN_TOKEN="$C/garage-admin-token" --from-file=GARAGE_METRICS_TOKEN="$C/garage-metrics-token"
# pgBackRest reads these as environment variables, so no credential is ever written to repo.conf (ADR-009).
secret pgbackrest-repo --from-file=PGBACKREST_REPO1_S3_KEY="$C/garage-s3-access-key-id" \
  --from-file=PGBACKREST_REPO1_S3_KEY_SECRET="$C/garage-s3-secret-key" \
  --from-file=PGBACKREST_REPO1_CIPHER_PASS="$C/pgbackrest-cipher-passphrase"

# Jobs are immutable, so the bootstrap Job is replaced on every deploy. It is idempotent.
kubectl -n "$PG_NS" delete job garage-bootstrap --ignore-not-found --wait=true >/dev/null
sed "s|__GARAGE_IMAGE__|$GARAGE_IMAGE|; s|__CURL_IMAGE__|$CURL_IMAGE|" "$ROOT_DIR/deploy/garage/garage.yaml" |
  kubectl -n "$PG_NS" apply -f -
kubectl -n "$PG_NS" rollout status deploy/garage --timeout=180s
kubectl -n "$PG_NS" wait --for=condition=Complete job/garage-bootstrap --timeout=180s >/dev/null ||
  { kubectl -n "$PG_NS" logs job/garage-bootstrap --tail=20 || true; die "garage-bootstrap did not complete"; }
kubectl -n "$PG_NS" logs job/garage-bootstrap
