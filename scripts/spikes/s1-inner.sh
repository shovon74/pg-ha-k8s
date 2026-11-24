#!/bin/bash
# Runs inside the spike pod. Exercises pgBackRest against Garage end to end. Prints no credentials.
set -euo pipefail
export PGHOST=/tmp PGUSER=postgres
S=s1
step() { printf '\n--- %s\n' "$1"; }
mkdir -p /work/log /work/lock /work/spool
sql() { psql -d postgres -v ON_ERROR_STOP=1 -Atc "$1"; }

step "pgBackRest config in use (credentials come from environment variables)"
pgbackrest version
grep -h '^repo1-' /etc/pgbackrest/conf.d/repo.conf

step "initdb and start Postgres with WAL archiving through pgBackRest"
mkdir -m 0700 /work/pgdata
initdb -D /work/pgdata --data-checksums --auth-local=trust --auth-host=reject >/dev/null
cat >> /work/pgdata/postgresql.conf <<CONF
listen_addresses = ''
unix_socket_directories = '/tmp'
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=$S archive-push %p'
CONF
pg_ctl -D /work/pgdata -l /work/pg.log -w start >/dev/null

step "stanza-create"
pgbackrest --stanza=$S --log-level-console=warn stanza-create; echo STANZA_OK

step "check (proves WAL archiving reaches the repository)"
pgbackrest --stanza=$S --log-level-console=warn check; echo CHECK_OK

step "write data, then take a full backup"
sql "create table marker as select g id, md5(g::text) v from generate_series(1,200000) g" >/dev/null
pgbackrest --stanza=$S --type=full --start-fast --log-level-console=warn backup; echo BACKUP_OK

step "write more data after the backup, which only archived WAL can restore"
sql "insert into marker select g, md5(g::text) from generate_series(200001,250000) g" >/dev/null
EXPECT=$(sql "select count(*) || ':' || md5(string_agg(v, '' order by id)) from marker")
echo "source: $EXPECT"
LSN=$(sql "select pg_walfile_name(pg_switch_wal())")
echo "switched WAL segment: $LSN"
for _ in $(seq 1 60); do
  A=$(sql "select coalesce(last_archived_wal,'') from pg_stat_archiver")
  [[ "$A" > "$LSN" || "$A" == "$LSN" ]] && break; sleep 1
done
echo "last archived: $A"
[[ "$A" > "$LSN" || "$A" == "$LSN" ]]; echo ARCHIVE_OK
sql "select 'archived=' || archived_count || ' failed=' || failed_count from pg_stat_archiver"

step "pgbackrest info"
pgbackrest --stanza=$S info

step "pgbackrest verify (the exit code alone is not trusted, the reported status must be ok)"
V=$(pgbackrest --stanza=$S --log-level-console=info --verbose verify 2>&1 || true)
printf '%s\n' "$V" | grep -E 'status:|archiveId|backup:|checked|missing|checksum invalid|size invalid|other' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +[A-Z]+: //; s/^ +//'
printf '%s\n' "$V" | grep -q 'status: ok'; echo VERIFY_OK

step "encryption: raw object is ciphertext, right passphrase reads it, wrong one cannot"
F=backup/$S/backup.info
pgbackrest --stanza=$S --log-level-console=error repo-get --raw "$F" > /work/raw.bin
RAW=$(head -c 8 /work/raw.bin); echo "raw header: $RAW"
pgbackrest --stanza=$S --log-level-console=error repo-get "$F" > /work/plain.bin
PLAIN=$(head -c 9 /work/plain.bin); echo "decrypted header: $PLAIN"
if PGBACKREST_REPO1_CIPHER_PASS=wrong-passphrase pgbackrest --stanza=$S --log-level-console=off --log-level-stderr=off repo-get "$F" >/dev/null 2>&1
then WRONG=read; else WRONG=refused; fi
echo "wrong passphrase: $WRONG"
[ "$RAW" = "Salted__" ] && [ "$PLAIN" = "[backrest" ] && [ "$WRONG" = refused ]; echo CIPHER_OK

step "stop the source and destroy its data directory, then restore"
pg_ctl -D /work/pgdata -m fast -w stop >/dev/null
rm -rf /work/pgdata; mkdir -m 0700 /work/pgdata
pgbackrest --stanza=$S --log-level-console=warn --type=default --archive-mode=off restore; echo RESTORE_OK
pg_ctl -D /work/pgdata -l /work/restore.log -w -t 120 start >/dev/null
for _ in $(seq 1 60); do [ "$(sql 'select pg_is_in_recovery()')" = f ] && break; sleep 1; done
GOT=$(sql "select count(*) || ':' || md5(string_agg(v, '' order by id)) from marker")
echo "restored: $GOT"
[ "$GOT" = "$EXPECT" ]; echo DATA_MATCH_OK
sql "select 'in_recovery=' || pg_is_in_recovery() || ' timeline=' || (select timeline_id from pg_control_checkpoint())"
pg_amcheck --all --install-missing --heapallindexed -h /tmp -U postgres; echo AMCHECK_OK
pg_ctl -D /work/pgdata -m fast -w stop >/dev/null
echo SPIKE_INNER_DONE
