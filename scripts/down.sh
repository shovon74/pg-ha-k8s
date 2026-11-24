#!/usr/bin/env bash
# Deletes only this project's named cluster. ./secrets is preserved.
. "$(dirname "$0")/lib.sh"
[ -x "$BIN_DIR/k3d" ] || die "k3d not installed, run: make tools"
if cluster_exists; then k3d cluster delete "$CLUSTER_NAME"; else log "Cluster $CLUSTER_NAME does not exist, nothing to delete."; fi
rm -f "$KUBECONFIG"
log "./secrets preserved."
