#!/usr/bin/env bash
# Shared helpers for the L4 restore tests. Each test writes docs/evidence/L4/<part>.md, then regenerates
# docs/evidence/L4-restore.md. SQL runs in the test client pod in pg-ha (no exec in a Postgres pod); it
# reaches the restored cluster through its pg-rw Service in pg-restore. Repository reads run in Jobs.
. "$(dirname "${BASH_SOURCE[0]}")/l3-lib.sh"
mkdir -p "$EV_DIR/L4"
RNS=pg-restore; RRW=pg-rw.$RNS.svc.cluster.local
# The data fingerprint of fingerprint.sql (seeded branch), as one statement for the test client.
FP_SQL="select 'rows.pgbench_accounts=' || count(*) from pgbench_accounts
union all select 'sum.pgbench_accounts=' || sum(hashtext(a::text)::bigint) from pgbench_accounts a
union all select 'rows.pgbench_branches=' || count(*) from pgbench_branches
union all select 'sum.pgbench_branches=' || sum(hashtext(b::text)::bigint) from pgbench_branches b
union all select 'rows.pgbench_tellers=' || count(*) from pgbench_tellers
union all select 'sum.pgbench_tellers=' || sum(hashtext(t::text)::bigint) from pgbench_tellers t"
rpatroni() { local i; for i in 0 1 2; do kubectl get --raw "/api/v1/namespaces/$RNS/pods/pg-$i:8008/proxy/cluster" 2>/dev/null && return 0; done; return 1; }
rleader() { rpatroni | jq -r '.members[] | select(.role == "leader") | .name'; }
# History files in the repository archive, from a short Job (repo-ls). Prints one name per line.
repo_history() { local j=pg-repo-ls-$RANDOM o; o=$(pgbr "$j" 'pgbackrest --stanza=main --output=text repo-ls archive/main/17-1') || true
  kubectl -n "$NS" delete job "$j" --wait=false >/dev/null 2>&1 || true; grep -E '^[0-9A-F]{8}\.history$' <<<"$o" || true; }
repo_wal_dirs() { local j=pg-repo-ls-$RANDOM o; o=$(pgbr "$j" 'pgbackrest --stanza=main --output=text repo-ls archive/main/17-1') || true
  kubectl -n "$NS" delete job "$j" --wait=false >/dev/null 2>&1 || true; grep -E '^[0-9A-F]{16}$' <<<"$o" || true; }

l4_finish() { # part title description make-target
  local verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
  { printf '# L4: %s\n\n**Result: %s**\n\n' "$2" "$verdict"
    printf -- '- **What:** %s\n' "$3"
    printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make %s`\n' "$STARTED" "$((SECONDS-T0))" "$4"
    printf -- '- **Versions:** k3s `%s`, image `%s`, Garage `%s`\n' "${K3S_IMAGE%%@*}" "$PG_IMAGE" "${GARAGE_IMAGE%%@*}"
    [ ! -f "$EV_DIR/L4-restore-history.md" ] || printf -- '- **History:** [`L4-restore-history.md`](../L4-restore-history.md) (maintained by hand)\n'
    printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$EV_DIR/L4/$1.md"
  "$ROOT_DIR/tests/l4-summary.sh"
  log "RESULT L4 $1: $verdict -> docs/evidence/L4/$1.md"
  rm -f "$BODY" "$CHECKS"
  [ "$FAILS" -eq 0 ]
}
