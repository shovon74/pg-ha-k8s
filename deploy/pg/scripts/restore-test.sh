#!/bin/bash
# Restore test body (ADR-010, R4.5, R5.4). One Job template, run by the pg-restore-test CronJob and by
# make test-restore. Restores the newest backup into this pod's emptyDir, to the backup's consistent end
# point, starts Postgres with no TCP listener (Unix socket in /tmp only, and no Service), and compares the
# data fingerprint that the backup Job recorded as pgBackRest annotations at backup time. Then runs
# pg_amcheck with --install-missing, which is acceptable only on this scratch copy. Exits non-zero on any
# failure. Nothing is written to the repository: archive_mode is off in the scratch instance.
set -euo pipefail
S=/scratch/pgdata; export PGHOST=/tmp PGPORT=5432 PGUSER=postgres
say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
fail() { say "RESTORE_TEST_FAILED: $*"; [ ! -f /tmp/pg.log ] || tail -20 /tmp/pg.log; exit 1; }
T0=$(date +%s)
LABEL=$(pgbackrest --stanza=main --output=json info | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["backup"][-1]["label"])') || fail "no backup in the repository"
pgbackrest --stanza=main --set="$LABEL" --output=json info | python3 -c '
import json, sys
b = json.load(sys.stdin)[0]["backup"][-1]
for k, v in sorted((b.get("annotation") or {}).items()): print(f"{k}={v}")' > /tmp/expected
say "restoring backup $LABEL to its consistent end point (--type=immediate)"
[ -s /tmp/expected ] || fail "backup $LABEL has no fingerprint annotations (taken before L4?)"
# Test hook, used only by tests/l4-restore-test.sh to prove the Job fails loudly on bad data.
[ "${RESTORE_TEST_INJECT_MISMATCH:-}" != 1 ] || { sed -i '$s/=.*/=injected-mismatch/' /tmp/expected; say "TEST HOOK: one expected value replaced"; }
pgbackrest --stanza=main --set="$LABEL" --type=immediate --target-action=promote --log-level-console=warn restore || fail "pgbackrest restore"
# The restored postgresql.conf is Patroni's and points at files this pod does not have, so it is replaced.
cat > "$S/postgresql.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '/tmp'
port = 5432
archive_mode = off
# max_connections, max_wal_senders, max_replication_slots and max_worker_processes stay at their defaults,
# which equal the primary's: recovery refuses to start when any is lower than on the primary.
shared_buffers = 64MB
hba_file = '$S/pg_hba.conf'
ident_file = '$S/pg_ident.conf'
CONF
echo 'local all postgres peer' > "$S/pg_hba.conf"; : > "$S/pg_ident.conf"
pg_ctl -D "$S" -l /tmp/pg.log -w -t 900 start >/dev/null || fail "Postgres did not start"
for _ in $(seq 1 300); do [ "$(psql -XAtqc 'select pg_is_in_recovery()' 2>/dev/null)" = f ] && break; sleep 1; done
[ "$(psql -XAtqc 'select pg_is_in_recovery()')" = f ] || fail "recovery did not finish"
say "recovered and promoted in $(( $(date +%s) - T0 )) s; $(grep -m1 -E 'recovery stopping|consistent recovery state' /tmp/pg.log | sed -E 's/^.*LOG: +//')"
# Fingerprint, computed exactly as backup-job.sh computes it.
psql -d app -XAtq -v ON_ERROR_STOP=1 -f /scripts/fingerprint.sql > /tmp/actual || fail "fingerprint query"
say "expected (recorded at backup time) vs restored:"
join -t= -a1 -a2 -e MISSING -o 0,1.2,2.2 <(sort /tmp/expected) <(sort /tmp/actual) | awk -F= '{s = ($2 == $3) ? "PASS" : "FAIL"; printf "%-26s %-22s %-22s %s\n", $1, $2, $3, s; if (s == "FAIL") bad = 1} END {exit bad}' \
  || fail "fingerprint mismatch"
say "pg_amcheck --install-missing (scratch instance only)"
pg_amcheck --all --install-missing --heapallindexed --progress 2>&1 | tail -2 || fail "pg_amcheck found corruption"
pg_ctl -D "$S" -m fast stop >/dev/null
say "RESTORE_TEST_OK backup=$LABEL total=$(( $(date +%s) - T0 ))s"
