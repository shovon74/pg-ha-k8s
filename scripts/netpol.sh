#!/usr/bin/env bash
# L6 (ADR-012, R8.6): renders and applies the NetworkPolicies in deploy/netpol for every project namespace that
# exists (pg-ha from make deploy; monitoring and monitoring-host from make monitoring). Idempotent. Called by
# scripts/deploy.sh and scripts/monitoring.sh. Addresses are discovered from the live cluster, never hard-coded:
#   API backend   the kubernetes Service's EndpointSlice (S2: only the real backend address works)
#   proxy source  the control-plane node's InternalIP, and the first two addresses of its podCIDR (flannel
#                 tunnel and cni0 bridge), from which the API server's pod and service proxy connects.
. "$(dirname "$0")/lib.sh"
read -r API_IP API_PORT n < <(kubectl -n default get endpointslice -l kubernetes.io/service-name=kubernetes -o json |
  jq -r '[.items[].endpoints[].addresses[]] as $a | "\($a[0]) \(.items[0].ports[0].port) \($a | length)"')
[ "$n" = 1 ] || die "expected exactly one API server backend, found $n"
read -r NODE_IP POD_CIDR < <(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json |
  jq -r '.items[0] | "\(.status.addresses[] | select(.type == "InternalIP") | .address) \(.spec.podCIDR)"')
read -r TUNNEL BRIDGE < <(python3 -I -c 'import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1]); print(n[0], n[1])' "$POD_CIDR")
log "NetworkPolicy inputs: API backend $API_IP:$API_PORT, API proxy sources $NODE_IP $TUNNEL $BRIDGE"
render() { sed "s|__API_IP__|$API_IP|g; s|__API_PORT__|$API_PORT|g; s|__PROXY_NODE__|$NODE_IP|g; s|__PROXY_TUNNEL__|$TUNNEL|g; s|__PROXY_BRIDGE__|$BRIDGE|g" "$1"; }
apply() { local out; out=$(render "$1" | kubectl apply -f -) || die "applying $1 failed"; grep -v unchanged <<<"$out" || true; }
if kubectl get ns "$PG_NS" >/dev/null 2>&1; then apply "$ROOT_DIR/deploy/netpol/pg-ha.yaml"; fi
if kubectl get ns monitoring >/dev/null 2>&1 && kubectl get ns monitoring-host >/dev/null 2>&1; then
  apply "$ROOT_DIR/deploy/netpol/monitoring.yaml"
fi
