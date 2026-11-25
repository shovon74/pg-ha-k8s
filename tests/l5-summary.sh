#!/usr/bin/env bash
# Regenerates docs/evidence/L5-monitoring.md from the per-part files in docs/evidence/L5/.
. "$(dirname "$0")/../scripts/spikes/lib.sh"
PARTS="alert-rules:Alert rule unit tests (R10.2)
metrics:Scrape targets, key series, lag measurement and resources (R10.1, R1.7)
alerts-failover:Alerts on a node failover (R10.3)
alerts-archive:Alerts on an object-storage outage (R10.3, R9.6)"
{ printf '# L5: monitoring and alerting\n\nGenerated from the per-part files in [`L5/`](L5/) each time a part runs. Timestamps are UTC. Design and alert table: [`../observability.md`](../observability.md).\n\n'
  [ ! -f "$EV_DIR/L5-monitoring-history.md" ] || printf 'Hand-written notes: [`L5-monitoring-history.md`](L5-monitoring-history.md).\n\n'
  printf '| Part | Result | Checks passed | Details |\n|---|---|---:|---|\n'
  while IFS=: read -r f t; do
    if [ -f "$EV_DIR/L5/$f.md" ]; then
      r=$(grep -m1 -oE 'Result: (PASS|FAIL)' "$EV_DIR/L5/$f.md" | cut -d' ' -f2)
      p=$(grep -c '| PASS |$' "$EV_DIR/L5/$f.md" || true); n=$(grep -cE '\| (PASS|\*\*FAIL\*\*) \|$' "$EV_DIR/L5/$f.md" || true)
      printf '| %s | %s | %s of %s | [`L5/%s.md`](L5/%s.md) |\n' "$t" "$r" "$p" "$n" "$f" "$f"
    else printf '| %s | Not run yet | | |\n' "$t"; fi
  done <<<"$PARTS"
  while IFS=: read -r f t; do
    [ -f "$EV_DIR/L5/$f.md" ] || continue
    printf '\n## %s\n\n' "$t"; sed -n '/^- \*\*What:\*\*/p' "$EV_DIR/L5/$f.md"; printf '\n'
    sed -n '/^## Checks/,/^## /p' "$EV_DIR/L5/$f.md" | sed '1,2d' | grep '^|'
    # Short result tables (timings, resources) marked for the summary.
    sed -n '/<!-- summary -->/,/<!-- \/summary -->/p' "$EV_DIR/L5/$f.md" | grep -v -- '<!--' || true
  done <<<"$PARTS"; } > "$EV_DIR/L5-monitoring.md"
