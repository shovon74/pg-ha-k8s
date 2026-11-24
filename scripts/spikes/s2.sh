#!/usr/bin/env bash
# S2: does k3s enforce NetworkPolicy, including egress to the Kubernetes API?
# Uses kubectl exec to run connection probes. This is a committed, automated test script (D4, HC20).
. "$(dirname "$0")/lib.sh"
ev_start S2 "NetworkPolicy enforcement and API egress" \
  "Does k3s enforce NetworkPolicy, including egress to the API server?" \
  "Default-deny blocks ingress, egress, DNS and API access across nodes. Explicit allows restore only the intended paths, including verified TLS to the Kubernetes API, while unlisted paths stay blocked."

section "Setup: server, allowed client and denied client on three different agents"
run "kubectl create ns $NS"
apply_yaml >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: {name: code}
data:
  probe.py: |
    import socket, ssl, sys
    kind, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    try:
        s = socket.create_connection((host, port), timeout=2)
        if kind == "tls":
            ctx = ssl.create_default_context(cafile="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
            s = ctx.wrap_socket(s, server_hostname="kubernetes.default.svc"); s.settimeout(2)
            s.sendall(b"GET /version HTTP/1.1\r\nHost: kubernetes.default.svc\r\nConnection: close\r\n\r\n")
            if not s.recv(64).startswith(b"HTTP/1.1"): sys.exit(1)
        print("open")
    except Exception as e:
        print("blocked:", type(e).__name__); sys.exit(1)
  server.py: |
    import http.server
    http.server.ThreadingHTTPServer(("", 8080), http.server.SimpleHTTPRequestHandler).serve_forever()
YAML
i=0
for p in server client denied; do
  cmd='[python3, -m, http.server, "8080", --directory, /code]'; [ $p = server ] || cmd='[sleep, "3600"]'
  apply_yaml >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $p, labels: {app: $p}}
spec:
  nodeName: k3d-pg-ha-agent-$i
  terminationGracePeriodSeconds: 0
  containers:
  - name: c
    image: __IMAGE__
    imagePullPolicy: IfNotPresent
    command: $cmd
    volumeMounts: [{name: code, mountPath: /code}]
  volumes:
  - name: code
    configMap: {name: code}
YAML
  i=$((i+1))
done
kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: server}
spec:
  selector: {app: server}
  ports: [{port: 8080, targetPort: 8080}]
YAML
kubectl -n "$NS" wait --for=condition=Ready pod --all --timeout=90s >/dev/null
SERVER_IP=$(kubectl -n "$NS" get pod server -o jsonpath='{.status.podIP}')
API_SVC=$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')
API_EP=$(kubectl -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].endpoints[0].addresses[0]}')
API_EP_PORT=$(kubectl -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].ports[0].port}')
DNS_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
run "kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP; echo API service=$API_SVC:443 backend=$API_EP:$API_EP_PORT DNS=$DNS_IP"

probe() { kubectl -n "$NS" exec "$1" -- python3 -I /code/probe.py "$2" "$3" "$4" 2>/dev/null; }
dns() { kubectl -n "$NS" exec "$1" -- python3 -I -c 'import socket;socket.setdefaulttimeout(2);socket.gethostbyname("kubernetes.default.svc.cluster.local")' >/dev/null 2>&1; }
# Policies apply asynchronously, so wait up to 30 s for the state, then require 3 consecutive matches.
expect() { # open|blocked probe-args...
  local want=$1 streak=0 end=$((SECONDS+30)) got; shift
  while [ $SECONDS -lt $end ]; do
    if "$@" >/dev/null 2>&1; then got=open; else got=blocked; fi
    if [ "$got" = "$want" ]; then streak=$((streak+1)); [ $streak -ge 3 ] && return 0; else streak=0; fi
    sleep 0.5
  done; return 1
}

section "Baseline with no policy"
check "client -> server open" expect open probe client tcp "$SERVER_IP" 8080
check "denied -> server open" expect open probe denied tcp "$SERVER_IP" 8080
check "client -> API (verified TLS) open" expect open probe client tls "$API_SVC" 443
check "client DNS works" expect open dns client

section "Default deny for ingress and egress"
run "kubectl -n $NS apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
YAML"
check "client -> server blocked" expect blocked probe client tcp "$SERVER_IP" 8080
check "client -> API blocked" expect blocked probe client tls "$API_SVC" 443
check "client DNS blocked" expect blocked dns client

section "Explicit allows: DNS, and client to server only"
run "kubectl -n $NS apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
      podSelector: {matchLabels: {k8s-app: kube-dns}}
    ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: client-to-server}
spec:
  podSelector: {matchLabels: {app: client}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: server}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: server-from-client}
spec:
  podSelector: {matchLabels: {app: server}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: client}}}]
    ports: [{protocol: TCP, port: 8080}]
YAML"
check "client DNS restored" expect open dns client
check "client -> server open across nodes" expect open probe client tcp "$SERVER_IP" 8080
check "denied -> server still blocked" expect blocked probe denied tcp "$SERVER_IP" 8080
check "client -> API still blocked" expect blocked probe client tls "$API_SVC" 443

section "API egress: which destination must the policy allow?"
note "Policy evaluation can happen before or after the Service address is translated, so both forms are tested. Variant A allows only the Service address ($API_SVC:443). Variant B allows only the real backend ($API_EP:$API_EP_PORT)."
api_policy() { kubectl -n "$NS" apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: client-to-api}
spec:
  podSelector: {matchLabels: {app: client}}
  policyTypes: [Egress]
  egress:
  - to: [{ipBlock: {cidr: $1/32}}]
    ports: [{protocol: TCP, port: $2}]
YAML
}
run "api_policy $API_SVC 443"
if expect open probe client tls "$API_SVC" 443; then A=open; else A=blocked; fi
note "Variant A (Service address only): **$A**"
log "Variant A (Service IP only): $A"
run "api_policy $API_EP $API_EP_PORT"
if expect open probe client tls "$API_SVC" 443; then B=open; else B=blocked; fi
note "Variant B (real backend only): **$B**"
log "Variant B (backend IP only): $B"
check "API reachable with verified TLS using an ipBlock allow (A=$A, B=$B)" test "$A" = open -o "$B" = open
check "denied pod -> API still blocked" expect blocked probe denied tls "$API_SVC" 443
check "client -> denied pod still blocked" expect blocked probe client tcp "$(kubectl -n "$NS" get pod denied -o jsonpath='{.status.podIP}')" 8080
run "kubectl -n $NS get networkpolicy"
ev_finish
