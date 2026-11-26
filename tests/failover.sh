#!/usr/bin/env bash
# L2 failure harness (R3.1-R3.7, R6.3, ADR-006). Usage: tests/failover.sh pod|node|storage|split-brain|switchover|diverge
#   RUNS=n (default 3, switchover 1), TO=pg-N (switchover target, default the current sync standby)
#   EV_OUT=path writes the evidence there instead of docs/evidence/L2/<mode>.md, and leaves L2-failover.md alone
#   (used by L3 to fault the cluster without replacing the L2 results).
#
# RTO = fault injection to the first commit acknowledged by a new primary, seen by the probe Job
# (tests/probe-job.yaml), which writes through pg-rw every 500 ms. RPO = acknowledged sequence numbers
# missing on the new primary. Leadership is sampled twice every 500 ms: the lock holder from the pg-rw
# Endpoints object, and pg_is_in_recovery() asked of each member directly.
#
# Fault injection (D4, committed and documented):
#   pod          kubectl delete pod <primary> (default grace period, so Patroni shuts down normally)
#   node         docker stop <agent hosting the primary>, then docker start once a new leader holds the lock
#   storage      docker exec <agent>: lazily unmount /data inside the primary container's mount namespace, so
#                the volume is gone from that container, then SIGKILL the postmaster, standing in for the
#                I/O error a lost disk causes. Restored by deleting the pod once a new leader holds the lock,
#                so the kubelet mounts the volume again. See the evidence file for the limits.
#   split-brain  docker exec <agent> iptables: drop the primary pod's traffic to the API server backend only.
#                Pod-to-pod traffic, including replication, is untouched. The rule is removed afterwards.
#   diverge      (L4, ADR-008) docker exec <agent> iptables: drop replication traffic from the primary pod to
#                both replicas (source port 5432) for DIVERGE_HOLD s (default 5) while the probe writes, so
#                the primary writes WAL that no replica receives. Then docker stop the agent, as in node mode.
#                The new primary is promoted behind the old one, so the old primary has diverged and must
#                rejoin by re-clone. The rules go with the stopped container and are deleted again anyway.
#   switchover   POST /switchover to the leader's Patroni REST API over kubectl port-forward and curl, with
#                basic auth (L6). The credential is read from ./secrets and handed to curl on stdin (-K -), so
#                it never appears on a command line or in the evidence. The API server pod proxy is not used
#                for this POST because Patroni rejects its request without a Content-Length header (HTTP 411).
# psql runs only in the test client pod, never in a Postgres pod.
#
# After every run (L3): WAL archive health on the current primary. Its pg_stat_archiver.failed_count must not
# have grown since before the fault, and after a WAL fill a segment must be archived within ARCHIVE_BOUND
# (archive_timeout 60 s + 30 s margin). CoreDNS placement is recorded per run. A run whose RTO is over the
# 30 s target is reported as OVER TARGET, never as PASS, and the script then exits non-zero.
. "$(dirname "$0")/lib.sh"
MODE=${1:-}; case "$MODE" in pod|node|storage|split-brain|switchover|diverge) ;; *) die "usage: $0 pod|node|storage|split-brain|switchover|diverge" ;; esac
RUNS=${RUNS:-$([ "$MODE" = switchover ] && echo 1 || echo 3)}
[[ "$RUNS" =~ ^[1-9]$ ]] || die "RUNS must be 1-9"
case "$MODE" in pod) DURATION=70 ;; switchover) DURATION=50 ;; *) DURATION=110 ;; esac
DIVERGE_IPS=""
W=$(mktemp -d); mkdir -p "$EV_DIR/L2"; EV_FILE="${EV_OUT:-$EV_DIR/L2/$MODE.md}"
PENDING_RESTORE=""; SAMPLER_PIDS=""

