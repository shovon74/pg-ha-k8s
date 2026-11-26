# L2: failover, switchover and split-brain

Generated from the per-mode files in [`L2/`](L2/) each time a mode runs. Timestamps are UTC. Hand-written notes: [`L2-failover-history.md`](L2-failover-history.md).

RTO is fault injection to the first commit acknowledged by a new primary, measured by a probe Job writing through pg-rw every 500 ms over new connections with a 2 s connect timeout. RPO is the number of acknowledged rows missing on the new primary. The target is RTO at most 30 s with safe settings (ttl 20, loop_wait 3, retry_timeout 5). A run over the target is reported as **OVER TARGET**, not PASS. After every run the harness also checks WAL archive health on the current primary (no new archive failures, a segment archived within 90 s of a WAL fill) and records where CoreDNS ran.

## RTO by failure mode

| Mode | Result | RTO |
|---|---|---|
| [pod](L2/pod.md) | PASS | min 3.33 s, median 3.74 s, max 4.34 s over 3 runs |
| [node](L2/node.md) | PASS | min 22.52 s, median 23.27 s, max 26.16 s over 3 runs |
| [storage](L2/storage.md) | PASS | min 3.01 s, median 4.54 s, max 4.65 s over 3 runs |
| [split-brain](L2/split-brain.md) | PASS | min 19.56 s, median 20.61 s, max 20.62 s over 3 runs |
| [switchover](L2/switchover.md) | PASS | min 2.56 s, median 2.60 s, max 2.72 s over 3 runs |
| [chain](L2/chain.md) | PASS |  |
| [diverge](L2/diverge.md) | PASS |  |
| [api-outage](L2/api-outage.md) | PASS |  |

