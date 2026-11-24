# L0 spike S4: v1 Endpoints and EndpointSlice mirroring

**Result: PASS**

- **Question:** Is v1 Endpoints served at runtime, and how long does EndpointSlice mirroring take?
- **Pass criteria:** v1 Endpoints is served and writable, a selector-less Service gets a mirrored EndpointSlice, and all 20 leader-style address changes reach both the EndpointSlice and real ClusterIP traffic within 2000 ms (the margin between the 28 s RTO estimate and the 30 s target).
- **Run:** 2026-11-23T11:13:33Z (UTC), 74 s
- **Reproduce:** `make spike-s4`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Checks

| Check | Result |
|---|---|
| v1 Endpoints object is served | PASS |
| v1 Endpoints object is writable (PATCH) | PASS |
| EndpointSlice mirrored by the mirroring controller | PASS |
| All 20 changes observed | PASS |
| Worst EndpointSlice latency ≤ 2000 ms (measured 247 ms) | PASS |
| Worst real-traffic latency ≤ 2000 ms (measured 173 ms) | PASS |

## Setup: two backends and a client on different agents, selector-less Service

```console
$ kubectl create ns spike-s4
namespace/spike-s4 created
```

```console
$ kubectl -n spike-s4 get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
POD         NODE                IP
backend-a   k3d-pg-ha-agent-0   10.42.4.3
backend-b   k3d-pg-ha-agent-1   10.42.1.7
client      k3d-pg-ha-agent-2   10.42.2.3
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
{"kind":"Endpoints","apiVersion":"v1","subsets":[{"addresses":[{"ip":"10.42.4.3"}],"ports":[{"name":"http","port":8080,"protocol":"TCP"}]}]}
```

API server warning on read: `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice`

## EndpointSlice mirroring

```console
$ kubectl -n spike-s4 get endpointslices -l kubernetes.io/service-name=s4-rw -o json | jq -c '.items[] | {name: .metadata.name, managedBy: .metadata.labels["endpointslice.kubernetes.io/managed-by"], addresses: [.endpoints[].addresses[]]}'
{"name":"s4-rw-mg7g4","managedBy":"endpointslicemirroring-controller.k8s.io","addresses":["10.42.4.3"]}
```

## Latency: 20 address changes, spaced 3 s apart

Each change is timed from just before the PATCH. **Slice** is when the EndpointSlice shows the new address, polled with kubectl (about 50–100 ms resolution, so it reads high). **Traffic** is when an in-cluster client, polling the ClusterIP every 10 ms over new connections, first gets the new backend. All clocks are the same VM clock.

```console
$ printf 'flip slice_ms traffic_ms\n'; cat /tmp/tmp.wt23w6iipG
flip slice_ms traffic_ms
1 214 129
2 238 149
3 209 132
4 208 126
5 217 145
6 209 128
7 221 137
8 212 133
9 211 121
10 215 134
11 210 128
12 208 127
13 208 119
14 207 137
15 214 134
16 247 173
17 219 126
18 201 135
19 204 124
20 217 128
```

```console
$ echo "slice:   $(stats 2)"; echo "traffic: $(stats 3)"
slice:   n=20 min=201 median=211 p95=238 max=247 mean=214 (ms)
traffic: n=20 min=119 median=129 p95=149 max=173 mean=133 (ms)
```

## Run history

Three complete runs on 2026-11-23 (UTC), all PASS. This file holds the last one. Worst values across all runs: **EndpointSlice 651 ms, real traffic 405 ms** (both from the first run).

| Run | Slice max (ms) | Traffic max (ms) |
|---|---:|---:|
| 1 | 651 | 405 |
| 2 | 281 | 177 |
| 3 | 247 | 173 |

**Scope:** the backends are small test servers and the Endpoints were patched by `kubectl`, not Patroni. Real failover timing is measured in L2.
