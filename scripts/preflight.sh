#!/usr/bin/env bash
# Read-only host checks. Changes nothing. Exits non-zero if any check fails.
. "$(dirname "$0")/lib.sh"

MIN_CPU=4; MIN_RAM_MIB=14000; MIN_AVAIL_MIB=8000; MIN_DISK_GIB=20
fails=0
ok()   { printf 'PASS  %-14s %s\n' "$1" "$2"; }
bad()  { printf 'FAIL  %-14s %s\n      fix: %s\n' "$1" "$2" "$3"; fails=$((fails+1)); }

for c in docker curl openssl sha256sum jq ss; do
  command -v "$c" >/dev/null && ok "cmd:$c" "found" || bad "cmd:$c" "not installed" "install $c"
done

v=$(cat /proc/sys/net/ipv4/ip_forward)
[ "$v" = 1 ] && ok ip_forward "1" || bad ip_forward "$v (containers lose network)" \
  "set net.ipv4.ip_forward=1 in a late /etc/sysctl.d file, then restart Docker (docs/environment.md)"

if dv=$(docker version --format '{{.Server.Version}}' 2>/dev/null); then ok docker "server $dv"
else bad docker "daemon unreachable" "start Docker and make sure your user is in the docker group"; fi

[ "$(stat -fc %T /sys/fs/cgroup)" = cgroup2fs ] && ok cgroups "v2" || bad cgroups "not v2" "use a host with cgroup v2"

n=$(nproc); [ "$n" -ge $MIN_CPU ] && ok cpu "$n vCPU (min $MIN_CPU)" || bad cpu "$n vCPU (min $MIN_CPU)" "use a larger host"

t=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo); a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
[ "$t" -ge $MIN_RAM_MIB ] && ok ram "$t MiB total (min $MIN_RAM_MIB)" || bad ram "$t MiB total (min $MIN_RAM_MIB)" "use a larger host"
if cluster_running=$(docker ps -q --filter "label=k3d.cluster=$CLUSTER_NAME" 2>/dev/null) && [ -n "$cluster_running" ]; then
  ok ram-available "$a MiB (cluster already running, minimum not applied)"
elif [ "$a" -ge $MIN_AVAIL_MIB ]; then ok ram-available "$a MiB (min $MIN_AVAIL_MIB)"
else bad ram-available "$a MiB (min $MIN_AVAIL_MIB)" "stop other workloads"; fi

d=$(df -BG --output=avail "$ROOT_DIR" | tail -1 | tr -dc 0-9)
[ "$d" -ge $MIN_DISK_GIB ] && ok disk "$d GiB free (min $MIN_DISK_GIB)" || bad disk "$d GiB free (min $MIN_DISK_GIB)" "free disk space"

if ss -ltnH "sport = :$API_PORT" | grep -q .; then
  if [ -n "${cluster_running:-}" ]; then ok "port:$API_PORT" "in use by this project's cluster"
  else bad "port:$API_PORT" "in use by another process" "free the port (Kubernetes API of the k3d cluster)"; fi
else ok "port:$API_PORT" "free"; fi

[ "$fails" -eq 0 ] || { printf '\nPreflight FAILED: %d check(s).\n' "$fails"; exit 1; }
printf '\nPreflight passed.\n'
