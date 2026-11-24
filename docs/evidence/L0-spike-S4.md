# L0 spike S4: v1 Endpoints and EndpointSlice mirroring

**Result: PASS**

- **Question:** Is v1 Endpoints served at runtime, and how long does EndpointSlice mirroring take?
- **Pass criteria:** v1 Endpoints is served and writable, a selector-less Service gets a mirrored EndpointSlice, and all 20 leader-style address changes reach both the EndpointSlice and real ClusterIP traffic within 2000 ms (the margin between the 28 s RTO estimate and the 30 s target).
- **Run:** 2026-11-24T16:47:41Z (UTC), 73 s
- **Reproduce:** `make spike-s4`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`
- **History:** [`L0-spike-S4-history.md`](L0-spike-S4-history.md) (maintained by hand, never written by this harness)

## Checks

| Check | Result |
|---|---|
| v1 Endpoints object is served | PASS |
| v1 Endpoints object is writable (PATCH) | PASS |
| EndpointSlice mirrored by the mirroring controller | PASS |
| All 20 changes observed | PASS |
| Worst EndpointSlice latency ≤ 2000 ms (measured 311 ms) | PASS |
| Worst real-traffic latency ≤ 2000 ms (measured 208 ms) | PASS |

## Setup: two backends and a client on different agents, selector-less Service

```console
$ kubectl create ns spike-s4
namespace/spike-s4 created
```

```console
$ kubectl -n spike-s4 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
POD         NODE                IP
backend-a   k3d-pg-ha-agent-0   10.42.4.4
backend-b   k3d-pg-ha-agent-1   10.42.1.13
client      k3d-pg-ha-agent-2   10.42.2.4
```

## v1 Endpoints is served at runtime

```console
$ kubectl api-resources --api-group='' | grep -E '^(NAME|endpoints)'
NAME                     SHORTNAMES   APIVERSION   NAMESPACED   KIND
endpoints                ep           v1           true         Endpoints
```

```console
$ kubectl get --raw /api/v1/namespaces/spike-s4/endpoints/s4-rw | jq -c '{kind, apiVersion, subsets}'
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
{"kind":"Endpoints","apiVersion":"v1","subsets":[{"addresses":[{"ip":"10.42.4.4"}],"ports":[{"name":"http","port":8080,"protocol":"TCP"}]}]}
```

API server warning on read: `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice`

## EndpointSlice mirroring

```console
$ kubectl -n spike-s4 get endpointslices -l kubernetes.io/service-name=s4-rw -o json | jq -c '.items[] | {name: .metadata.name, managedBy: .metadata.labels["endpointslice.kubernetes.io/managed-by"], addresses: [.endpoints[].addresses[]]}'
{"name":"s4-rw-f4d6l","managedBy":"endpointslicemirroring-controller.k8s.io","addresses":["10.42.4.4"]}
```

## Latency: 20 address changes, spaced 3 s apart

Each change is timed from just before the PATCH. **Slice** is when the EndpointSlice shows the new address, polled with kubectl (about 50–100 ms resolution, so it reads high). **Traffic** is when an in-cluster client, polling the ClusterIP every 10 ms over new connections, first gets the new backend. All clocks are the same VM clock.

```console
$ printf 'flip slice_ms traffic_ms\n'; cat /tmp/tmp.vOHCMXCoYs
flip slice_ms traffic_ms
1 311 208
2 218 136
3 208 131
4 216 131
5 219 146
6 215 140
7 218 129
8 203 137
9 213 144
10 210 132
11 221 146
12 223 128
13 214 130
14 216 131
15 211 137
16 212 136
17 210 121
18 214 132
19 216 143
20 213 137
```

```console
$ echo "slice:   $(stats 2)"; echo "traffic: $(stats 3)"
slice:   n=20 min=203 median=214 p95=223 max=311 mean=219 (ms)
traffic: n=20 min=121 median=136 p95=146 max=208 mean=139 (ms)
```
