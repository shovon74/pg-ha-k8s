#!/usr/bin/env bash
# Regenerates docs/evidence/L4-restore.md from the per-part files in docs/evidence/L4/.
. "$(dirname "$0")/../scripts/spikes/lib.sh"
PARTS="restore-full:Full restore into an empty namespace (R5.1)
pitr:Point-in-time recovery (R5.3)
restore-test:Restore test Job, on demand (R4.5, R5.4)
restore-scheduled:Restore test Job, scheduled (R4.5)"
{ printf '# L4: restore, PITR and restore verification\n\nGenerated from the per-part files in [`L4/`](L4/) each time a part runs. Timestamps are UTC.\n\n'
  [ ! -f "$EV_DIR/L4-restore-history.md" ] || printf 'Hand-written notes: [`L4-restore-history.md`](L4-restore-history.md).\n\n'
  printf '| Part | Result | Checks passed | Details |\n|---|---|---:|---|\n'
  while IFS=: read -r f t; do
    if [ -f "$EV_DIR/L4/$f.md" ]; then
      r=$(grep -m1 -oE 'Result: (PASS|FAIL)' "$EV_DIR/L4/$f.md" | cut -d' ' -f2)
      p=$(grep -c '| PASS |$' "$EV_DIR/L4/$f.md" || true); n=$(grep -cE '\| (PASS|\*\*FAIL\*\*) \|$' "$EV_DIR/L4/$f.md" || true)
      printf '| %s | %s | %s of %s | [`L4/%s.md`](L4/%s.md) |\n' "$t" "$r" "$p" "$n" "$f" "$f"
    else printf '| %s | Not run yet | | |\n' "$t"; fi
  done <<<"$PARTS"
  while IFS=: read -r f t; do
    [ -f "$EV_DIR/L4/$f.md" ] || continue
    printf '\n## %s\n\n' "$t"; sed -n '/^- \*\*What:\*\*/p' "$EV_DIR/L4/$f.md"; printf '\n'
    sed -n '/^## Checks/,/^## /p' "$EV_DIR/L4/$f.md" | sed '1,2d' | grep '^|'
  done <<<"$PARTS"; } > "$EV_DIR/L4-restore.md"
