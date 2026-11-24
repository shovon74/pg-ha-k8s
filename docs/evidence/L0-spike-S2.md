# L0 spike S2: NetworkPolicy enforcement and API egress

**Result: PASS**

- **Question:** Does k3s enforce NetworkPolicy, including egress to the API server?
- **Pass criteria:** Default-deny blocks ingress, egress, DNS and API access across nodes. Explicit allows restore only the intended paths, including verified TLS to the Kubernetes API, while unlisted paths stay blocked.
- **Run:** 2026-11-23T11:12:07Z (UTC), 67 s
- **Reproduce:** `make spike-s2`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Checks

| Check | Result |
|---|---|
| client -> server open | PASS |
| denied -> server open | PASS |
| client -> API (verified TLS) open | PASS |
| client DNS works | PASS |
| client -> server blocked | PASS |
| client -> API blocked | PASS |
| client DNS blocked | PASS |
| client DNS restored | PASS |
| client -> server open across nodes | PASS |
| denied -> server still blocked | PASS |
| client -> API still blocked | PASS |
| API reachable with verified TLS using an ipBlock allow (A=blocked, B=open) | PASS |
| denied pod -> API still blocked | PASS |
| client -> denied pod still blocked | PASS |

## Setup: server, allowed client and denied client on three different agents

```console
$ kubectl create ns spike-s2
namespace/spike-s2 created
```

```console
$ kubectl -n spike-s2 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP; echo API service=10.43.0.1:443 backend=172.18.0.2:6443 DNS=10.43.0.10
POD      NODE                IP
client   k3d-pg-ha-agent-1   10.42.1.3
denied   k3d-pg-ha-agent-2   10.42.2.2
server   k3d-pg-ha-agent-0   10.42.4.2
API service=10.43.0.1:443 backend=172.18.0.2:6443 DNS=10.43.0.10
```

## Baseline with no policy

## Default deny for ingress and egress

```console
$ kubectl -n spike-s2 apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
YAML
networkpolicy.networking.k8s.io/default-deny created
```

## Explicit allows: DNS, and client to server only

```console
$ kubectl -n spike-s2 apply -f - <<'YAML'
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
YAML
networkpolicy.networking.k8s.io/allow-dns created
networkpolicy.networking.k8s.io/client-to-server created
networkpolicy.networking.k8s.io/server-from-client created
```

## API egress: which destination must the policy allow?

Policy evaluation can happen before or after the Service address is translated, so both forms are tested. Variant A allows only the Service address (10.43.0.1:443). Variant B allows only the real backend (172.18.0.2:6443).

```console
$ api_policy 10.43.0.1 443
networkpolicy.networking.k8s.io/client-to-api created
```

Variant A (Service address only): **blocked**

```console
$ api_policy 172.18.0.2 6443
networkpolicy.networking.k8s.io/client-to-api configured
```

Variant B (real backend only): **open**

```console
$ kubectl -n spike-s2 get networkpolicy
NAME                 POD-SELECTOR   AGE
allow-dns            <none>         43s
client-to-api        app=client     36s
client-to-server     app=client     43s
default-deny         <none>         53s
server-from-client   app=server     43s
```
