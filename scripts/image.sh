#!/usr/bin/env bash
# Builds our Postgres image from pinned inputs and imports it into the k3d cluster.
. "$(dirname "$0")/lib.sh"
cluster_exists || die "cluster $CLUSTER_NAME not found, run: make cluster"
docker build --quiet -t "$PG_IMAGE" \
  --build-arg "POSTGRES_BASE_IMAGE=$POSTGRES_BASE_IMAGE" \
  --build-arg "PATRONI_DEB_VERSION=$PATRONI_DEB_VERSION" \
  --build-arg "PGBACKREST_DEB_VERSION=$PGBACKREST_DEB_VERSION" \
  "$ROOT_DIR/docker/postgres"
docker run --rm --entrypoint sh "$PG_IMAGE" -c 'id -u; postgres --version; patroni --version; pgbackrest version'
k3d image import --mode direct -c "$CLUSTER_NAME" "$PG_IMAGE"
log "Imported $PG_IMAGE"
