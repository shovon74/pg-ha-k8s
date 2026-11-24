# L2: failover, switchover and split-brain

Generated from the per-mode files in [`L2/`](L2/) each time a mode runs. Timestamps are UTC.

RTO is fault injection to the first commit acknowledged by a new primary, measured by a probe Job writing through pg-rw every 500 ms over new connections with a 2 s connect timeout. RPO is the number of acknowledged rows missing on the new primary. The target is RTO at most 30 s with safe settings (ttl 20, loop_wait 3, retry_timeout 5).

## pod: Result: PASS

- **Fault:** `kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.
- Details: [`L2/pod.md`](L2/pod.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 3.15 | 2.64 | 134 | 0 | 1 | restart only | 7.92 | PASS |
| 2 | pg-0 | pg-1 | 3.08 | 3.02 | 132 | 0 | 1 | restart only | 8.16 | PASS |
| 3 | pg-1 | pg-2 | 3.88 | 2.89 | 133 | 0 | 1 | pg_rewind | 9.68 | PASS |

RTO: min 3.08 s, median 3.15 s, max 3.88 s over 3 runs. Target 30 s.


## node: Result: PASS

- **Fault:** `docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.
- Details: [`L2/node.md`](L2/node.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 21.91 | 21.87 | 174 | 0 | 1 | pg_rewind | 46.11 | PASS |
| 2 | pg-0 | pg-1 | 22.62 | 22.66 | 146 | 0 | 1 | pg_rewind | 91.02 | PASS |
| 3 | pg-1 | pg-2 | 23.35 | 23.16 | 169 | 0 | 1 | pg_rewind | 57.79 | PASS |

RTO: min 21.91 s, median 22.62 s, max 23.35 s over 3 runs. Target 30 s.


## storage: Result: PASS

- **Fault:** The primary's data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container's mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.
- Details: [`L2/storage.md`](L2/storage.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 2.44 | 2.66 | 213 | 0 | 1 | pg_rewind | 20.95 | PASS |
| 2 | pg-0 | pg-1 | 1.79 | 2.12 | 212 | 0 | 1 | pg_rewind | 22.17 | PASS |
| 3 | pg-1 | pg-2 | 3.94 | 4.03 | 207 | 0 | 1 | pg_rewind | 24.45 | PASS |

RTO: min 1.79 s, median 2.44 s, max 3.94 s over 3 runs. Target 30 s.


## split-brain: Result: PASS

- **Fault:** An iptables rule on the primary's node drops only the primary pod's traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.
- Details: [`L2/split-brain.md`](L2/split-brain.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-2 | pg-0 | 20.80 | 15.37 | 187 | 0 | 1 | restart only | 23.91 | PASS |
| 2 | pg-0 | pg-1 | 22.68 | 16.60 | 173 | 0 | 1 | restart only | 42.56 | PASS |
| 3 | pg-1 | pg-2 | 19.82 | 15.26 | 186 | 0 | 1 | restart only | 22.70 | PASS |

RTO: min 19.82 s, median 20.80 s, max 22.68 s over 3 runs. Target 30 s.


## switchover: Result: PASS

- **Fault:** `POST /switchover` to the leader's Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. **The REST API is unauthenticated until L6.**
- Details: [`L2/switchover.md`](L2/switchover.md)


| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | Result |
|---|---|---|---:|---:|---:|---:|---:|---|---:|---|
| 1 | pg-0 | pg-1 | 2.54 | 2.58 | 93 | 0 | 1 | pg_rewind | 8.78 | PASS |
| 2 | pg-1 | pg-2 | 1.83 | 1.85 | 95 | 0 | 1 | restart only | 8.79 | PASS |
| 3 | pg-2 | pg-0 | 2.60 | 2.63 | 93 | 0 | 1 | restart only | 9.31 | PASS |

RTO: min 1.83 s, median 2.54 s, max 2.60 s over 3 runs. Target 30 s.


## api-outage

Not run yet.
