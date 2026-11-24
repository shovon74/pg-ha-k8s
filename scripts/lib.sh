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
