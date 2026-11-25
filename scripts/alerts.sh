#!/usr/bin/env bash
# L5: lists the alerts Alertmanager currently holds, read through the API server's service proxy (no exec,
# no port-forward). ALL=1 also lists Prometheus's pending alerts (condition true, 'for' not yet elapsed).
. "$(dirname "$0")/lib.sh"
P=/api/v1/namespaces/monitoring/services
am=$(kubectl get --raw "$P/alertmanager:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false") ||
  die "Alertmanager not reachable, run: make monitoring"
printf 'Firing alerts in Alertmanager at %s (UTC):\n' "$(date -u +%FT%TZ)"
n=$(jq length <<<"$am")
if [ "$n" = 0 ]; then echo "  none"
else jq -r 'sort_by(.labels.severity, .labels.alertname)[] |
  "  \(.labels.severity | ascii_upcase | .[0:4])  \(.labels.alertname)\(if .labels.lag then "/" + .labels.lag else "" end)  since \(.startsAt[0:19])Z  \(.annotations.summary)"' <<<"$am"; fi
if [ "${ALL:-0}" = 1 ]; then
  printf '\nPending in Prometheus:\n'
  kubectl get --raw "$P/prometheus:9090/proxy/api/v1/alerts" |
    jq -r '[.data.alerts[] | select(.state == "pending")] | if length == 0 then "  none" else .[] | "  \(.labels.alertname)  since \(.activeAt[0:19])Z" end'
fi
