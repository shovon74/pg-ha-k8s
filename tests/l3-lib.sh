#!/usr/bin/env bash
# Shared helpers for the L3 backup tests. Each test writes docs/evidence/L3/<part>.md and then regenerates
# docs/evidence/L3-backup.md. Repository commands run in Jobs made from the pg-backup CronJob template
# (scripts/pgbr-job.sh), never by exec. SQL runs in the test client pod, as in L1 and L2.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$EV_DIR/L3"
pgbr() { JOB_WAIT=${JOB_WAIT:-900} "$ROOT_DIR/scripts/pgbr-job.sh" "$@"; }
# pgBackRest info as JSON, from a short Job. Prints only the JSON line.
pgbr_info() { local j=pg-info-$RANDOM o; o=$(pgbr "$j" 'pgbackrest --stanza=main --output=json info') || true
  kubectl -n "$NS" delete job "$j" --wait=false >/dev/null 2>&1 || true; grep -m1 '^\[' <<<"$o"; }
archiver() { q "$RW" monitor "select archived_count, failed_count, coalesce(last_archived_wal, '-'), coalesce(extract(epoch from last_archived_time)::text, '0'), coalesce(extract(epoch from last_failed_time)::text, '0') from pg_stat_archiver"; }
# Waits until pg_stat_archiver on the primary shows a segment archived after epoch T. archive_timeout (60 s)
# closes a segment on any primary with writes, so no superuser call is needed. Prints the archive epoch.
archived_after() { # T timeout
  local end=$((SECONDS + $2)) r; while [ $SECONDS -lt $end ]; do
    r=$(archiver 2>/dev/null | awk -v t="$1" '$4 > t {print $4}') && [ -n "$r" ] && { echo "$r"; return 0; }; sleep 1
  done; return 1; }

l3_finish() { # part title description
  local verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
  { printf '# L3: %s\n\n**Result: %s**\n\n' "$2" "$verdict"
    printf -- '- **What:** %s\n' "$3"
    printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make %s`\n' "$STARTED" "$((SECONDS-T0))" "$4"
    printf -- '- **Versions:** k3s `%s`, image `%s`, Garage `%s`\n' "${K3S_IMAGE%%@*}" "$PG_IMAGE" "${GARAGE_IMAGE%%@*}"
    [ ! -f "$EV_DIR/L3-backup-history.md" ] || printf -- '- **History:** [`L3-backup-history.md`](../L3-backup-history.md) (maintained by hand)\n'
    printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L3/$1.md"
  "$ROOT_DIR/tests/l3-summary.sh"
  log "RESULT L3 $1: $verdict -> docs/evidence/L3/$1.md"
  rm -f "$BODY" "$CHECKS"
  [ "$FAILS" -eq 0 ]
}
