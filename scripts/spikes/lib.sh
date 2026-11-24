#!/usr/bin/env bash
# Spike harness: runs commands, records them with their output, and writes a PASS/FAIL evidence file.
# Any value from ./secrets/credentials is replaced by a visible placeholder before it reaches the file.
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SPIKE_DIR="$ROOT_DIR/scripts/spikes"
EV_DIR="$ROOT_DIR/docs/evidence"

redact() {
  python3 -I -c '
import glob, os, sys
data = sys.stdin.read()
for path in glob.glob(os.path.join(sys.argv[1], "*")):
    value = open(path).read().strip()
    if value:
        data = data.replace(value, "[REDACTED:" + os.path.basename(path) + "]")
sys.stdout.write(data)' "$SECRETS_DIR/credentials"
}

ev_start() { # id title question criteria
  SPIKE=$1; TITLE=$2; QUESTION=$3; CRITERIA=$4; NS="spike-$(echo "$1" | tr 'A-Z' 'a-z')"
  BODY=$(mktemp); CHECKS=$(mktemp); FAILS=0; T0=$SECONDS; STARTED=$(date -u +%FT%TZ)
  kubectl get ns "$NS" >/dev/null 2>&1 && kubectl delete ns "$NS" --wait=true >/dev/null
  trap ev_cleanup EXIT
}
ev_cleanup() {
  [ "${KEEP:-0}" = 1 ] || kubectl delete ns "$NS" --wait=false >/dev/null 2>&1 || true
  rm -f "$BODY" "$CHECKS"
}
section() { printf '\n## %s\n' "$1" >> "$BODY"; log "== $1"; }
run() { # command string; output is recorded. Returns the command's exit code.
  local out rc=0
  out=$(eval "$1" 2>&1) || rc=$?
  { printf '\n```console\n$ %s\n' "$1"; printf '%s\n' "$out"; [ $rc -eq 0 ] || printf '[exit code %s]\n' "$rc"; printf '```\n'; } | redact >> "$BODY"
  printf '%s\n' "$out" | redact | tail -"${TAIL:-12}"
  return $rc
}
note() { printf '\n%s\n' "$1" >> "$BODY"; }
check() { # description, command...
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then printf '| %s | PASS |\n' "$d" >> "$CHECKS"; log "PASS  $d"
  else printf '| %s | **FAIL** |\n' "$d" >> "$CHECKS"; log "FAIL  $d"; FAILS=$((FAILS+1)); fi
}
ev_finish() {
  local verdict=PASS; [ "$FAILS" -eq 0 ] || verdict=FAIL
  local f="$EV_DIR/L0-spike-$SPIKE.md"; mkdir -p "$EV_DIR"
  { printf '# L0 spike %s: %s\n\n**Result: %s**\n\n' "$SPIKE" "$TITLE" "$verdict"
    printf -- '- **Question:** %s\n- **Pass criteria:** %s\n' "$QUESTION" "$CRITERIA"
    printf -- '- **Run:** %s (UTC), %s s\n- **Reproduce:** `make spike-%s`\n' "$STARTED" "$((SECONDS-T0))" "$(echo "$SPIKE" | tr 'A-Z' 'a-z')"
    printf -- '- **Versions:** k3s `%s`, image `%s`\n' "${K3S_IMAGE%@*}" "$PG_IMAGE"
    [ ! -f "$EV_DIR/L0-spike-$SPIKE-history.md" ] || printf -- '- **History:** [`L0-spike-%s-history.md`](L0-spike-%s-history.md) (maintained by hand, never written by this harness)\n' "$SPIKE" "$SPIKE"
    printf '\n## Checks\n\n| Check | Result |\n|---|---|\n'; cat "$CHECKS"; cat "$BODY"; } | redact > "$f"
  log "RESULT $SPIKE: $verdict -> docs/evidence/L0-spike-$SPIKE.md"
  [ "$FAILS" -eq 0 ]
}
wait_job() { # job timeout-seconds; succeeds only if the Job completes
  local end=$((SECONDS+$2)) s f
  while [ $SECONDS -lt $end ]; do
    s=$(kubectl -n "$NS" get job "$1" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
    f=$(kubectl -n "$NS" get job "$1" -o jsonpath='{.status.failed}' 2>/dev/null || true)
    [ "${s:-0}" -ge 1 ] && return 0; [ "${f:-0}" -ge 1 ] && return 1; sleep 1
  done; return 1
}
apply_yaml() { sed "s|__IMAGE__|$PG_IMAGE|g; s|__NS__|$NS|g" | kubectl -n "$NS" apply -f - ; }