## pod: Result: PASS

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- Details: [`L2/pod.md`](L2/pod.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 4.34 | 3.86 | 132 | 0 | 1 | restart only | 10.47 | k3d-pg-ha-server-0 | 0 | 2.36 | PASS |
| 2 | pg-2 | pg-1 | 3.33 | 3.35 | 131 | 0 | 1 | restart only | 10.61 | k3d-pg-ha-server-0 | 0 | 1.88 | PASS |
| 3 | pg-1 | pg-0 | 3.74 | 3.73 | 132 | 0 | 1 | restart only | 11.78 | k3d-pg-ha-server-0 | 0 | 2.80 | PASS |

RTO: min 3.33 s, median 3.74 s, max 4.34 s over 3 runs. Target 30 s.


## node: Result: PASS

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- Details: [`L2/node.md`](L2/node.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 26.16 | 26.27 | 143 | 0 | 1 | restart only | 65.88 | k3d-pg-ha-server-0 | 0 | 1.81 | PASS |
| 2 | pg-2 | pg-1 | 22.52 | 22.64 | 169 | 0 | 1 | restart only | 42.88 | k3d-pg-ha-server-0 | 0 | 2.10 | PASS |
| 3 | pg-1 | pg-0 | 23.27 | 23.28 | 171 | 0 | 1 | restart only | 44.90 | k3d-pg-ha-server-0 | 0 | 2.60 | PASS |

RTO: min 22.52 s, median 23.27 s, max 26.16 s over 3 runs. Target 30 s.


## storage: Result: PASS

- **Fault:** The primary's data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container's mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.
- Details: [`L2/storage.md`](L2/storage.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 3.01 | 3.29 | 211 | 0 | 1 | restart only | 13.04 | k3d-pg-ha-server-0 | 0 | 1.94 | PASS |
| 2 | pg-2 | pg-1 | 4.65 | 4.65 | 207 | 0 | 1 | restart only | 16.04 | k3d-pg-ha-server-0 | 0 | 2.24 | PASS |
| 3 | pg-1 | pg-0 | 4.54 | 4.69 | 171 | 0 | 1 | restart only | 18.05 | k3d-pg-ha-server-0 | 0 | 2.93 | PASS |

RTO: min 3.01 s, median 4.54 s, max 4.65 s over 3 runs. Target 30 s.


## split-brain: Result: PASS

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- Details: [`L2/split-brain.md`](L2/split-brain.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 20.62 | 15.15 | 188 | 0 | 1 | restart only | 24.59 | k3d-pg-ha-server-0 | 0 | 2.67 | PASS |
| 2 | pg-2 | pg-1 | 20.61 | 15.31 | 188 | 0 | 1 | restart only | 24.31 | k3d-pg-ha-server-0 | 0 | 2.35 | PASS |
| 3 | pg-1 | pg-0 | 19.56 | 14.64 | 188 | 0 | 1 | restart only | 23.53 | k3d-pg-ha-server-0 | 0 | 2.68 | PASS |

RTO: min 19.56 s, median 20.61 s, max 20.62 s over 3 runs. Target 30 s.


## switchover: Result: PASS

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. Since L6 the POST carries basic auth (user `patroni`, password from `./secrets`, passed to curl on stdin); unauthenticated state-changing requests are refused (`make test-security`).
- Details: [`L2/switchover.md`](L2/switchover.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| 1 | pg-0 | pg-2 | 2.56 | 2.64 | 93 | 0 | 1 | restart only | 9.01 | k3d-pg-ha-server-0 | 0 | 1.66 | PASS |
| 2 | pg-2 | pg-1 | 2.60 | 2.63 | 94 | 0 | 1 | restart only | 8.38 | k3d-pg-ha-server-0 | 0 | 2.19 | PASS |
| 3 | pg-1 | pg-0 | 2.72 | 2.78 | 93 | 0 | 1 | restart only | 8.06 | k3d-pg-ha-server-0 | 0 | 2.65 | PASS |

RTO: min 2.56 s, median 2.60 s, max 2.72 s over 3 runs. Target 30 s.


## chain: Result: PASS

- **Fault:** Node failover (`docker stop` of the primary's agent), then a planned switchover back to the old primary after it has rejoined. This is the sequence that stalled WAL archiving in L3 when rejoin used `pg_rewind` (ADR-008). Archive health is checked on the returned primary.
- Details: [`L2/chain.md`](L2/chain.md)


| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| node | pg-1 | pg-0 | 24.68 | 24.80 | 168 | 0 | 1 | restart only | 43.17 | k3d-pg-ha-server-0 | 0 | 2.17 | PASS |
| switchover 1 | pg-0 | pg-2 | 2.55 | 2.64 | 94 | 0 | 1 | restart only | 7.87 | k3d-pg-ha-server-0 | 0 | 2.24 | PASS |
| switchover 2 | pg-2 | pg-1 | 2.54 | 2.66 | 93 | 0 | 1 | restart only | 7.87 | k3d-pg-ha-server-0 | 0 | 2.10 | PASS |

Second interval on `pg-1`: archived 1.39 s after a WAL fill, failed_count +0, pending .ready `-`.


## diverge: Result: PASS

- **Fault:** Diverge failover (replication from the primary blocked for a few seconds while it commits, then its node stopped), so the old primary holds WAL no replica received and must rejoin by re-clone (ADR-008). Then a planned switchover back to it, through the sync standby if needed. This is the original trigger of the L3 archiving stall. Archive health is checked on the returned primary.
- **Fault:** Replication traffic from the primary pod to both replicas is dropped by iptables on its node for 5 s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).
- Details: [`L2/diverge.md`](L2/diverge.md)


| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|
| diverge | pg-1 | pg-0 | 29.48 | 29.70 | 157 | 0 | 1 | re-clone | 55.73 | k3d-pg-ha-server-0 | 0 | 2.17 | PASS |
| switchover 1 | pg-0 | pg-2 | 2.58 | 2.65 | 94 | 0 | 1 | restart only | 7.97 | k3d-pg-ha-server-0 | 0 | 2.23 | PASS |
| switchover 2 | pg-2 | pg-1 | 2.52 | 2.63 | 94 | 0 | 1 | restart only | 7.87 | k3d-pg-ha-server-0 | 0 | 2.24 | PASS |

Second interval on `pg-1`: archived 1.52 s after a WAL fill, failed_count +0, pending .ready `-`.


## api-outage: Result: PASS

- **Fault:** `docker stop` on the k3d server container for 60 s, then `docker start`. With `failsafe_mode` off (ADR-002), every member should demote, so writes stop and reads continue. Observed by a Job on an agent node that queried each member by pod IP every second. Its log was read after the API returned, so nothing depends on `make status` or the API during the outage.
- Details: [`L2/api-outage.md`](L2/api-outage.md)


| Outage (s) | Last write during outage (s) | Rounds with no primary | Reads served | Max primaries in a round | API back (s) | Healthy again (s) | First write after (s) | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|
| 60 | +9.14 | 55 of 65 | 65 of 65 rounds | 1 | +74.11 | +114.52 | +86.13 | PASS |

Times are seconds after the server was stopped. Write unavailability lasts the whole outage plus recovery, by design.

