#!/usr/bin/env bash
# The only path that deletes ./secrets (ADR-009). Requires a typed confirmation on a terminal.
. "$(dirname "$0")/lib.sh"
[ -d "$SECRETS_DIR" ] || { log "No ./secrets directory, nothing to delete."; exit 0; }
cat >&2 <<MSG
WARNING: this permanently deletes ./secrets, including the pgBackRest cipher passphrase.
Every existing backup encrypted with it becomes UNRECOVERABLE.
MSG
[ -t 0 ] || die "refusing to run without an interactive terminal"
read -r -p "Type 'delete secrets' to continue: " answer
[ "$answer" = "delete secrets" ] || { log "Aborted. Nothing deleted."; exit 1; }
rm -rf -- "$SECRETS_DIR"
log "Deleted ./secrets."
