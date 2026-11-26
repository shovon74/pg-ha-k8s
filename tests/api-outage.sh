#!/usr/bin/env bash
# L2 optional: Kubernetes API outage (ADR-002, failsafe_mode off). Stops the k3d server container for
# OUTAGE seconds (default 60), then starts it again. Expected: every member demotes, so writes stop;
# reads continue; no two members are primary at once; a leader is elected once the API returns.
#
# Observation does not use make status or the API during the outage. A Job on an agent node, started
# beforehand, asks each member by pod IP (cluster DNS runs on the server, so it is down too) every second
# whether it is in recovery, and tries one write on each. Its log is read after the API returns.
# Fault injection (D4): docker stop / docker start of the k3d server container. No exec is used.
. "$(dirname "$0")/lib.sh"
OUTAGE=${OUTAGE:-60}; [[ "$OUTAGE" =~ ^[0-9]+$ ]] || die "OUTAGE must be seconds"
SERVER="k3d-$CLUSTER_NAME-server-0"; EV_FILE="$EV_DIR/L2/api-outage.md"; mkdir -p "$EV_DIR/L2"
W=$(mktemp -d); STOPPED=0
cleanup() { [ $STOPPED = 0 ] || docker start "$SERVER" >/dev/null 2>&1 || true; rm -rf "$W" "$BODY" "$CHECKS"; }
trap cleanup EXIT
api_up() { kubectl get --raw /readyz >/dev/null 2>&1; }

client_up
until primary_confirms; do sleep 1; done
L=$(leader); IPS=""; for m in pg-0 pg-1 pg-2; do IPS="$IPS $m=$(pod_ip "$m")"; done
RUN_ID="api-outage-$(date +%s)"; DURATION=$((OUTAGE + 150))
kubectl -n "$NS" delete job pg-api-probe --ignore-not-found --wait=true >/dev/null
sed "s|__PG_IMAGE__|$PG_IMAGE|; s|__IPS__|${IPS# }|; s|__RUN__|$RUN_ID|; s|__DURATION__|$DURATION|" <<'YAML' | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata: {name: pg-api-probe}
spec:
  backoffLimit: 0
  template:
    metadata: {labels: {app.kubernetes.io/name: pg-api-probe, pg-ha/db-client: "true"}}   # L6: NetworkPolicy client label
    spec:
      restartPolicy: Never
      nodeSelector: {pg-ha/role: db}
      securityContext: {runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: probe
        image: __PG_IMAGE__
        imagePullPolicy: IfNotPresent
        securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
        env:
        - {name: HOME, value: /tmp}
        - name: PGPASSWORD
          valueFrom: {secretKeyRef: {name: pg-credentials, key: pg-app-password}}
        command: [bash, -c]
        args:
        - |
          end=$(( $(date +%s) + __DURATION__ )); i=0
          while [ "$(date +%s)" -lt "$end" ]; do i=$((i+1))
            for kv in __IPS__; do ( m=${kv%%=*}; ip=${kv#*=}; c="host=$ip user=app dbname=app connect_timeout=2"
              r=$(timeout 3 psql "$c" -XAtqc "select pg_is_in_recovery()" 2>/dev/null) || r=x
              w=no; timeout 3 psql "$c" -XAtq -v ON_ERROR_STOP=1 -c "insert into probe (run, seq, client_ts) values ('__RUN__', $i * 10 + ${m#pg-}, now())" >/dev/null 2>&1 && w=yes
              echo "R $i $(date +%s.%N) $m ${r:-x} $w" ) & done
            sleep 1
          done; wait; echo DONE
        volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {}}]
YAML
until [ "$(kubectl -n "$NS" logs job/pg-api-probe 2>/dev/null | grep -c '^R')" -ge 15 ]; do sleep 1; done

section "API server outage"
T_STOP=$(now); docker stop "$SERVER" >/dev/null; STOPPED=1
note "Leader before: \`$L\`. Server container \`$SERVER\` stopped at $(iso "$T_STOP") UTC for ${OUTAGE} s. Members by IP: \`${IPS# }\`."
sleep "$OUTAGE"
T_START=$(now); docker start "$SERVER" >/dev/null; STOPPED=0
end=$((SECONDS + 240)); until api_up; do [ $SECONDS -lt $end ] || die "API not back after 240 s"; sleep 1; done; T_API=$(now)
client_up   # the test client runs on the server node, so it did not survive the restart
T_HEALTHY=""; end=$((SECONDS + 240)); until primary_confirms 2>/dev/null; do [ $SECONDS -lt $end ] || break; sleep 1; done
primary_confirms 2>/dev/null && T_HEALTHY=$(now); L2=$(leader)
end=$((SECONDS + DURATION + 60)); until kubectl -n "$NS" logs job/pg-api-probe 2>/dev/null | grep -q '^DONE'; do [ $SECONDS -lt $end ] || break; sleep 2; done
kubectl -n "$NS" logs job/pg-api-probe > "$W/probe.txt"
kubectl -n "$NS" delete job pg-api-probe --wait=false >/dev/null

