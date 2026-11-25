#!/usr/bin/env bash
# Runs one Job from the pg-backup CronJob template and waits for it. No exec (D4).
#   scripts/pgbr-job.sh NAME [COMMAND] [ENV=VALUE...]
# Without COMMAND (or with an empty one) the Job runs the CronJob's own backup script, as make backup does.
# Prints the Job's log, and exits non-zero if the Job failed.
. "$(dirname "$0")/lib.sh"
name=$1; cmd=${2:-}; shift; [ $# -eq 0 ] || shift
envs=$(printf '%s\n' "$@" | jq -Rn '[inputs | select(length > 0) | split("=") | {name: .[0], value: (.[1:] | join("="))}]')
kubectl -n "$PG_NS" delete job "$name" --ignore-not-found --wait=true >/dev/null
kubectl -n "$PG_NS" create job "$name" --from=cronjob/pg-backup --dry-run=client -o json |
  jq --arg cmd "$cmd" --argjson envs "$envs" '
    .spec.template.spec.containers[0] |= ((if $cmd == "" then . else .command = ["bash", "-ec", $cmd] end) | .env += $envs)' |
  kubectl -n "$PG_NS" apply -f - >/dev/null
end=$((SECONDS + ${JOB_WAIT:-1800}))
while :; do
  s=$(kubectl -n "$PG_NS" get job "$name" -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null || true)
  [ "${s%/*}" = 1 ] || [ "${s#*/}" = 1 ] && break
  [ $SECONDS -lt $end ] || { s=timeout; break; }
  sleep 2
done
kubectl -n "$PG_NS" logs "job/$name" 2>/dev/null || true
[ "${s%/*}" = 1 ]
