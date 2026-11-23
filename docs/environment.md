# Environment check

**Checked:** 2026-11-22 (UTC), using read-only commands. Container networking was tested on 2026-11-22 and re-tested on 2026-11-23 (UTC) with lead-approved throwaway containers, which were removed along with their test image. The lead applied the host networking fix. The agent changed no host setting or tool.
**Privacy:** Project number, internal IPs and usernames are intentionally left out because this repo goes to reviewers.

## Verdict

**Yes, by planning estimate, this machine can run a 4-node local cluster (1 server, 3 agents) with 3 Postgres pods, Garage (ADR-014) and a plain Prometheus and Alertmanager stack.** Container networking now works. Memory limits are required and heavy tests must not overlap.

One item remains for the build:

- **Fix: kubectl version skew.** System kubectl is v1.37.2 and k3d's default k3s is v1.35.5, which is outside Kubernetes' supported ±1 skew. `versions.env` now pins kubectl and k3s to v1.35.10, and `make tools` will install them in L0. See [Tool pinning](#tool-pinning).

## Machine

| Item | Value |
|---|---|
| Instance | GCP e2-standard-4, not preemptible, auto-restart on, live-migrates on host maintenance |
| OS | Ubuntu 24.04.5 LTS |
| Kernel | 7.0.0-1017-gcp, x86_64 |
| CPU | 4 vCPU (2 cores, 2 threads each), Intel Xeon 2.20 GHz |
| RAM | 15.6 GiB total, about 14 GiB available |
| Swap | None |
| Disk | 48 GiB ext4 root on a balanced persistent disk, **44 GiB free** |
| cgroups | v2, systemd driver |
| Docker state | 0 containers, 0 volumes, no daemon.json. One image not created by the agent is present (`busybox:latest`), and the project must not depend on it |
| Kubernetes state | No k3d clusters, no kubeconfig contexts |

## Tools

| Tool | Version | Status |
|---|---|---|
| docker | 29.10.0 (client and server) | OK, user is in the `docker` group |
| kubectl | v1.37.2 (Kustomize v5.8.1) | **Skew against k3s default** |
| k3d | v5.9.0 (default k3s v1.35.5-k3s1) | OK |
| kind | Not installed | Not needed if we use k3d |
| helm | v3.22.1 | Installed, not needed under decision D2 |
| make | 4.3 | OK |
| git | 2.43.0 | OK |
| jq | 1.7 | OK |

Not requested but likely useful, and all missing: `yq`, `psql`, `mc`, `shellcheck`, `kubeconform`. Whether we need them is a Phase 1 decision.

## Host readiness

| Check | Result | Assessment |
|---|---|---|
| inotify instances / watches | 512 / 524288 | OK for a multi-node cluster |
| `vm.max_map_count` | 1048576 | OK |
| Open file limit | 1048576 | OK |
| Kernel modules | `overlay`, `ip_tables`, `xt_conntrack` loaded; `nf_conntrack` built in; `br_netfilter`, `iptable_nat` available | OK |
| iptables | 1.8.10 (nf_tables) | OK |
| Transparent huge pages | `madvise` | OK for Postgres |
| IP forwarding | 1, set by `/etc/sysctl.d/99-k8s.conf` | OK. Persistence across a reboot not tested |
| Firewall | `ufw` active. Its rules could not be read without root | Does not block the tested container egress |
| Registries | Docker Hub, GHCR, Quay and registry.k8s.io all reachable from the host (HTTP 401 on `/v2/`) | OK. A pull from Docker Hub succeeded |

## Container networking test

Run with `busybox:1.37.0` on the default Docker bridge.

| Check from inside the container | Before fix (2026-11-22) | After fix (2026-11-23) |
|---|---|---|
| `ping -c1 -W5 8.8.8.8` | **Failed**, 100% packet loss | Passed, 0% loss, 1.7 ms |
| `nslookup registry.k8s.io` | **Failed**, no servers reached | Passed, name resolved |
| HTTPS request | **Failed**, name not resolved | Passed, HTTP 204 from `google.com/generate_204` and HTTP 401 from `registry.k8s.io/v2/` |
| Test container and image removed | Passed | Passed |

BusyBox `wget` does not validate TLS certificates, so the HTTPS check proves connectivity only.

**Root cause (as diagnosed by the lead):** the GCE image's `/etc/sysctl.d/60-gce-network-security.conf` sets `net.ipv4.ip_forward=0`. An earlier `sysctl --system` re-applied that value after Docker had started, which turned off the forwarding that bridge-networked containers need.

**Fix (applied by the lead):** added `net.ipv4.ip_forward=1` to `/etc/sysctl.d/99-k8s.conf`, which loads after the GCE file, and restarted Docker. The kernel now reports `ip_forward=1`.

**Phase 2 follow-up:** add a `make preflight` target that runs before `make up` and checks host prerequisites: `ip_forward`, Docker, CPU, RAM and disk. A reviewer on a similar image then gets a clear message early instead of a confusing cluster failure.

## Tool pinning

Decided in ADR-013. `versions.env` exists, and `make tools` is not built yet.

- `versions.env` is the single source of truth for the k3s image, kubectl and every other pinned component.
- `make tools` downloads those exact versions into a git-ignored `./bin`, and verifies checksums where upstream publishes them.
- Project commands use `./bin` first, so system tools are left unchanged.
- kubectl is pinned to the same minor version as k3s.

## Capacity estimate

These are **planning estimates, not measurements**. Phase 1 should replace them with observed usage. They are upper bounds: the reference machine is 4 vCPU and 16 GB (D7), the deployment keeps a reduced footprint, and the 100–200 MB dataset (D8) should need less disk than shown.

| Component | Memory (GiB) | Disk (GiB) |
|---|---:|---:|
| Host OS and Docker | 1.0 | already counted as used |
| 4 k3s nodes (1 server, 3 agents) | 2.7 | 8.0 (with images) |
| 3 Postgres pods with HA agent | 3.0 | 9.0 |
| Garage (budget, not measured) | 0.5 | 8.0 |
| Prometheus | 1.0 | 2.0 |
| Alertmanager, exporters | 0.65 | 0.5 |
| Backup job (transient) | 0.5 | n/a |
| Restore-test instance (transient) | 1.0 | 3.0 |
| **Peak total** | **10.35 of 15.6** | **30.5 of 44 free** |

That leaves about 5 GiB of memory and 13 GiB of disk as headroom.

## Constraints this machine puts on the project

- **CPU is the tightest resource.** Four vCPUs are 2 physical cores. Running a base backup, restore test and load generator together could distort RTO measurements, so timing tests should run alone.
- **No swap.** Exceeding memory triggers the OOM killer, so every workload needs memory limits.
- **All "nodes" share one VM, kernel and disk.** Node failure is simulated, and a real VM or disk failure would take out the whole cluster. This must appear under known limitations.
- **Disk pressure is shared.** Runaway WAL in one pod consumes space for all nodes and can trigger kubelet evictions cluster-wide. Local volumes may not enforce PVC size limits, which must be checked before relying on them for the R1.6 test.
- **Disk performance was not measured**, because a meaningful `fsync` test writes to disk. It affects commit latency and failover timing.