restore_fault() {
  case "$PENDING_RESTORE" in
    node:*) docker start "${PENDING_RESTORE#node:}" >/dev/null 2>&1 || true
            for ip in ${DIVERGE_IPS:-}; do docker exec "${PENDING_RESTORE#node:}" iptables -D FORWARD -s "$OLD_IP" -d "$ip" -p tcp --sport 5432 -j DROP >/dev/null 2>&1 || true; done ;;
    storage:*) kubectl -n "$NS" delete pod "${PENDING_RESTORE#storage:}" --wait=false >/dev/null 2>&1 || true ;;
    split:*) set -- ${PENDING_RESTORE#split:}; docker exec "$1" iptables -D FORWARD -s "$2" -d "$3" -p tcp --dport "$4" -j DROP >/dev/null 2>&1 || true ;;
  esac
  PENDING_RESTORE=""
}
stop_samplers() { [ -z "$SAMPLER_PIDS" ] || kill $SAMPLER_PIDS 2>/dev/null || true; wait $SAMPLER_PIDS 2>/dev/null || true; SAMPLER_PIDS=""; }
cleanup() {
  restore_fault; stop_samplers
  kubectl -n "$NS" delete job pg-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  rm -rf "$W" "$BODY" "$CHECKS"
}
trap cleanup EXIT

wait_until() { # timeout-seconds command...
  local end=$((SECONDS + $1)); shift
  until "$@" >/dev/null 2>&1; do [ $SECONDS -lt $end ] || return 1; sleep 0.5; done
}
leader_is_not() { local l; l=$(leader); [ -n "$l" ] && [ "$l" != "$1" ]; }
leader_is() { [ "$(leader)" = "$1" ]; }
pod_uid() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null; }
uid_changed() { local u; u=$(pod_uid "$1"); [ -n "$u" ] && [ "$u" != "$2" ]; }
ts_of_log() { # "YYYY-MM-DD HH:MM:SS,mmm" or "YYYY-MM-DD HH:MM:SS.mmm UTC" at line start -> epoch
  sed -E 's/^([0-9-]+ [0-9:]+)[.,]([0-9]+).*/\1.\2 UTC/' | head -1 | xargs -r -I{} date -d {} +%s.%N
}
container_pid() { # agent pod -> host-visible PID of the Postgres container, via crictl on that node
  local id; id=$(docker exec "$1" crictl ps -q --name postgres --label "io.kubernetes.pod.name=$2" --label "io.kubernetes.pod.namespace=$NS")
  docker exec "$1" crictl inspect -o go-template --template '{{.info.pid}}' "$id"
}

client_up
kubectl get ns "$NS" >/dev/null 2>&1 || die "namespace $NS not found, run: make up"
SUMMARY=$(mktemp -p "$W")
printf '| Run | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |\n|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|\n' > "$SUMMARY"
RTOS=""; OVER=0; TARGET_RTO=30

