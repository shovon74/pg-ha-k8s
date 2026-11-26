#!/usr/bin/env bash
# L5 (ADR-011): deploys Prometheus, Alertmanager, kube-state-metrics and node_exporter from deploy/monitoring
# with the pinned images, then waits until every scrape target is up. Idempotent. Part of make up.
# The postgres_exporter sidecar is part of the StatefulSet (scripts/deploy.sh), so it is not applied here.
. "$(dirname "$0")/lib.sh"
cluster_exists || die "cluster $CLUSTER_NAME not found, run: make cluster"
kubectl get ns "$PG_NS" >/dev/null 2>&1 || die "namespace $PG_NS not found, run: make deploy"

kubectl kustomize "$ROOT_DIR/deploy/monitoring" |
  sed "s|__PROMETHEUS_IMAGE__|$PROMETHEUS_IMAGE|; s|__ALERTMANAGER_IMAGE__|$ALERTMANAGER_IMAGE|; s|__KUBE_STATE_METRICS_IMAGE__|$KUBE_STATE_METRICS_IMAGE|; s|__NODE_EXPORTER_IMAGE__|$NODE_EXPORTER_IMAGE|" |
  kubectl apply -f - | grep -v unchanged || true
# L6 (R8.6): NetworkPolicies for monitoring and monitoring-host (and pg-ha, unchanged if already applied).
"$ROOT_DIR/scripts/netpol.sh"
for d in prometheus alertmanager kube-state-metrics; do kubectl -n monitoring rollout status "deployment/$d" --timeout=300s >/dev/null; done
kubectl -n monitoring-host rollout status daemonset/node-exporter --timeout=300s >/dev/null

# Every active target up, read through the API server's service proxy (no port-forward, no exec).
want=$((3 * 2 + $(kubectl get nodes --no-headers | wc -l) + 4))   # 3 members x 2 jobs, nodes, ksm x 2 + am + self
end=$((SECONDS + ${MON_WAIT:-180}))
while :; do
  t=$(kubectl get --raw /api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/targets?state=active 2>/dev/null |
      jq -r '[.data.activeTargets[] | select(.health == "up")] | length' 2>/dev/null || echo 0)
  [ "$t" -ge "$want" ] && break
  [ $SECONDS -lt $end ] || { kubectl get --raw /api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/targets?state=active |
    jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health) \(.lastError)"' >&2 || true; die "only $t of $want targets up"; }
  sleep 3
done
rules=$(kubectl get --raw /api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/rules | jq '[.data.groups[].rules[]] | length')
log "Monitoring up: $t of $want targets up, $rules rules loaded. Alerts: make alerts. UIs: docs/observability.md"