# Rounds are grouped by round number; times are each round's first sample.
awk '$1=="R"' "$W/probe.txt" | sort -k2,2n -k4,4 > "$W/r.txt"
LAST_PRIMARY_DURING=$(awk -v a="$T_STOP" -v b="$T_START" '$3>a && $3<b && $5=="f" {print $3}' "$W/r.txt" | sort -n | tail -1)
LAST_WRITE_DURING=$(awk -v a="$T_STOP" -v b="$T_START" '$3>a && $3<b && $6=="yes" {print $3}' "$W/r.txt" | sort -n | tail -1)
FIRST_WRITE_AFTER=$(awk -v b="$T_START" '$3>b && $6=="yes" {print $3}' "$W/r.txt" | sort -n | head -1)
OUT_ROUNDS=$(awk -v a="$T_STOP" -v b="$T_START" '$3>a && $3<b {print $2}' "$W/r.txt" | sort -u | wc -l)
READ_ROUNDS=$(awk -v a="$T_STOP" -v b="$T_START" '$3>a && $3<b && $5=="t" {print $2}' "$W/r.txt" | sort -u | wc -l)
NOPRIM_ROUNDS=$(awk -v a="$T_STOP" -v b="$T_START" '$3>a && $3<b {r[$2]=1} $3>a && $3<b && $5=="f" {p[$2]=1} END {n=0; for (k in r) if (!(k in p)) n++; print n}' "$W/r.txt")
MAXP=$(awk '$5=="f" {c[$2]++} END {m=0; for (k in c) if (c[k]>m) m=c[k]; print m}' "$W/r.txt")
WRITERS=$(awk '$6=="yes" {c[$2]++} END {m=0; for (k in c) if (c[k]>m) m=c[k]; print m}' "$W/r.txt")
note "During the outage: last sample with a primary +$(secs "$T_STOP" "$LAST_PRIMARY_DURING") s, last successful write +$(secs "$T_STOP" "$LAST_WRITE_DURING") s. $READ_ROUNDS of $OUT_ROUNDS rounds had a replica answering reads, and $NOPRIM_ROUNDS rounds had no primary at all. API back at +$(secs "$T_STOP" "$T_API") s, healthy with leader \`$L2\` at +$(secs "$T_STOP" "$T_HEALTHY") s, first write after restart +$(secs "$T_STOP" "$FIRST_WRITE_AFTER") s."
run "awk -v a=$T_STOP '\$3>a-3' $W/r.txt | awk '{printf \"%s round=%s %s in_recovery=%s write=%s\\n\", strftime(\"%H:%M:%S\", \$3, 1), \$2, \$4, \$5, \$6}' | awk 'NR%3==1 || /write=yes/' | head -40" || true
check "Every member demoted during the outage (writes stopped)" test -n "$LAST_WRITE_DURING" -a "$NOPRIM_ROUNDS" -gt 0
check "Demotion within 20 s of the outage starting (ttl)" awk -v d="$(secs "$T_STOP" "$LAST_WRITE_DURING")" 'BEGIN{exit !(d != "n/a" && d <= 20)}'
check "Reads continued on replicas in every outage round" test "$READ_ROUNDS" = "$OUT_ROUNDS"
check "Never more than 1 primary in any round" test "$MAXP" -le 1
check "Never more than 1 member accepted a write in any round" test "$WRITERS" -le 1
check "A leader was elected and replication healthy after the API returned" test -n "$T_HEALTHY"

verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
{ printf '# L2 failure mode: api-outage\n\n**Result: %s**\n\n' "$verdict"
  printf -- '- **Fault:** `docker stop` on the k3d server container for %s s, then `docker start`. With `failsafe_mode` off (ADR-002), every member should demote, so writes stop and reads continue. Observed by a Job on an agent node that queried each member by pod IP every second. Its log was read after the API returned, so nothing depends on `make status` or the API during the outage.\n' "$OUTAGE"
  printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make test-api-outage`\n- **Versions:** k3s `%s`, image `%s`\n' "$STARTED" "$((SECONDS-T0))" "${K3S_IMAGE%%@*}" "$PG_IMAGE"
  printf '\n## Summary\n\n| Outage (s) | Last write during outage (s) | Rounds with no primary | Reads served | Max primaries in a round | API back (s) | Healthy again (s) | First write after (s) | Result |\n|---:|---:|---:|---|---:|---:|---:|---:|---|\n'
  printf '| %s | +%s | %s of %s | %s of %s rounds | %s | +%s | +%s | +%s | %s |\n\n' "$OUTAGE" "$(secs "$T_STOP" "$LAST_WRITE_DURING")" "$NOPRIM_ROUNDS" "$OUT_ROUNDS" "$READ_ROUNDS" "$OUT_ROUNDS" "$MAXP" "$(secs "$T_STOP" "$T_API")" "$(secs "$T_STOP" "$T_HEALTHY")" "$(secs "$T_STOP" "$FIRST_WRITE_AFTER")" "$verdict"
  printf 'Times are seconds after the server was stopped. Write unavailability lasts the whole outage plus recovery, by design.\n\n## Checks\n\n| Check | Result |\n|---|---|\n'
  cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_FILE"
"$ROOT_DIR/tests/l2-summary.sh"
log "RESULT L2 api-outage: $verdict -> docs/evidence/L2/api-outage.md"
[ "$FAILS" -eq 0 ]