for N in $(seq 1 "$RUNS"); do
  R="$W/run$N"; mkdir -p "$R"; run_fails=$FAILS
  section "Run $N"
  wait_until 240 primary_confirms || die "cluster not healthy before run $N, see: make status"
  sleep 3
  OLD=$(leader); OLD_IP=$(pod_ip "$OLD"); OLD_NODE=$(pod_node "$OLD"); OLD_UID=$(pod_uid "$OLD")
  SYNC=$(sync_standby); TL0=$(patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline')
  TARGET=${TO:-$SYNC}
  CDNS=$(coredns_nodes)
  declare -A FC0=(); for m in pg-0 pg-1 pg-2; do FC0[$m]=$(archive_stat "$(member "$m")" 2>/dev/null | awk '{print $1}'); done
  [ "$MODE" != switchover ] || [ "$TARGET" != "$OLD" ] || die "switchover target $TARGET is already the leader"
  RUN_ID="$MODE-$N-$(date +%s)"

  # Probe, then samplers. Nothing is deployed or reconfigured during the measured window.
  kubectl -n "$NS" delete job pg-probe --ignore-not-found --wait=true >/dev/null
  sed "s|__PG_IMAGE__|$PG_IMAGE|; s|__RUN_ID__|$RUN_ID|; s|__DURATION__|$DURATION|" "$ROOT_DIR/tests/probe-job.yaml" | kubectl -n "$NS" apply -f - >/dev/null
  wait_until 90 bash -c "[ \$(kubectl -n $NS logs job/pg-probe 2>/dev/null | grep -c '^ACK') -ge 6 ]" || die "probe did not start acknowledging writes"
  ( while :; do echo "L $(now) $(lock)"; sleep 0.5; done ) > "$R/lock.txt" 2>/dev/null & SAMPLER_PIDS="$!"
  kubectl -n "$NS" exec "$CLIENT" -- sh -c 'end=$(( $(date +%s) + 600 )); i=0
    while [ "$(date +%s)" -lt "$end" ]; do i=$((i+1))
      for m in pg-0 pg-1 pg-2; do ( r=$(PGPASSWORD=$MON_PW psql "host=$m.pg-headless.pg-ha.svc.cluster.local user=monitor dbname=app connect_timeout=2" -XAtqc "select pg_is_in_recovery()" 2>/dev/null) || r=x; echo "S $i $(date +%s.%N) $m ${r:-x}" ) & done
      sleep 0.5; done' > "$R/samples.txt" 2>/dev/null & SAMPLER_PIDS="$SAMPLER_PIDS $!"
  sleep 2

  # Fault.
  case "$MODE" in
    pod) T_FAULT=$(now); kubectl -n "$NS" delete pod "$OLD" --wait=false >/dev/null ;;
    node) T_FAULT=$(now); docker stop "$OLD_NODE" >/dev/null; PENDING_RESTORE="node:$OLD_NODE" ;;
    diverge)
      DIVERGE_IPS=""; for m in pg-0 pg-1 pg-2; do [ "$m" = "$OLD" ] || DIVERGE_IPS="$DIVERGE_IPS $(pod_ip "$m")"; done
      T_FAULT=$(now); PENDING_RESTORE="node:$OLD_NODE"
      for ip in $DIVERGE_IPS; do docker exec "$OLD_NODE" iptables -I FORWARD 1 -s "$OLD_IP" -d "$ip" -p tcp --sport 5432 -j DROP; done
      sleep "${DIVERGE_HOLD:-5}"; T_STOP=$(now); docker stop "$OLD_NODE" >/dev/null
      note "Replication from \`$OLD\` to$(printf ' `%s`' $DIVERGE_IPS) blocked at $(iso "$T_FAULT") UTC, node stopped +$(secs "$T_FAULT" "$T_STOP") s later." ;;
    storage)
      PID=$(container_pid "$OLD_NODE" "$OLD")
      PM=$(docker exec "$OLD_NODE" sh -c "for d in /proc/[0-9]*; do [ \"\$(cut -d' ' -f4 \$d/stat 2>/dev/null)\" = $PID ] && [ \"\$(cat \$d/comm 2>/dev/null)\" = postgres ] && echo \${d#/proc/}; done; true" | head -1)
      [ -n "$PM" ] || die "postmaster of $OLD not found"
      T_FAULT=$(now); docker exec "$OLD_NODE" sh -c "nsenter -t $PID -m -p -- umount -l /data && kill -KILL $PM"
      PENDING_RESTORE="storage:$OLD" ;;
    split-brain)
      API=$(kubectl get endpointslice -n default -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].endpoints[0].addresses[0]} {.items[0].ports[0].port}')
      set -- $API; API_IP=$1; API_PORT=$2
      T_FAULT=$(now); docker exec "$OLD_NODE" iptables -I FORWARD 1 -s "$OLD_IP" -d "$API_IP" -p tcp --dport "$API_PORT" -j DROP
      PENDING_RESTORE="split:$OLD_NODE $OLD_IP $API_IP $API_PORT" ;;
    switchover)
      printf '{"leader": "%s", "candidate": "%s"}' "$OLD" "$TARGET" > "$R/body.json"
      PFPORT=$((18000 + RANDOM % 1000)); kubectl -n "$NS" port-forward "pod/$OLD" "$PFPORT:8008" >/dev/null 2>&1 & PF=$!
      wait_until 10 curl -s -o /dev/null "http://127.0.0.1:$PFPORT/liveness" || true
      T_FAULT=$(now); printf 'user = "patroni:%s"\n' "$(cat "$SECRETS_DIR/credentials/pg-restapi-password")" |
        curl -sS -m 60 -K - -X POST -H 'Content-Type: application/json' --data-binary @"$R/body.json" "http://127.0.0.1:$PFPORT/switchover" > "$R/switchover.txt" 2>&1 || true
      kill $PF 2>/dev/null || true; wait $PF 2>/dev/null || true ;;
  esac
  note "Fault at $(iso "$T_FAULT") UTC on primary \`$OLD\` ($OLD_IP, node \`$OLD_NODE\`, timeline $TL0). Sync standby before: \`$SYNC\`. CoreDNS on \`$CDNS\`."
  got=0; if [ "$MODE" = switchover ]; then wait_until 90 leader_is "$TARGET" || got=1; else wait_until 120 leader_is_not "$OLD" || got=1; fi
  T_LOCK=$(now); NEW=$(leader)
  check "run $N: lock moved from $OLD to a new leader ($NEW)" test $got = 0
  if [ "$MODE" = storage ]; then
    # Proof the volume was unavailable, taken from the old container before the pod is replaced.
    sleep 3; kubectl -n "$NS" logs "$OLD" --since-time="$(date -u -d "@${T_FAULT%.*}" +%FT%TZ)" > "$R/old-before-restore.log" 2>/dev/null || true
    run "grep -iE 'No such file|does not exist|not running|failed|crash|primary_start|releas|demot|promot' $R/old-before-restore.log | head -8" || true
  fi
  restore_fault; T_RESTORE=$(now)

  # Rejoin: a new pod where one is expected, then confirmed from the primary, not from Patroni alone.
  case "$MODE" in pod|storage) wait_until 180 uid_changed "$OLD" "$OLD_UID" || true ;; esac
  rj=0; wait_until 300 primary_confirms "$OLD" || rj=1; T_REJOIN=$(now)
  wait_until $((DURATION + 60)) bash -c "kubectl -n $NS logs job/pg-probe 2>/dev/null | grep -q '^DONE'" || true
  stop_samplers
  kubectl -n "$NS" logs job/pg-probe > "$R/probe.txt" 2>/dev/null || true
  NEW_IP=$(pod_ip "$NEW")

  # Analysis.
  FIRST_NEW=$(awk -v ip="$OLD_IP" -v t="$T_FAULT" '$1=="ACK" && $5!=ip && $4>t {print $4}' "$R/probe.txt" | sort -n | head -1)
  LAST_OLD=$(awk -v ip="$OLD_IP" '$1=="ACK" && $5==ip {print $4}' "$R/probe.txt" | sort -n | tail -1)
  PREV=$(awk -v f="${FIRST_NEW:-0}" '$1=="ACK" && $4<f {print $4}' "$R/probe.txt" | sort -n | tail -1)
  RTO=$(secs "$T_FAULT" "$FIRST_NEW"); GAP=$(secs "$PREV" "$FIRST_NEW")
  OVERLAP=$(awk -v ip="$OLD_IP" -v f="${FIRST_NEW:-9e99}" '$1=="ACK" && $5==ip && $4>f' "$R/probe.txt" | wc -l)
  ACKED=$(awk '$1=="ACK" {print $2}' "$R/probe.txt" | sort -n | paste -sd, -)
  NACK=$(awk '$1=="ACK"' "$R/probe.txt" | wc -l); NERR=$(awk '$1=="ERR"' "$R/probe.txt" | wc -l)
  FOUND=$( [ -n "$ACKED" ] && q "$RW" app "select count(*) from probe where run = '$RUN_ID' and seq in ($ACKED)" || echo 0)
  MISSING=$((NACK - ${FOUND:-0}))
  MAXP=$(awk '$1=="S" && $5=="f" {c[$2]++} END {m=0; for (k in c) if (c[k]>m) m=c[k]; print m}' "$R/samples.txt")
  NTICKS=$(awk '$1=="S" {print $2}' "$R/samples.txt" | sort -u | wc -l)
  HOLDERS=$(awk '$1=="L" && NF>=3 {print $3}' "$R/lock.txt" | uniq | paste -sd'>' -)
  case "$MODE" in pod|storage) LOGARGS="$OLD" ;; *) LOGARGS="$OLD --since-time=$(date -u -d "@${T_FAULT%.*}" +%FT%TZ)" ;; esac
  kubectl -n "$NS" logs $LOGARGS > "$R/old.log" 2>/dev/null || true
  if grep -qiE 'Removing data directory|replica has been created using basebackup|bootstrap from leader|reinitializing due to diverged timelines' "$R/old.log"; then REJOIN="re-clone"
  elif grep -qiE 'running pg_rewind|pg_rewind.*(success|done)' "$R/old.log"; then REJOIN="pg_rewind"
  else REJOIN="restart only"; fi
  TL1=$(patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline')
  OLD_TL=$(patroni_cluster | jq -r --arg o "$OLD" '.members[] | select(.name == $o) | .timeline')

  note "Probe: $NACK acknowledged, $NERR failed attempts. Lock holders sampled: \`$HOLDERS\`. Leadership samples: $NTICKS rounds of 3 members."
  note "First acknowledged write on the new primary at $( [ -n "$FIRST_NEW" ] && iso "$FIRST_NEW" || echo none) UTC. Last on the old primary at $( [ -n "$LAST_OLD" ] && iso "$LAST_OLD" || echo none) UTC. Timeline $TL0 -> $TL1. Fault restored at $(iso "$T_RESTORE"), old member streaming from the new primary at $(iso "$T_REJOIN") UTC."
  run "grep -iE 'rewind|basebackup|diverged|Removing data|bootstrap from leader|Demoting|demote|promot|shut down|immediate shutdown|read-only|PANIC' $R/old.log | sed -E 's/[0-9a-f]{32,}/[hex]/g' | head -12" || true
  [ "$MODE" != switchover ] || run "cat $R/switchover.txt" || true
  check "run $N: writes resumed on the new primary (RTO $RTO s)" test -n "$FIRST_NEW"
  check "run $N: RPO 0, all $NACK acknowledged rows present on the new primary" test "$MISSING" = 0
  check "run $N: never more than 1 member out of recovery in any sample" test "$MAXP" -le 1
  check "run $N: no acknowledged write on the old primary after the new primary's first" test "$OVERLAP" = 0
  check "run $N: old primary $OLD rejoined as a streaming replica of $NEW, sync standby restored" test $rj = 0
  check "run $N: old primary in recovery on the new leader's timeline" bash -c "[ \"\$(q $(member "$OLD") monitor 'select pg_is_in_recovery()')\" = t ] && [ '$OLD_TL' = '$TL1' ]"

  if [ "$MODE" = split-brain ]; then
    # ADR-006: demotion must complete before the old lock can expire (last renewal + ttl 20 s).
    LAST_RENEW=$(awk -v o="$OLD" '$1=="L" && $3==o {print $4}' "$R/lock.txt" | sort | tail -1 | xargs -r -I{} date -d {} +%s.%N)
    ACQ=$(lock | awk '{print $3}' | xargs -r -I{} date -d {} +%s.%N)
    T_DEMOTE=$(grep -iE 'demot' "$R/old.log" | head -1 | ts_of_log)
    T_STOPPED=$(grep -E 'database system is shut down' "$R/old.log" | head -1 | ts_of_log)
    note "Last lock renewal by $OLD: $( [ -n "$LAST_RENEW" ] && iso "$LAST_RENEW") UTC. Demotion issued +$(secs "$LAST_RENEW" "$T_DEMOTE") s (bound 13 s). Postgres stopped +$(secs "$LAST_RENEW" "$T_STOPPED") s. Last acknowledged write on the old primary +$(secs "$LAST_RENEW" "$LAST_OLD") s. New leader $NEW acquired the lock +$(secs "$LAST_RENEW" "$ACQ") s (ttl 20 s)."
    check "run $N: demotion issued within 13 s of the last renewal" awk -v d="$(secs "$LAST_RENEW" "$T_DEMOTE")" 'BEGIN{exit !(d != "n/a" && d <= 13.5)}'
    check "run $N: old primary stopped within 20 s of the last renewal (13 s + 7 s stop budget)" awk -v d="$(secs "$LAST_RENEW" "$T_STOPPED")" 'BEGIN{exit !(d != "n/a" && d <= 20)}'
    check "run $N: old primary's last acknowledged write precedes the new leader's lock acquisition" awk -v a="${LAST_OLD:-0}" -v b="${ACQ:-0}" 'BEGIN{exit !(b > 0 && a < b)}'
  fi
  check "run $N: CoreDNS was not on the faulted primary's node ($OLD_NODE)" bash -c "! grep -qw -- '$OLD_NODE' <<<'$CDNS'"

  # Archive health on the current primary (L3). Failures counted against its own value before the fault.
  CUR=$(leader); archive_check "$(member "$CUR")" "${FC0[$CUR]:-0}" "$ARCHIVE_BOUND"
  note "Archive health on primary \`$CUR\`: failed_count $((${FC0[$CUR]:-0})) before the fault, +$ARCH_FAILED since. After a WAL fill, a segment was archived in $ARCH_T s (bound $ARCHIVE_BOUND s). Last archived \`$(awk '{print $3}' <<<"$ARCH_STAT")\`. Pending .ready: $(awk '{print $4, "(" $5 ")"}' <<<"$ARCH_STAT")."
  check "run $N: no new archive failures on the primary $CUR" test "$ARCH_FAILED" -le 0
  check "run $N: the primary archived a segment within $ARCHIVE_BOUND s of a WAL fill" test "$ARCH_T" != n/a

  res=PASS; [ $FAILS -eq $run_fails ] || res=FAIL
  if [ "$res" = PASS ] && awk -v r="$RTO" -v t="$TARGET_RTO" 'BEGIN{exit !(r == "n/a" || r > t)}'; then res="OVER TARGET"; OVER=$((OVER + 1)); fi
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$N" "$OLD" "$NEW" "$RTO" "$GAP" "$NACK" "$MISSING" "$MAXP" "$REJOIN" "$(secs "$T_FAULT" "$T_REJOIN")" "$CDNS" "$ARCH_FAILED" "$ARCH_T" "$( [ "$res" = PASS ] && echo PASS || echo "**$res**")" >> "$SUMMARY"
  RTOS="$RTOS $RTO"
  log "run $N: RTO=$RTO s gap=$GAP s acked=$NACK missing=$MISSING maxprimaries=$MAXP rejoin=$REJOIN coredns=$CDNS archfail=+$ARCH_FAILED archived=${ARCH_T}s $res"
done

# Evidence file for this mode, then the combined L2 summary.
verdict=PASS; [ "$OVER" -eq 0 ] || verdict="OVER TARGET"; [ "$FAILS" -eq 0 ] || verdict=FAIL
STATS=$(tr ' ' '\n' <<<"$RTOS" | { grep -E '^[0-9.]+$' || true; } | sort -n | awk '{a[NR]=$1} END {if (NR) printf "min %.2f s, median %.2f s, max %.2f s over %d runs", a[1], (NR%2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2), a[NR], NR; else print "no RTO measured"}')
case "$MODE" in
  pod) DESC='`kubectl delete pod` on the primary, with the default grace period. Patroni shuts Postgres down and releases the lock, so this measures a clean handover. An abrupt death is covered by the node mode.' ;;
  node) DESC='`docker stop` on the k3d agent container hosting the primary (D6), restarted with `docker start` once a new leader holds the lock. Every process on that node dies, so the lock must expire (ttl 20 s) before a replica can take over.' ;;
  storage) DESC='The primary'"'"'s data volume is made unavailable inside its container: `/data` is lazily unmounted in the Postgres container'"'"'s mount namespace (`docker exec <agent> nsenter -t <pid> -m umount -l /data`) and the postmaster is killed with SIGKILL, so Patroni cannot restart Postgres. It is restored by deleting the pod once a new leader holds the lock, so the kubelet mounts the volume again. **Limits:** a running Postgres does not notice a detached directory because it works relative to its open data directory, so the SIGKILL stands in for the I/O error or PANIC a real disk failure would cause. The data on the volume is intact, so this is not a lost or corrupted disk, and a hung disk that blocks I/O without failing is not shown. A read-only remount was tried first and refused (`mount point is busy`), because Postgres holds its files open for writing.' ;;
  split-brain) DESC='An iptables rule on the primary'"'"'s node drops only the primary pod'"'"'s traffic to the API server backend (the S2 finding: policy and filtering see the real backend address). Replication and client traffic are untouched, so the old primary can still reach its sync standby and acknowledge commits until it demotes itself. The rule is removed afterwards.' ;;
  diverge) DESC='Replication traffic from the primary pod to both replicas is dropped by iptables on its node for '"${DIVERGE_HOLD:-5}"' s while the probe writes, so the primary writes WAL (commits that wait for the sync standby and are never acknowledged) that no replica receives. Then its k3d agent is stopped, as in the node mode, and started again once a new leader holds the lock. RTO counts from the start of the block. The old primary has diverged and must rejoin by re-clone (ADR-008).' ;;
  switchover) DESC='`POST /switchover` to the leader'"'"'s Patroni REST API over `kubectl port-forward` and `curl`, naming the target (default the current sync standby). No exec is used. The API server pod proxy was tried first and refused with HTTP 411, because Patroni requires a Content-Length header that the proxy does not forward. Since L6 the POST carries basic auth (user `patroni`, password from `./secrets`, passed to curl on stdin); unauthenticated state-changing requests are refused (`make test-security`).' ;;
