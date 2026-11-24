#!/usr/bin/env bash
# S4: is v1 Endpoints served at runtime, and how quickly do changes reach EndpointSlices and traffic?
. "$(dirname "$0")/lib.sh"
FLIPS=20
LIMIT_MS=2000
ev_start S4 "v1 Endpoints and EndpointSlice mirroring" \
  "Is v1 Endpoints served at runtime, and how long does EndpointSlice mirroring take?" \
  "v1 Endpoints is served and writable, a selector-less Service gets a mirrored EndpointSlice, and all $FLIPS leader-style address changes reach both the EndpointSlice and real ClusterIP traffic within ${LIMIT_MS} ms (the margin between the 28 s RTO estimate and the 30 s target)."

section "Setup: two backends and a client on different agents, selector-less Service"
run "kubectl create ns $NS"
apply_yaml >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: {name: code}
data:
  backend.py: |
    import http.server, os
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            b = os.environ["NAME"].encode(); self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        def log_message(self, *a): pass
    http.server.ThreadingHTTPServer(("", 8080), H).serve_forever()
  client.py: |
    import http.client, sys, time
    last = None
    while True:
        try:
            c = http.client.HTTPConnection("s4-rw", 8080, timeout=0.5); c.request("GET", "/"); v = c.getresponse().read().decode(); c.close()
        except Exception:
            v = "error"
        if v != last:
            print(int(time.time() * 1000), v, flush=True); last = v
        time.sleep(0.01)
---
apiVersion: v1
kind: Service
metadata: {name: s4-rw}
spec:
  ports: [{name: http, port: 8080, targetPort: 8080}]
YAML
for i in 0 1 2; do
  case $i in 0) name=backend-a; f=backend.py;; 1) name=backend-b; f=backend.py;; 2) name=client; f=client.py;; esac
  apply_yaml >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $name, labels: {app: s4}}
spec:
  nodeName: k3d-pg-ha-agent-$i
  containers:
  - name: c
    image: __IMAGE__
    imagePullPolicy: IfNotPresent
    command: [python3, -u, /code/$f]
    env: [{name: NAME, value: $name}]
    volumeMounts: [{name: code, mountPath: /code}]
  volumes:
  - name: code
    configMap: {name: code}
YAML
done
kubectl -n "$NS" wait --for=condition=Ready pod --all --timeout=90s >/dev/null
A=$(kubectl -n "$NS" get pod backend-a -o jsonpath='{.status.podIP}')
B=$(kubectl -n "$NS" get pod backend-b -o jsonpath='{.status.podIP}')
run "kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP"

set_ep() { kubectl -n "$NS" patch endpoints s4-rw --type=merge -p \
  "{\"subsets\":[{\"addresses\":[{\"ip\":\"$1\"}],\"ports\":[{\"name\":\"http\",\"port\":8080}]}]}" >/dev/null 2>&1; }

section "v1 Endpoints is served at runtime"
apply_yaml >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Endpoints
metadata: {name: s4-rw}
subsets:
- addresses: [{ip: $A}]
  ports: [{name: http, port: 8080}]
YAML
run "kubectl api-resources --api-group='' | grep -E '^(NAME|endpoints)'" || true
run "kubectl get --raw /api/v1/namespaces/$NS/endpoints/s4-rw | jq -c '{kind, apiVersion, subsets}'" || true
dep=$(kubectl -n "$NS" get endpoints s4-rw 2>&1 >/dev/null || true)
note "API server warning on read: \`${dep:-none}\`"
check "v1 Endpoints object is served" kubectl get --raw "/api/v1/namespaces/$NS/endpoints/s4-rw"
check "v1 Endpoints object is writable (PATCH)" set_ep "$A"

section "EndpointSlice mirroring"
sleep 2
slice_ip() { kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name=s4-rw -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null; }
run "kubectl -n $NS get endpointslices -l kubernetes.io/service-name=s4-rw -o json | jq -c '.items[] | {name: .metadata.name, managedBy: .metadata.labels[\"endpointslice.kubernetes.io/managed-by\"], addresses: [.endpoints[].addresses[]]}'"
check "EndpointSlice mirrored by the mirroring controller" bash -c \
  "kubectl -n $NS get endpointslices -l kubernetes.io/service-name=s4-rw,endpointslice.kubernetes.io/managed-by=endpointslicemirroring-controller.k8s.io -o name | grep -q ."

section "Latency: $FLIPS address changes, spaced 3 s apart"
note "Each change is timed from just before the PATCH. **Slice** is when the EndpointSlice shows the new address, polled with kubectl (about 50–100 ms resolution, so it reads high). **Traffic** is when an in-cluster client, polling the ClusterIP every 10 ms over new connections, first gets the new backend. All clocks are the same VM clock."
res=$(mktemp); cur=$A; missed=0
for n in $(seq 1 $FLIPS); do
  if [ "$cur" = "$A" ]; then next=$B; want=backend-b; else next=$A; want=backend-a; fi
  t0=$(date +%s%3N); set_ep "$next"; ts=""; end=$((t0+10000))
  while [ "$(date +%s%3N)" -lt $end ]; do
    [ "$(slice_ip)" = "$next" ] && { ts=$(date +%s%3N); break; }
  done
  tt=""
  while [ "$(date +%s%3N)" -lt $end ]; do
    tt=$(kubectl -n "$NS" logs client --since=30s 2>/dev/null | awk -v w="$want" -v t="$t0" '$2==w && $1>=t {print $1; exit}')
    [ -n "$tt" ] && break; sleep 0.1
  done
  if [ -z "$ts" ] || [ -z "$tt" ]; then missed=$((missed+1)); echo "$n miss miss" >> "$res"
  else echo "$n $((ts-t0)) $((tt-t0))" >> "$res"; fi
  cur=$next; sleep 3
done
stats() { awk -v c="$1" '$c!="miss"{print $c}' "$res" | sort -n | awk '{a[NR]=$1;s+=$1} END{if(NR)printf "n=%d min=%d median=%d p95=%d max=%d mean=%.0f (ms)\n",NR,a[1],a[int((NR+1)/2)],a[int(NR*0.95+0.999)],a[NR],s/NR; else print "no samples"}'; }
run "printf 'flip slice_ms traffic_ms\n'; cat $res"  >/dev/null
run "echo \"slice:   \$(stats 2)\"; echo \"traffic: \$(stats 3)\""
max_s=$(awk '$2!="miss"{print $2}' "$res" | sort -n | tail -1); max_t=$(awk '$3!="miss"{print $3}' "$res" | sort -n | tail -1)
check "All $FLIPS changes observed" test "$missed" -eq 0
check "Worst EndpointSlice latency ≤ ${LIMIT_MS} ms (measured ${max_s:-none} ms)" test "${max_s:-999999}" -le $LIMIT_MS
check "Worst real-traffic latency ≤ ${LIMIT_MS} ms (measured ${max_t:-none} ms)" test "${max_t:-999999}" -le $LIMIT_MS
rm -f "$res"
ev_finish
