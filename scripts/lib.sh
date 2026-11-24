#!/usr/bin/env bash
# Shared settings. Sourced by every project script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
# shellcheck disable=SC1091
. "$ROOT_DIR/versions.env"
set +a

CLUSTER_NAME=pg-ha
API_PORT=6550
BIN_DIR="$ROOT_DIR/bin"
SECRETS_DIR="$ROOT_DIR/secrets"
RUN_DIR="$ROOT_DIR/.run"
export KUBECONFIG="$RUN_DIR/kubeconfig"
export PATH="$BIN_DIR:$PATH"

# Image tag derived from the pinned inputs, so a version change produces a new tag.
pg_version="${POSTGRES_BASE_IMAGE#postgres:}"; pg_version="${pg_version%%-*}"
PG_IMAGE="pg-ha-postgres:${pg_version}-patroni${PATRONI_DEB_VERSION%%-*}-pgbackrest${PGBACKREST_DEB_VERSION%%-*}"

log()  { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cluster_exists() { k3d cluster list -o json | jq -e --arg n "$CLUSTER_NAME" 'any(.[]; .name == $n)' >/dev/null; }

# L1: Postgres cluster
PG_NS=pg-ha
PG_STS=pg
# Patroni's /cluster view, read through the API server's pod proxy, so no kubectl exec is needed (D4).
patroni_cluster() {
  local i out
  for i in 0 1 2; do
    out=$(kubectl get --raw "/api/v1/namespaces/$PG_NS/pods/$PG_STS-$i:8008/proxy/cluster" 2>/dev/null) && { printf '%s\n' "$out"; return 0; }
  done
  return 1
}
# Succeeds when Patroni reports 1 leader, 2 streaming replicas and 1 sync standby.
patroni_healthy() {
  patroni_cluster | jq -e '[.members[] | select(.role == "leader" and .state == "running")] | length == 1' >/dev/null &&
  patroni_cluster | jq -e '[.members[] | select(.role != "leader" and .state == "streaming")] | length == 2' >/dev/null &&
  patroni_cluster | jq -e '[.members[] | select(.role == "sync_standby")] | length == 1' >/dev/null
}
