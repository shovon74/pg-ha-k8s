#!/bin/bash
# Backup CronJob body (ADR-009): full backup, then expire, then verify. Exits non-zero unless verify
# reports status ok, because verify can exit 0 while reporting status error (L0 finding, spike S1).
set -euo pipefail
S=main
say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
say "full backup"
pgbackrest --stanza=$S --type=full --log-level-console=info backup > /tmp/backup.log 2>&1 || { cat /tmp/backup.log; say BACKUP_FAILED; exit 1; }
grep -E 'new backup label|full backup size|backup start archive|backup stop archive' /tmp/backup.log || true
say "expire (repo1-retention-full from repo.conf, or PGBACKREST_REPO1_RETENTION_FULL for a test)"
pgbackrest --stanza=$S --log-level-console=info expire > /tmp/expire.log 2>&1 || { cat /tmp/expire.log; say EXPIRE_FAILED; exit 1; }
grep -E 'expire|remove' /tmp/expire.log | grep -v 'command (begin|end)' || true
say "verify"
rc=0; V=$(pgbackrest --stanza=$S --log-level-console=info --verbose verify 2>&1) || rc=$?
printf '%s\n' "$V" | grep -E 'status:|archiveId:|backup:|checksum invalid|size invalid|missing|other' | sed -E 's/^[0-9-]+ [0-9:.]+ +P[0-9]+ +[A-Z]+: //; s/^ +//'
if [ $rc -ne 0 ] || ! grep -q 'status: ok' <<<"$V" || grep -q 'status: error' <<<"$V"; then
  say "VERIFY_FAILED (exit $rc)"; exit 1
fi
say VERIFY_OK
pgbackrest --stanza=$S info
say BACKUP_JOB_OK
