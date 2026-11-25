#!/usr/bin/env bash
# Regenerates docs/evidence/L3-backup.md from the per-part files in docs/evidence/L3/.
. "$(dirname "$0")/../scripts/spikes/lib.sh"
PARTS="archive:Garage, pgBackRest, archiving and on-demand backup
scheduled:Scheduled backup (R4.1)
retention:Retention enforcement
failover:Backup after failover (R4.6)
garage-restart:Garage restart while writing"
{ printf '# L3: backup, archiving, retention and verification\n\nGenerated from the per-part files in [`L3/`](L3/) each time a part runs. Timestamps are UTC.\n\n'
  [ ! -f "$EV_DIR/L3-backup-history.md" ] || printf 'Hand-written notes: [`L3-backup-history.md`](L3-backup-history.md).\n\n'
  printf '| Part | Result | Checks passed | Details |\n|---|---|---:|---|\n'
  while IFS=: read -r f t; do
    if [ -f "$EV_DIR/L3/$f.md" ]; then
      r=$(grep -m1 -oE 'Result: (PASS|FAIL)' "$EV_DIR/L3/$f.md" | cut -d' ' -f2)
      p=$(grep -c '| PASS |$' "$EV_DIR/L3/$f.md" || true); n=$(grep -cE '\| (PASS|\*\*FAIL\*\*) \|$' "$EV_DIR/L3/$f.md" || true)
      printf '| %s | %s | %s of %s | [`L3/%s.md`](L3/%s.md) |\n' "$t" "$r" "$p" "$n" "$f" "$f"
    else printf '| %s | Not run yet | | |\n' "$t"; fi
  done <<<"$PARTS"
  while IFS=: read -r f t; do
    [ -f "$EV_DIR/L3/$f.md" ] || continue
    printf '\n## %s\n\n' "$t"; sed -n '/^- \*\*What:\*\*/p' "$EV_DIR/L3/$f.md"; printf '\n'
    sed -n '/^## Checks/,/^## /p' "$EV_DIR/L3/$f.md" | sed '1,2d' | grep '^|'
  done <<<"$PARTS"; } > "$EV_DIR/L3-backup.md"
