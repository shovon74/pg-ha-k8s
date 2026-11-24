#!/usr/bin/env bash
# Creates the project's cluster if absent. Kubeconfig stays in ./.run.
. "$(dirname "$0")/lib.sh"
umask 077; mkdir -p "$RUN_DIR"
if cluster_exists; then log "OK    cluster $CLUSTER_NAME exists"
else k3d cluster create --config "$ROOT_DIR/deploy/k3d/cluster.yaml" --image "$K3S_IMAGE"; fi
k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG.tmp"; mv "$KUBECONFIG.tmp" "$KUBECONFIG"
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
kubectl get nodes -L pg-ha/role
