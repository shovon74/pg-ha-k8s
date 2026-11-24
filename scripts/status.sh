#!/usr/bin/env bash
# Shows nodes, resource use and, once deployed, Patroni members. Read-only, and uses no kubectl exec (D4).
. "$(dirname "$0")/lib.sh"
cluster_exists || { log "Cluster $CLUSTER_NAME is not running."; exit 0; }
kubectl get nodes -o wide -L pg-ha/role
log ""
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
  $(docker ps -q --filter "label=k3d.cluster=$CLUSTER_NAME")
kubectl get ns "$PG_NS" >/dev/null 2>&1 || exit 0
log ""
if J=$(patroni_cluster); then
  log "Patroni cluster $(jq -r '.scope // "pg-rw"' <<<"$J") (lag in bytes behind the leader, from Patroni's REST API)"
  { echo "MEMBER ROLE STATE TIMELINE LAG_BYTES NODE"
    for n in $(jq -r '.members[].name' <<<"$J"); do
      node=$(kubectl -n "$PG_NS" get pod "$n" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo -)
      jq -r --arg n "$n" --arg node "$node" '.members[] | select(.name == $n) |
        "\(.name) \(.role) \(.state) \(.timeline // "-") \(if .role == "leader" then "-" else (.lag // "?") end) \($node)"' <<<"$J"
    done; } | column -t
  log "Sync standby: $(jq -r '[.members[] | select(.role == "sync_standby") | .name] | join(", ") | if . == "" then "none" else . end' <<<"$J")"
  log "pg-rw ->     $(kubectl -n "$PG_NS" get endpointslice -l kubernetes.io/service-name=pg-rw -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null || true)"
  log "pg-ro ->     $(kubectl -n "$PG_NS" get endpointslice -l kubernetes.io/service-name=pg-ro -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]} {end}' 2>/dev/null || true)"
else
  log "Patroni REST API not reachable yet."; kubectl -n "$PG_NS" get pods -o wide
fi
