# L2: failover, switchover and split-brain

Generated from the per-mode files in [`L2/`](L2/) each time a mode runs. Timestamps are UTC. Hand-written notes: [`L2-failover-history.md`](L2-failover-history.md).

RTO is fault injection to the first commit acknowledged by a new primary, measured by a probe Job writing through pg-rw every 500 ms over new connections with a 2 s connect timeout. RPO is the number of acknowledged rows missing on the new primary. The target is RTO at most 30 s with safe settings (ttl 20, loop_wait 3, retry_timeout 5). A run over the target is reported as **OVER TARGET**, not PASS. After every run the harness also checks WAL archive health on the current primary (no new archive failures, a segment archived within 90 s of a WAL fill) and records where CoreDNS ran.

## RTO by failure mode

| Mode | Result | RTO |
|---|---|---|
| [pod](L2/pod.md) | PASS | min 3.60 s, median 3.78 s, max 5.13 s over 3 runs |
| [node](L2/node.md) | PASS | min 23.22 s, median 23.93 s, max 26.19 s over 3 runs |
| [storage](L2/storage.md) | PASS | min 2.39 s, median 3.37 s, max 3.69 s over 3 runs |
| [split-brain](L2/split-brain.md) | PASS | min 20.47 s, median 22.18 s, max 22.20 s over 3 runs |
| [switchover](L2/switchover.md) | PASS | min 2.08 s, median 2.08 s, max 2.08 s over 1 runs |
| chain | not run | |
| [api-outage](L2/api-outage.md) | PASS |  |

## pod: Result: PASS

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- Details: [`L2/pod.md`](L2/pod.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 3.78 | 3.24 | 132 | 0 | 1 | restart only | 8.88 | k3d-pg-ha-server-0 | 0 | 2.26 | PASS |
| 2 | pg-0 | pg-2 | 5.13 | 4.55 | 131 | 0 | 1 | restart only | 10.33 | k3d-pg-ha-server-0 | 0 | 2.48 | PASS |
| 3 | pg-2 | pg-1 | 3.60 | 3.09 | 132 | 0 | 1 | restart only | 10.01 | k3d-pg-ha-server-0 | 0 | 2.41 | PASS |

RTO: min 3.60 s, median 3.78 s, max 5.13 s over 3 runs. Target 30 s.


## node: Result: PASS

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- Details: [`L2/node.md`](L2/node.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 23.22 | 23.43 | 170 | 0 | 1 | restart only | 39.42 | k3d-pg-ha-server-0 | 0 | 5.39 | PASS |
| 2 | pg-0 | pg-2 | 26.19 | 25.83 | 166 | 0 | 1 | restart only | 47.96 | k3d-pg-ha-server-0 | 0 | 2.32 | PASS |
| 3 | pg-2 | pg-1 | 23.93 | 23.81 | 166 | 0 | 1 | restart only | 45.49 | k3d-pg-ha-server-0 | 0 | 2.60 | PASS |

RTO: min 23.22 s, median 23.93 s, max 26.19 s over 3 runs. Target 30 s.


## storage: Result: PASS

- **Fault:** The primary's data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container's mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.
- Details: [`L2/storage.md`](L2/storage.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 2.39 | 2.58 | 212 | 0 | 1 | restart only | 12.09 | k3d-pg-ha-server-0 | 0 | 2.26 | PASS |
| 2 | pg-0 | pg-2 | 3.69 | 4.00 | 209 | 0 | 1 | restart only | 14.10 | k3d-pg-ha-server-0 | 0 | 2.38 | PASS |
| 3 | pg-2 | pg-1 | 3.37 | 3.17 | 209 | 0 | 1 | restart only | 15.46 | k3d-pg-ha-server-0 | 0 | 2.60 | PASS |

RTO: min 2.39 s, median 3.37 s, max 3.69 s over 3 runs. Target 30 s.


## split-brain: Result: PASS

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- Details: [`L2/split-brain.md`](L2/split-brain.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 20.47 | 14.49 | 189 | 0 | 1 | restart only | 24.61 | k3d-pg-ha-server-0 | 0 | 2.45 | PASS |
| 2 | pg-0 | pg-2 | 22.20 | 15.11 | 188 | 0 | 1 | restart only | 25.81 | k3d-pg-ha-server-0 | 0 | 2.45 | PASS |
| 3 | pg-2 | pg-1 | 22.18 | 15.69 | 186 | 0 | 1 | restart only | 27.38 | k3d-pg-ha-server-0 | 0 | 2.69 | PASS |

RTO: min 20.47 s, median 22.18 s, max 22.20 s over 3 runs. Target 30 s.


## switchover: Result: PASS

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- Details: [`L2/switchover.md`](L2/switchover.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-1 | pg-0 | 2.08 | 2.15 | 95 | 0 | 1 | restart only | 8.90 | k3d-pg-ha-server-0 | 0 | 1.84 | PASS |

RTO: min 2.08 s, median 2.08 s, max 2.08 s over 1 runs. Target 30 s.


## chain

Not run yet.

## api-outage: Result: PASS

- **Fault:** `docker stop` on the k3d server container for 60 s, then `docker start`. With `failsafe_mode` off (ADR-002), every member should demote, so writes stop and reads continue. Observed by a Job on an agent node that queried each member by pod IP every second. Its log was read after the API returned, so nothing depends on `make status` or the API during the outage.
- Details: [`L2/api-outage.md`](L2/api-outage.md)


| Outage (s) | Last write during outage (s) | Rounds with no primary | Reads served | Max primaries in a round | API back (s) | Healthy again (s) | First write after (s) | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|
| 60 | +9.14 | 55 of 65 | 65 of 65 rounds | 1 | +74.11 | +114.52 | +86.13 | PASS |

Times are seconds after the server was stopped. Write unavailability lasts the whole outage plus recovery, by design.