esac
{ printf '# L2 failure mode: %s\n\n**Result: %s**\n\n' "$MODE" "$verdict"
  printf -- '- **Fault:** %s\n' "$DESC"
  printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make %s`\n' "$STARTED" "$((SECONDS-T0))" "$([ "$MODE" = switchover ] && echo switchover || ([ "$MODE" = split-brain ] && echo test-split-brain || echo "failover-$MODE"))"
  printf -- '- **Versions:** k3s `%s`, image `%s`\n' "${K3S_IMAGE%@*}" "$PG_IMAGE"
  printf -- '- **Method:** RTO is fault injection to the first commit acknowledged by a new primary, from a probe writing through pg-rw every 500 ms. Write gap is the last acknowledged write before that to the first after it. RPO counts acknowledged rows missing on the new primary.\n'
  printf '\n## Summary\n\n%s\n\nRTO: %s. Target 30 s%s.\n\n## Checks\n\n| Check | Result |\n|---|---|\n' "$(cat "$SUMMARY")" "$STATS" "$( [ "$OVER" -eq 0 ] || echo ": **$OVER run(s) OVER TARGET**")"
  cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_FILE"

[ -n "${EV_OUT:-}" ] || "$ROOT_DIR/tests/l2-summary.sh"
log "RESULT L2 $MODE: $verdict ($STATS) -> ${EV_FILE#$ROOT_DIR/}"
[ "$FAILS" -eq 0 ] && [ "$OVER" -eq 0 ]
