#!/usr/bin/env bash
# Shared helpers for the L5 monitoring tests. Each test writes docs/evidence/L5/<part>.md, then regenerates
# docs/evidence/L5-monitoring.md. Prometheus and Alertmanager are read through the API server's service proxy,
# so no port-forward or exec is needed. SQL runs in the test client pod (tests/lib.sh, D4).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$EV_DIR/L5"
SVC=/api/v1/namespaces/monitoring/services
uri() { jq -rn --arg q "$1" '$q|@uri'; }
# promq QUERY: instant query, one line per series: {labels} value
promq() { kubectl get --raw "$SVC/prometheus:9090/proxy/api/v1/query?query=$(uri "$1")" |
  jq -r '.data.result[] | "\(.metric | del(.__name__) | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1])"'; }
# promv QUERY: the single value of a scalar-like query, or empty
promv() { kubectl get --raw "$SVC/prometheus:9090/proxy/api/v1/query?query=$(uri "$1")" | jq -r '.data.result[0].value[1] // empty'; }
# Alertmanager's active alerts as JSON, and one line per alert for the evidence.
am_json() { kubectl get --raw "$SVC/alertmanager:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false"; }
am_lines() { am_json | jq -r 'sort_by(.labels.alertname)[] | "\(.labels.alertname)\(if .labels.lag then "/" + .labels.lag else "" end) severity=\(.labels.severity) pod=\(.labels.pod // "-") startsAt=\(.startsAt)"'; }
am_has() { am_json | jq -e --arg a "$1" 'any(.[]; .labels.alertname == $a and .labels.namespace != "pg-restore")' >/dev/null; }

# wait_alerts STATE TIMEOUT ALERT...: polls Alertmanager every 5 s until every ALERT is firing (STATE=firing) or
# none is (STATE=resolved). Records first-seen and gone times in SEEN_<name> and GONE_<name> (epoch seconds).
wait_alerts() {
  local state=$1 end=$((SECONDS + $2)) a ok cur; shift 2
  while :; do
    cur=$(am_json 2>/dev/null | jq -r '.[] | select(.labels.namespace != "pg-restore") | .labels.alertname' | sort -u) || cur=
    ok=1
    for a in "$@"; do
      if grep -qx "$a" <<<"$cur"; then [ -n "$(eval echo "\${SEEN_$a:-}")" ] || eval "SEEN_$a=$(date +%s)"
        [ "$state" = firing ] || ok=0
      else [ -z "$(eval echo "\${SEEN_$a:-}")" ] || [ -n "$(eval echo "\${GONE_$a:-}")" ] || eval "GONE_$a=$(date +%s)"
        [ "$state" = resolved ] || ok=0
      fi
    done
    [ $ok = 1 ] && return 0
    [ $SECONDS -lt $end ] || return 1
    sleep 5
  done
}
# ts EPOCH: UTC clock time, or n/a
ts() { [ -n "${1:-}" ] && date -u -d "@$1" +%H:%M:%S || echo n/a; }
# Seconds between two epochs, or n/a
dt() { [ -n "${1:-}" ] && [ -n "${2:-}" ] && echo $(( $2 - $1 )) || echo n/a; }

l5_finish() { # part title description make-target
  local verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
  { printf '# L5: %s\n\n**Result: %s**\n\n' "$2" "$verdict"
    printf -- '- **What:** %s\n' "$3"
    printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make %s`\n' "$STARTED" "$((SECONDS-T0))" "$4"
    printf -- '- **Versions:** Prometheus `%s`, Alertmanager `%s`, postgres_exporter `%s`, image `%s`\n' "${PROMETHEUS_IMAGE%%@*}" "${ALERTMANAGER_IMAGE%%@*}" "${POSTGRES_EXPORTER_IMAGE%%@*}" "$PG_IMAGE"
    [ ! -f "$EV_DIR/L5-monitoring-history.md" ] || printf -- '- **History:** [`L5-monitoring-history.md`](../L5-monitoring-history.md) (maintained by hand)\n'
    printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L5/$1.md"
  "$ROOT_DIR/tests/l5-summary.sh"
  log "RESULT L5 $1: $verdict -> docs/evidence/L5/$1.md"
  rm -f "$BODY" "$CHECKS"
  [ "$FAILS" -eq 0 ]
}
