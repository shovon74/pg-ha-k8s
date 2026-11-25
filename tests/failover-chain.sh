#!/usr/bin/env bash
# L2/L3 chained scenario (ADR-008): the sequence that stalled WAL archiving in L3. A node failover, then a
# planned switchover back to the old primary, which by then has rejoined on the new timeline. When the old
# primary rejoined with pg_rewind, it held WAL files copied without archive status, and once it was primary
# again, archiving failed for good with "already exists in the repo1 archive with a different checksum".
# With rejoin by re-clone, archiving on the old primary must stay healthy.
#
# Every step runs tests/failover.sh with RUNS=1, so each has the full RTO, RPO, single-primary and archive
# health checks, with its evidence in L2/chain-node.md and L2/chain-switchover-N.md. In synchronous mode
# Patroni switches over only to the sync standby, so when the old primary is not the sync standby, the
# chain first switches over to whichever member is (at most 3 hops), until the old primary leads again. A
# manual failover to an async member would bypass that rule and is not used. This script then watches
# archiving on the returned primary over a second interval. No exec beyond the harness (D4).
. "$(dirname "$0")/lib.sh"
W=$(mktemp -d); trap 'rm -rf "$W" "$BODY" "$CHECKS"; kubectl -n "$NS" delete pod "$CLIENT" --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT
client_up
tl() { patroni_cluster | jq -r '.members[] | select(.role == "leader") | .timeline'; }
row() { sed -nE '/^\| 1 \|/p' "$1" | head -1; }
OLD=$(leader); TL0=$(tl)

section "Step 1: node failover"
note "Before: leader \`$OLD\`, timeline $TL0. Evidence: [\`chain-node.md\`](chain-node.md)."
RUNS=1 EV_OUT="$EV_DIR/L2/chain-node.md" "$ROOT_DIR/tests/failover.sh" node > "$W/1.log" 2>&1 && s1=1 || s1=0
run "grep -E '^run 1:|RESULT' $W/1.log" || true
check "Node failover run passed (RTO within target, RPO 0, one primary, rejoined, archive healthy)" test $s1 = 1
REJOIN=$(row "$EV_DIR/L2/chain-node.md" | awk -F'|' '{gsub(/ /, "", $10); print $10}')
client_up; MID=$(leader); TL1=$(tl)
note "After step 1: leader \`$MID\`, timeline $TL1. \`$OLD\` rejoined by: $REJOIN."

section "Step 2: switchover back to the old primary"
rm -f "$EV_DIR"/L2/chain-switchover*.md; HOPS=0; s2=1
while [ "$(leader)" != "$OLD" ] && [ $HOPS -lt 3 ]; do
  HOPS=$((HOPS + 1)); SYNC=$(sync_standby); TGT=$( [ "$SYNC" = "$OLD" ] && echo "$OLD" || echo "$SYNC")
  note "Hop $HOPS: leader \`$(leader)\`, sync standby \`$SYNC\`, switchover to \`$TGT\`. Evidence: [\`chain-switchover-$HOPS.md\`](chain-switchover-$HOPS.md)."
  RUNS=1 TO="$TGT" EV_OUT="$EV_DIR/L2/chain-switchover-$HOPS.md" "$ROOT_DIR/tests/failover.sh" switchover > "$W/2.log" 2>&1 || s2=0
  run "grep -E '^run 1:|RESULT' $W/2.log" || true
  client_up
  [ $s2 = 1 ] || break
done
check "Every switchover hop passed (RTO, RPO 0, one primary, archive health right after it), $HOPS hop(s)" test $s2 = 1
NOW=$(leader); TL2=$(tl); TLX=$(printf '%08X' "$TL2")
check "$OLD is the primary again, on timeline $TL2" test "$NOW" = "$OLD"

section "Archive health on the returned primary, second interval"
S0=$(archive_stat "$(member "$NOW")"); F0=$(awk '{print $1}' <<<"$S0")
archive_check "$(member "$NOW")" "$F0" "$ARCHIVE_BOUND"
READY=$(awk '{print $5}' <<<"$ARCH_STAT")
STALE=$(tr ',' '\n' <<<"$READY" | { grep -vE "^-$|^$TLX" || true; } | paste -sd, -)
note "Primary \`$NOW\`. Before: $(awk '{print "failed_count", $1 ", last archived", $3}' <<<"$S0"). After a WAL fill: archived in $ARCH_T s, failed_count +$ARCH_FAILED, last archived \`$(awk '{print $3}' <<<"$ARCH_STAT")\`, pending .ready: ${READY}."
run "q $(member "$NOW") monitor 'select failed_count, last_failed_wal, last_failed_time, archived_count, last_archived_wal, last_archived_time from pg_stat_archiver'" || true
check "No new archive failures on $NOW" test "$ARCH_FAILED" -le 0
check "A segment was archived within $ARCHIVE_BOUND s of a WAL fill" test "$ARCH_T" != n/a
check "No pending .ready segment from an older timeline (stale WAL from a rejoin)" test -z "$STALE"

verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
{ printf '# L2 failure mode: chain\n\n**Result: %s**\n\n' "$verdict"
  printf -- '- **Fault:** Node failover (`docker stop` of the primary'"'"'s agent), then a planned switchover back to the old primary after it has rejoined. This is the sequence that stalled WAL archiving in L3 when rejoin used `pg_rewind` (ADR-008). Archive health is checked on the returned primary.\n'
  printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make failover-chain`\n' "$STARTED" "$((SECONDS-T0))"
  printf -- '- **Versions:** k3s `%s`, image `%s`\n' "${K3S_IMAGE%@*}" "$PG_IMAGE"
  printf '\n## Summary\n\n| Step | Old primary | New primary | RTO (s) | Write gap (s) | Acked | RPO (acked rows missing) | Max primaries in one sample | Rejoin | Rejoin after fault (s) | CoreDNS node | Archive failures (new) | Archived after fill (s) | Result |\n|---|---|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---|\n'
  row "$EV_DIR/L2/chain-node.md" | sed 's/^| 1 |/| node |/'
  for f in "$EV_DIR"/L2/chain-switchover-*.md; do [ -f "$f" ] || continue; n=${f##*-}; row "$f" | sed "s/^| 1 |/| switchover ${n%.md} |/"; done
  printf '\nSecond interval on `%s`: archived %s s after a WAL fill, failed_count +%s, pending .ready `%s`.\n' "$NOW" "$ARCH_T" "$ARCH_FAILED" "$READY"
  printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L2/chain.md"
"$ROOT_DIR/tests/l2-summary.sh"
log "RESULT L2 chain: $verdict -> docs/evidence/L2/chain.md"
[ "$FAILS" -eq 0 ]
