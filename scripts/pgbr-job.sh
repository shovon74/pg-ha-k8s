#!/usr/bin/env bash
# Runs one Job from the pg-backup CronJob template (or CRONJOB=pg-restore-test, L4) and waits for it. No exec (D4).
#   [CRONJOB=name] scripts/pgbr-job.sh NAME [COMMAND] [ENV=VALUE...]
# Without COMMAND (or with an empty one) the Job runs the CronJob's own backup script, as make backup does.
# Prints the Job's log, and exits non-zero if the Job failed.
# L6 step 0: a Job with its own COMMAND (stanza-create, check) is a helper, not a run of the CronJob. It gets
# no ownerReference, so the CronJob's history limit never counts it and it cannot evict the record of the
# last real backup Job (which would raise a false BackupStale). It is labelled pg-ha/job-kind=helper and
# deletes itself a day after it finishes. Its pods keep the CronJob's pod labels, so the same
# NetworkPolicies apply.
. "$(dirname "$0")/lib.sh"
name=$1; cmd=${2:-}; shift; [ $# -eq 0 ] || shift
envs=$(printf '%s\n' "$@" | jq -Rn '[inputs | select(length > 0) | split("=") | {name: .[0], value: (.[1:] | join("="))}]')
kubectl -n "$PG_NS" delete job "$name" --ignore-not-found --wait=true >/dev/null
kubectl -n "$PG_NS" create job "$name" --from=cronjob/${CRONJOB:-pg-backup} --dry-run=client -o json |
  jq --arg cmd "$cmd" --argjson envs "$envs" '
    .spec.template.spec.containers[0] |= ((if $cmd == "" then . else .command = ["bash", "-ec", $cmd] end) | .env += $envs)
    | if $cmd == "" then . else
        del(.metadata.ownerReferences) | del(.metadata.annotations["cronjob.kubernetes.io/instantiate"])
        | .metadata.labels["pg-ha/job-kind"] = "helper" | .spec.ttlSecondsAfterFinished = 86400
      end' |
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
