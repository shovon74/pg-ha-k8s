#!/usr/bin/env bash
# Generates credentials into ./secrets. Never overwrites, and never prints a value.
. "$(dirname "$0")/lib.sh"
umask 077
mkdir -p "$SECRETS_DIR/credentials"; chmod 700 "$SECRETS_DIR" "$SECRETS_DIR/credentials"
created=0; kept=0

gen() { # name openssl-rand-args...
  local f="$SECRETS_DIR/credentials/$1" tmp; shift
  if [ -s "$f" ]; then kept=$((kept+1)); return; fi
  tmp=$(mktemp "$f.XXXXXX")
  openssl rand "$@" | tr -d '\n' > "$tmp"
  # ln fails if the target exists, so a concurrent run cannot replace a value.
  if ln "$tmp" "$f" 2>/dev/null; then created=$((created+1)); else kept=$((kept+1)); fi
  rm -f "$tmp"
}

for r in postgres replicator rewind monitor backup app app_ro; do gen "pg-$r-password" -hex 24; done
gen pg-restapi-password -hex 24     # L6: basic auth for Patroni's state-changing REST endpoints
gen pgbackrest-cipher-passphrase -base64 48
gen garage-rpc-secret -hex 32        # Garage requires exactly 32 bytes in hex
gen garage-admin-token -hex 32
gen garage-metrics-token -hex 32
gen garage-s3-secret-key -hex 32     # Garage requires 32 bytes in hex

# Garage access key IDs are GK + 12 bytes in hex.
f="$SECRETS_DIR/credentials/garage-s3-access-key-id"
if [ -s "$f" ]; then kept=$((kept+1)); else
  tmp=$(mktemp "$f.XXXXXX"); printf 'GK%s' "$(openssl rand -hex 12)" > "$tmp"
  if ln "$tmp" "$f" 2>/dev/null; then created=$((created+1)); else kept=$((kept+1)); fi
  rm -f "$tmp"
fi
log "Secrets: $created created, $kept kept (in ./secrets/credentials, values not shown)"
