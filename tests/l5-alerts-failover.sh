#!/usr/bin/env bash
# L5 R10.3, scenario a: node failover. The primary's k3d agent is stopped for DOWN s (default 180), then started.
# Expected in Alertmanager: MemberDown (the old primary), ReplicaNotStreaming and FailoverOccurred fire, then all
# three resolve after the node returns and the member rejoins. NoPrimary and MultiplePrimaries must stay silent,
# because Patroni fails over within 45 s (L2: 26 s at worst) and fences the old primary.
#
# Fault injection (D4): docker stop / docker start of the k3d agent container, as in make failover-node. No exec.
# DOWN is longer than in L2, where the node returns as soon as a new leader holds the lock, so that the 30 s and
# 2 min alert delays elapse while the member is really gone.
. "$(dirname "$0")/l5-lib.sh"
DOWN=${DOWN:-180}; NODE=
cleanup() { [ -z "$NODE" ] || docker start "$NODE" >/dev/null 2>&1 || true; rm -f "$BODY" "$CHECKS"; }
trap cleanup EXIT
client_up
patroni_healthy || die "Patroni not healthy before the test"
EXPECT="MemberDown ReplicaNotStreaming FailoverOccurred"

section "Before"
OLD=$(leader); NODE=$(pod_node "$OLD"); TL0=$(promv 'max(patroni_postgres_timeline{namespace="pg-ha"})')
TAIL=10 run "am_lines"
check "No warning or critical alert firing before the fault" test "$(am_json | jq '[.[] | select(.labels.severity != "info")] | length')" = 0
note "Primary \`$OLD\` on \`$NODE\`, timeline $TL0. CoreDNS on: $(coredns_nodes)."

section "Fault"
T_FAULT=$(date +%s); docker stop "$NODE" >/dev/null
note "\`docker stop $NODE\` at $(ts "$T_FAULT") UTC. Held for $DOWN s."
T_NEW=; NEW=
end=$((SECONDS + DOWN)); NP=0; MP=0
while [ $SECONDS -lt $end ]; do
  [ -n "$T_NEW" ] || { l=$(leader); [ -n "$l" ] && [ "$l" != "$OLD" ] && { NEW=$l; T_NEW=$(date +%s); }; }
  am_has NoPrimary && NP=1; am_has MultiplePrimaries && MP=1
  wait_alerts firing 0 $EXPECT >/dev/null 2>&1 || true
  sleep 5
done
section "Alertmanager at the end of the outage (make alerts)"
TAIL=20 run "scripts/alerts.sh"
FIRING=$(am_json)
for a in MemberDown ReplicaNotStreaming; do
  check "$a firing while the node is down" jq -e --arg a "$a" 'any(.[]; .labels.alertname == $a)' <<<"$FIRING"
done
check "MemberDown names the old primary $OLD" jq -e --arg p "$OLD" 'any(.[]; .labels.alertname == "MemberDown" and .labels.pod == $p)' <<<"$FIRING"
check "FailoverOccurred fired (new primary ${NEW:-none})" test -n "${SEEN_FailoverOccurred:-}"
check "A new primary took over (${NEW:-none}, $(dt "$T_FAULT" "$T_NEW") s after the fault)" test -n "$NEW"

section "Recovery"
T_START=$(date +%s); docker start "$NODE" >/dev/null; NODE_STARTED=$NODE; NODE=
end=$((SECONDS + 300)); T_HEALTHY=
while [ $SECONDS -lt $end ]; do patroni_healthy && { T_HEALTHY=$(date +%s); break; }; am_has NoPrimary && NP=1; am_has MultiplePrimaries && MP=1; sleep 3; done
check "Cluster healthy again: 1 leader, 2 streaming, 1 sync ($(dt "$T_START" "$T_HEALTHY") s after docker start)" test -n "$T_HEALTHY"
# FailoverOccurred clears 5 min after the promotion; the others once the member streams again.
wait_alerts resolved 600 $EXPECT && RES=1 || RES=0
am_has NoPrimary && NP=1; am_has MultiplePrimaries && MP=1
check "MemberDown, ReplicaNotStreaming and FailoverOccurred all resolved" test "$RES" = 1
check "NoPrimary never fired (failover finished within its 45 s delay)" test "$NP" = 0
check "MultiplePrimaries never fired" test "$MP" = 0
TAIL=10 run "am_lines"
check "No warning or critical alert firing at the end" test "$(am_json | jq '[.[] | select(.labels.severity != "info")] | length')" = 0
run "patroni_cluster | jq -r '.members[] | \"\(.name) role=\(.role) state=\(.state) timeline=\(.timeline)\"'"

row() { printf '| %s | %s | %s | %s | %s |\n' "$1" "$(ts "$(eval echo "\${SEEN_$1:-}")")" "$(dt "$T_FAULT" "$(eval echo "\${SEEN_$1:-}")")" "$(ts "$(eval echo "\${GONE_$1:-}")")" "$(dt "$T_FAULT" "$(eval echo "\${GONE_$1:-}")")"; }
cat >> "$BODY" <<EOF

## Timeline

Times are UTC. Alertmanager was polled every 5 s through the API server's service proxy, so each time is accurate to about 5 s. Alert delays add the scrape interval (10 s), the rule evaluation interval (10 s) and Alertmanager's group_wait (10 s) to each rule's \`for\`.

<!-- summary -->
| Event | Time | Seconds after fault |
|---|---|---:|
| docker stop $NODE_STARTED (primary $OLD) | $(ts "$T_FAULT") | 0 |
| New primary $NEW holds the lock | $(ts "$T_NEW") | $(dt "$T_FAULT" "$T_NEW") |
| docker start | $(ts "$T_START") | $(dt "$T_FAULT" "$T_START") |
| Cluster healthy (3 members, sync standby) | $(ts "$T_HEALTHY") | $(dt "$T_FAULT" "$T_HEALTHY") |

| Alert | First seen firing | s after fault | Gone | s after fault |
|---|---|---:|---|---:|
$(row MemberDown)
$(row ReplicaNotStreaming)
$(row FailoverOccurred)
<!-- /summary -->

Alertmanager's full alert objects at the end of the outage:

\`\`\`json
$(jq '[.[] | {alertname: .labels.alertname, severity: .labels.severity, pod: .labels.pod, startsAt, summary: .annotations.summary}]' <<<"$FIRING")
\`\`\`
EOF
l5_finish alerts-failover "Alerts on a node failover (R10.3)" \
  "\`docker stop\` of the primary's k3d agent for $DOWN s, then \`docker start\`. MemberDown, ReplicaNotStreaming and FailoverOccurred must fire in Alertmanager and then resolve. NoPrimary and MultiplePrimaries must stay silent. Read from the Alertmanager API through the API server's service proxy." alerts-failover
