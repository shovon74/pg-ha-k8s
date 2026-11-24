#!/usr/bin/env bash
# Regenerates docs/evidence/L2-failover.md from the per-mode files in docs/evidence/L2/.
. "$(dirname "$0")/../scripts/spikes/lib.sh"
{ printf '# L2: failover, switchover and split-brain\n\nGenerated from the per-mode files in [`L2/`](L2/) each time a mode runs. Timestamps are UTC.\n\n'
  printf 'RTO is fault injection to the first commit acknowledged by a new primary, measured by a probe Job writing through pg-rw every 500 ms over new connections with a 2 s connect timeout. RPO is the number of acknowledged rows missing on the new primary. The target is RTO at most 30 s with safe settings (ttl 20, loop_wait 3, retry_timeout 5).\n'
  for f in pod node storage split-brain switchover api-outage; do
    [ -f "$EV_DIR/L2/$f.md" ] || { printf '\n## %s\n\nNot run yet.\n' "$f"; continue; }
    printf '\n## %s: %s\n\n' "$f" "$(grep -m1 -oE 'Result: (PASS|FAIL)' "$EV_DIR/L2/$f.md")"
    sed -n '/^- \*\*Fault:\*\*/p' "$EV_DIR/L2/$f.md"
    printf -- '- Details: [`L2/%s.md`](L2/%s.md)\n\n' "$f" "$f"
    sed -n '/^## Summary/,/^## Checks/p' "$EV_DIR/L2/$f.md" | sed '1d;$d'
  done; } > "$EV_DIR/L2-failover.md"
