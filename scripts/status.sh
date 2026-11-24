#!/usr/bin/env bash
# Shows nodes and measured container resource use for this project's cluster only.
. "$(dirname "$0")/lib.sh"
cluster_exists || { log "Cluster $CLUSTER_NAME is not running."; exit 0; }
kubectl get nodes -o wide -L pg-ha/role
log ""
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
  $(docker ps -q --filter "label=k3d.cluster=$CLUSTER_NAME")
